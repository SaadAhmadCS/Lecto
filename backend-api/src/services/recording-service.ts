import { prisma } from '../config/database.js';
import { ConflictError, NotFoundError } from '../utils/errors.js';
import { processingQueue } from './processing-queue.js';
import { subjectService } from './subject-service.js';
import {
  UNSORTED_SUBJECT_ID,
  type CreateRecordingInput,
  type UpdateRecordingInput,
  type ListRecordingsQuery,
} from '../validators/recording.js';

export class RecordingService {
  async list(userId: string, query: ListRecordingsQuery) {
    const where: Record<string, unknown> = { userId };
    if (query.subjectId) where.subjectId = query.subjectId;
    if (query.status) where.status = query.status;

    const skip = (query.page - 1) * query.limit;

    const [recordings, total] = await Promise.all([
      prisma.recording.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip,
        take: query.limit,
        include: {
          subject: { select: { id: true, name: true, color: true } },
          _count: {
            select: { chunks: true },
          },
        },
      }),
      prisma.recording.count({ where }),
    ]);

    return { recordings, total, page: query.page, limit: query.limit };
  }

  async getById(id: string, userId: string) {
    const recording = await prisma.recording.findFirst({
      where: { id, userId },
      include: {
        subject: { select: { id: true, name: true, color: true } },
        chunks: {
          orderBy: { sequenceNumber: 'asc' },
          select: {
            id: true,
            sequenceNumber: true,
            status: true,
            durationMs: true,
            sizeBytes: true,
            createdAt: true,
          },
        },
        _count: { select: { chunks: true } },
      },
    });

    if (!recording) {
      throw new NotFoundError('Recording', id);
    }

    return recording;
  }

  async create(userId: string, data: CreateRecordingInput) {
    const include = {
      subject: { select: { id: true, name: true, color: true } },
    } as const;

    // Idempotent for client-generated IDs: an offline recording is retried
    // until it syncs, so a repeat create must return the existing row.
    if (data.id) {
      const existing = await prisma.recording.findUnique({
        where: { id: data.id },
        include,
      });
      if (existing) {
        if (existing.userId !== userId) {
          throw new ConflictError('Recording ID already in use');
        }
        return existing;
      }
    }

    // Auto-generate title if not provided
    const now = new Date();
    const title =
      data.title ??
      `Recording ${now.toLocaleDateString()} ${now.toLocaleTimeString([], {
        hour: '2-digit',
        minute: '2-digit',
      })}`;

    const subjectId = await this.resolveSubjectId(userId, data.subjectId);

    return prisma.recording.create({
      data: {
        id: data.id,
        userId,
        subjectId,
        title,
        // null = auto-detect
        language: data.language && data.language !== 'auto' ? data.language : null,
        audioFormat: data.audioFormat,
        chunkDurationMin: data.chunkDurationMin,
        status: 'recording',
      },
      include,
    });
  }

  async update(id: string, userId: string, data: UpdateRecordingInput) {
    // Verify ownership
    const existing = await this.getById(id, userId);

    const updated = await prisma.recording.update({
      where: { id },
      data: {
        ...data,
        subjectId: data.subjectId
          ? await this.resolveSubjectId(userId, data.subjectId)
          : undefined,
      },
      include: {
        subject: { select: { id: true, name: true, color: true } },
      },
    });

    // Auto-trigger processing when recording is completed. Only on the
    // transition, so a retried completion request doesn't reprocess.
    if (data.status === 'completed' && existing.status !== 'completed') {
      console.log(`🤖 Auto-processing triggered for recording ${id}`);
      processingQueue.enqueue(id, userId);
    }

    return updated;
  }

  /** Resolve 'unsorted' and verify the subject belongs to the user. */
  private async resolveSubjectId(userId: string, subjectId: string): Promise<string> {
    if (subjectId === UNSORTED_SUBJECT_ID) {
      return (await subjectService.getOrCreateUnsorted(userId)).id;
    }

    const subject = await prisma.subject.findFirst({
      where: { id: subjectId, userId },
    });
    if (!subject) {
      throw new NotFoundError('Subject', subjectId);
    }
    return subject.id;
  }

  async delete(id: string, userId: string) {
    // Verify ownership
    await this.getById(id, userId);

    // Cascade delete: chunks first, then recording
    await prisma.audioChunk.deleteMany({ where: { recordingId: id } });
    return prisma.recording.delete({ where: { id } });
  }

  async addChunk(
    recordingId: string,
    userId: string,
    chunkData: {
      sequenceNumber: number;
      filePath: string;
      durationMs: number;
      sizeBytes: number;
    },
  ) {
    // Verify recording ownership
    await this.getById(recordingId, userId);

    // A retried upload (e.g. response lost on a flaky network) re-sends the
    // same sequence number; update it instead of failing the unique index.
    const existing = await prisma.audioChunk.findUnique({
      where: {
        recordingId_sequenceNumber: {
          recordingId,
          sequenceNumber: chunkData.sequenceNumber,
        },
      },
    });
    if (existing) {
      const [chunk] = await prisma.$transaction([
        prisma.audioChunk.update({
          where: { id: existing.id },
          data: {
            filePath: chunkData.filePath,
            durationMs: chunkData.durationMs,
            sizeBytes: chunkData.sizeBytes,
          },
        }),
        prisma.recording.update({
          where: { id: recordingId },
          data: {
            totalDurationMs: {
              increment: chunkData.durationMs - existing.durationMs,
            },
          },
        }),
      ]);
      return chunk;
    }

    const chunk = await prisma.audioChunk.create({
      data: {
        recordingId,
        sequenceNumber: chunkData.sequenceNumber,
        filePath: chunkData.filePath,
        durationMs: chunkData.durationMs,
        sizeBytes: chunkData.sizeBytes,
        status: 'uploaded',
      },
    });

    // Update recording's total duration
    await prisma.recording.update({
      where: { id: recordingId },
      data: {
        totalDurationMs: { increment: chunkData.durationMs },
      },
    });

    return chunk;
  }

  async getChunks(recordingId: string, userId: string) {
    // Verify ownership
    await this.getById(recordingId, userId);

    return prisma.audioChunk.findMany({
      where: { recordingId },
      orderBy: { sequenceNumber: 'asc' },
    });
  }
}

export const recordingService = new RecordingService();
