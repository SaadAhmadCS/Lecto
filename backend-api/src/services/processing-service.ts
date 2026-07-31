import { prisma } from '../config/database.js';
import { transcribeAudioChunk, generateSummary } from './gemini-service.js';

// Processing status pipeline:
// pending → transcribing → transcribed → assembling → assembled → summarizing → completed
// At any stage: → failed_transcription | failed_assembly | failed_summary

export type ProcessingStage =
  | 'pending'
  | 'transcribing'
  | 'transcribed'
  | 'assembling'
  | 'assembled'
  | 'summarizing'
  | 'completed'
  | 'failed_transcription'
  | 'failed_assembly'
  | 'failed_summary';

/**
 * Process a complete recording through the full pipeline.
 *
 * 1. Transcribe each chunk
 * 2. Assemble into full transcript
 * 3. Generate AI summary/notes
 */
export async function processRecording(recordingId: string, userId: string): Promise<void> {
  console.log(`📝 Starting processing for recording ${recordingId}`);

  // Verify recording exists and belongs to user
  const recording = await prisma.recording.findFirst({
    where: { id: recordingId, userId },
    include: {
      chunks: { orderBy: { sequenceNumber: 'asc' } },
    },
  });

  if (!recording) {
    throw new Error(`Recording ${recordingId} not found`);
  }

  if (recording.chunks.length === 0) {
    throw new Error('No audio chunks to process');
  }

  // Stage 1: Transcribe each chunk
  await updateProcessingStatus(recordingId, 'transcribing');

  try {
    await transcribeAllChunks(recordingId, recording.chunks);
    await updateProcessingStatus(recordingId, 'transcribed');
  } catch (error) {
    console.error(`❌ Transcription failed for ${recordingId}:`, error);
    await updateProcessingStatus(recordingId, 'failed_transcription');
    throw error;
  }

  // Stage 2: Assemble full transcript
  await updateProcessingStatus(recordingId, 'assembling');

  try {
    await assembleTranscript(recordingId, recording.title);
    await updateProcessingStatus(recordingId, 'assembled');
  } catch (error) {
    console.error(`❌ Assembly failed for ${recordingId}:`, error);
    await updateProcessingStatus(recordingId, 'failed_assembly');
    throw error;
  }

  // Stage 3: Generate summary/notes
  await updateProcessingStatus(recordingId, 'summarizing');

  try {
    await generateNotesFromTranscript(recordingId, recording.title);
    await updateProcessingStatus(recordingId, 'completed');
    console.log(`✅ Processing complete for recording ${recordingId}`);
  } catch (error) {
    console.error(`❌ Summary generation failed for ${recordingId}:`, error);
    await updateProcessingStatus(recordingId, 'failed_summary');
    throw error;
  }
}

/**
 * Transcribe all chunks for a recording, one at a time.
 */
async function transcribeAllChunks(
  recordingId: string,
  chunks: Array<{ id: string; sequenceNumber: number; filePath: string | null; status: string; transcription: string | null }>,
): Promise<void> {
  const totalChunks = chunks.length;

  for (const chunk of chunks) {
    // Skip already-transcribed chunks (retry support)
    if (chunk.transcription && chunk.status === 'transcribed') {
      console.log(`  ⏭️  Chunk ${chunk.sequenceNumber} already transcribed, skipping`);
      continue;
    }

    if (!chunk.filePath) {
      console.warn(`  ⚠️  Chunk ${chunk.sequenceNumber} has no file path, skipping`);
      await prisma.audioChunk.update({
        where: { id: chunk.id },
        data: { status: 'skipped' },
      });
      continue;
    }

    console.log(`  🎙️  Transcribing chunk ${chunk.sequenceNumber + 1}/${totalChunks}...`);

    // Update chunk status
    await prisma.audioChunk.update({
      where: { id: chunk.id },
      data: { status: 'transcribing' },
    });

    try {
      const transcript = await transcribeAudioChunk(
        chunk.filePath,
        chunk.sequenceNumber,
        totalChunks,
      );

      // Save transcription to chunk
      await prisma.audioChunk.update({
        where: { id: chunk.id },
        data: {
          transcription: transcript,
          status: 'transcribed',
        },
      });

      console.log(`  ✅ Chunk ${chunk.sequenceNumber + 1} transcribed (${transcript.length} chars)`);

      // Small delay between API calls to respect rate limits
      if (chunk.sequenceNumber < totalChunks - 1) {
        await delay(1000);
      }
    } catch (error) {
      console.error(`  ❌ Chunk ${chunk.sequenceNumber + 1} failed:`, error);

      await prisma.audioChunk.update({
        where: { id: chunk.id },
        data: { status: 'failed' },
      });

      throw error; // Propagate to halt pipeline
    }
  }
}

/**
 * Assemble all chunk transcriptions into a single transcript document.
 */
