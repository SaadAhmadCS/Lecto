import type { FastifyReply, FastifyRequest } from 'fastify';
import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { recordingService } from '../services/recording-service.js';
import {
  createRecordingSchema,
  updateRecordingSchema,
  listRecordingsQuerySchema,
} from '../validators/recording.js';
import { successResponse, paginatedResponse } from '../utils/response.js';


// Directory for uploaded audio files (relative to project root)
const UPLOADS_DIR = join(process.cwd(), 'uploads');

export class RecordingController {
  async list(request: FastifyRequest, reply: FastifyReply) {
    const query = listRecordingsQuerySchema.parse(request.query);
    const result = await recordingService.list(request.userId, query);
    return reply.send(
      paginatedResponse(
        result.recordings,
        result.total,
        result.page,
        result.limit,
      ),
    );
  }

  async getById(
    request: FastifyRequest<{ Params: { id: string } }>,
    reply: FastifyReply,
  ) {
    const recording = await recordingService.getById(
      request.params.id,
      request.userId,
    );
    return reply.send(successResponse(recording));
  }

  async create(request: FastifyRequest, reply: FastifyReply) {
    const data = createRecordingSchema.parse(request.body);
    const recording = await recordingService.create(request.userId, data);
    return reply.status(201).send(successResponse(recording));
  }

  async update(
    request: FastifyRequest<{ Params: { id: string } }>,
    reply: FastifyReply,
  ) {
    const data = updateRecordingSchema.parse(request.body);
    const recording = await recordingService.update(
      request.params.id,
      request.userId,
      data,
    );
    return reply.send(successResponse(recording));
  }

  async delete(
    request: FastifyRequest<{ Params: { id: string } }>,
    reply: FastifyReply,
  ) {
    await recordingService.delete(request.params.id, request.userId);
    return reply.status(204).send();
  }

  async uploadChunk(
    request: FastifyRequest<{ Params: { id: string } }>,
    reply: FastifyReply,
  ) {
    const recordingId = request.params.id;

    // Verify ownership before writing anything to disk
    await recordingService.getById(recordingId, request.userId);

    // Parse multipart form data (audio file + metadata fields)
    const data = await request.file();
    if (!data) {
      return reply.status(400).send({
        error: { code: 'MISSING_FILE', message: 'Audio file is required (multipart field "file")' },
      });
    }

    // Read metadata from form fields
    const fields = data.fields as Record<string, { value?: string }>;
    const sequenceNumber = parseInt(fields['sequenceNumber']?.value ?? '0', 10);
    const durationMs = parseInt(fields['durationMs']?.value ?? '0', 10);

    // Consume file buffer
    const fileBuffer = await data.toBuffer();
    const sizeBytes = fileBuffer.length;

    // Determine file extension from mimetype
    const ext = data.mimetype === 'audio/wav' ? 'wav'
      : data.mimetype === 'audio/mp3' || data.mimetype === 'audio/mpeg' ? 'mp3'
      : data.mimetype === 'audio/ogg' ? 'ogg'
      : data.mimetype === 'audio/aac' ? 'aac'
      : 'm4a'; // Default for audio/mp4, audio/x-m4a

    // Save to uploads/{recordingId}/chunk_{seq}.{ext}
    const recordingDir = join(UPLOADS_DIR, recordingId);
    await mkdir(recordingDir, { recursive: true });
    const fileName = `chunk_${String(sequenceNumber).padStart(3, '0')}.${ext}`;
    const filePath = join(recordingDir, fileName);
    await writeFile(filePath, fileBuffer);

    console.log(`  📁 Saved chunk ${sequenceNumber} → ${filePath} (${(sizeBytes / 1024).toFixed(0)} KB)`);

    // Store in DB with server-side file path
    const chunk = await recordingService.addChunk(
      recordingId,
      request.userId,
      {
        sequenceNumber,
        filePath,
        durationMs,
        sizeBytes,
      },
    );

    return reply.status(201).send(successResponse(chunk));
  }

  async getChunks(
    request: FastifyRequest<{ Params: { id: string } }>,
    reply: FastifyReply,
  ) {
    const chunks = await recordingService.getChunks(
      request.params.id,
      request.userId,
    );
    return reply.send(successResponse(chunks));
  }
}

export const recordingController = new RecordingController();
