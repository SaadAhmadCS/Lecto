import type { FastifyReply, FastifyRequest } from 'fastify';
import { recordingService } from '../services/recording-service.js';
import {
  createRecordingSchema,
  updateRecordingSchema,
  listRecordingsQuerySchema,
} from '../validators/recording.js';
import { successResponse, paginatedResponse } from '../utils/response.js';

// Placeholder until auth is implemented
const TEMP_USER_ID = 'dev-user-001';

export class RecordingController {
  async list(request: FastifyRequest, reply: FastifyReply) {
    const query = listRecordingsQuerySchema.parse(request.query);
    const result = await recordingService.list(TEMP_USER_ID, query);
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
      TEMP_USER_ID,
    );
    return reply.send(successResponse(recording));
  }

  async create(request: FastifyRequest, reply: FastifyReply) {
    const data = createRecordingSchema.parse(request.body);
    const recording = await recordingService.create(TEMP_USER_ID, data);
    return reply.status(201).send(successResponse(recording));
  }

  async update(
    request: FastifyRequest<{ Params: { id: string } }>,
    reply: FastifyReply,
  ) {
    const data = updateRecordingSchema.parse(request.body);
    const recording = await recordingService.update(
      request.params.id,
      TEMP_USER_ID,
      data,
    );
    return reply.send(successResponse(recording));
  }

  async delete(
    request: FastifyRequest<{ Params: { id: string } }>,
    reply: FastifyReply,
  ) {
    await recordingService.delete(request.params.id, TEMP_USER_ID);
    return reply.status(204).send();
  }

  async uploadChunk(
    request: FastifyRequest<{ Params: { id: string } }>,
    reply: FastifyReply,
  ) {
    // For now, accept JSON metadata (file upload will come with multipart support)
    const body = request.body as {
      sequenceNumber: number;
      filePath: string;
      durationMs: number;
      sizeBytes: number;
    };

    const chunk = await recordingService.addChunk(
      request.params.id,
      TEMP_USER_ID,
      body,
    );
    return reply.status(201).send(successResponse(chunk));
  }

  async getChunks(
    request: FastifyRequest<{ Params: { id: string } }>,
    reply: FastifyReply,
  ) {
    const chunks = await recordingService.getChunks(
      request.params.id,
      TEMP_USER_ID,
    );
    return reply.send(successResponse(chunks));
  }
}

export const recordingController = new RecordingController();