async function assembleTranscript(recordingId: string, title: string): Promise<void> {
  const chunks = await prisma.audioChunk.findMany({
    where: {
      recordingId,
      status: 'transcribed',
      transcription: { not: null },
    },
    orderBy: { sequenceNumber: 'asc' },
  });

  if (chunks.length === 0) {
    throw new Error('No transcribed chunks to assemble');
  }

  // Build the assembled markdown document
  const parts: string[] = [
    `# ${title}`,
    ``,
    `> Transcribed by Lecto AI | ${new Date().toLocaleDateString('en-US', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' })}`,
    `> ${chunks.length} chunk(s) processed`,
    ``,
    `---`,
    ``,
  ];

  for (const chunk of chunks) {
    if (chunks.length > 1) {
      // Only add chunk markers if there are multiple chunks
      const chunkMinutes = Math.floor((chunk.durationMs || 0) / 60000);
      parts.push(`<!-- Chunk ${chunk.sequenceNumber + 1} | ~${chunkMinutes} min -->`);
      parts.push(``);
    }
    parts.push(chunk.transcription!);
    parts.push(``);
  }

  const fullTranscript = parts.join('\n');
  const wordCount = fullTranscript.split(/\s+/).filter(w => w.length > 0).length;

  // Upsert transcript record
  await prisma.transcript.upsert({
    where: { recordingId },
    create: {
      recordingId,
      content: fullTranscript,
      format: 'markdown',
      wordCount,
    },
    update: {
      content: fullTranscript,
      wordCount,
      updatedAt: new Date(),
    },
  });

  console.log(`  📄 Transcript assembled: ${wordCount} words`);
}

/**
 * Generate structured study notes from the assembled transcript.
 */
async function generateNotesFromTranscript(recordingId: string, title: string): Promise<void> {
  const transcript = await prisma.transcript.findUnique({
    where: { recordingId },
  });

  if (!transcript) {
    throw new Error('Transcript not found for summary generation');
  }

  console.log(`  🧠 Generating summary from ${transcript.wordCount} words...`);

  const summaryContent = await generateSummary(
    transcript.content,
    title,
    [], // TODO: Add photo descriptions when photo analysis is implemented
  );

  // Upsert summary record
  await prisma.summary.upsert({
    where: { recordingId },
    create: {
      recordingId,
      transcriptId: transcript.id,
      content: summaryContent,
      status: 'completed',
    },
    update: {
      content: summaryContent,
      status: 'completed',
      updatedAt: new Date(),
    },
  });

  console.log(`  ✅ Summary generated (${summaryContent.length} chars)`);
}

/**
 * Get detailed processing status for a recording.
 */
export async function getProcessingStatus(recordingId: string, userId: string) {
  const recording = await prisma.recording.findFirst({
    where: { id: recordingId, userId },
    include: {
      chunks: {
        select: {
          id: true,
          sequenceNumber: true,
          status: true,
          durationMs: true,
        },
        orderBy: { sequenceNumber: 'asc' },
      },
      transcript: {
        select: { id: true, wordCount: true, createdAt: true },
      },
      summary: {
        select: { id: true, status: true, createdAt: true },
      },
    },
  });

  if (!recording) {
    return null;
  }

  const totalChunks = recording.chunks.length;
  const transcribedChunks = recording.chunks.filter(c => c.status === 'transcribed').length;
  const failedChunks = recording.chunks.filter(c => c.status === 'failed').length;

  return {
    recordingId: recording.id,
    processingStatus: recording.processingStatus,
    progress: {
      totalChunks,
      transcribedChunks,
      failedChunks,
      percentage: totalChunks > 0 ? Math.round((transcribedChunks / totalChunks) * 100) : 0,
    },
    transcript: recording.transcript ? {
      id: recording.transcript.id,
      wordCount: recording.transcript.wordCount,
      createdAt: recording.transcript.createdAt,
    } : null,
    summary: recording.summary ? {
      id: recording.summary.id,
      status: recording.summary.status,
      createdAt: recording.summary.createdAt,
    } : null,
    chunks: recording.chunks.map(c => ({
      sequenceNumber: c.sequenceNumber,
      status: c.status,
    })),
  };
}

/**
 * Get the assembled transcript content.
 */
export async function getTranscriptContent(recordingId: string, userId: string) {
  const recording = await prisma.recording.findFirst({
    where: { id: recordingId, userId },
    select: { id: true },
  });

  if (!recording) return null;

  return prisma.transcript.findUnique({
    where: { recordingId },
  });
}

/**
 * Get the generated summary content.
 */
export async function getSummaryContent(recordingId: string, userId: string) {
  const recording = await prisma.recording.findFirst({
    where: { id: recordingId, userId },
    select: { id: true },
  });

  if (!recording) return null;

  return prisma.summary.findUnique({
    where: { recordingId },
    include: {
      transcript: {
        select: { wordCount: true },
      },
    },
  });
}

// ─── Helpers ─────────────────────────────────────────────────────────

async function updateProcessingStatus(recordingId: string, status: ProcessingStage): Promise<void> {
  await prisma.recording.update({
    where: { id: recordingId },
    data: { processingStatus: status },
  });
  console.log(`  📊 Processing status: ${status}`);
}

function delay(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}
