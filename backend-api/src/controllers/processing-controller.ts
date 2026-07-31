import type { FastifyReply, FastifyRequest } from 'fastify';
import { getProcessingStatus, getTranscriptContent, getSummaryContent } from '../services/processing-service.js';
import { processingQueue } from '../services/processing-queue.js';
import { successResponse, errorResponse } from '../utils/response.js';

const DEV_USER_ID = 'dev-user-001';

class ProcessingController {
  /**
   * POST /recordings/:id/process — Start processing a completed recording.
   */
  async startProcessing(
    request: FastifyRequest<{ Params: { id: string } }>,
    reply: FastifyReply,
  ) {
    const { id } = request.params;
    const userId = DEV_USER_ID;

    // Check if already in queue
    if (processingQueue.isRecordingQueued(id)) {
      return reply.status(409).send(
        errorResponse('ALREADY_PROCESSING', 'Recording is already being processed'),
      );
    }

    // Enqueue for processing (auto-starts)
    processingQueue.enqueue(id, userId);

    // Return immediately — processing happens in background
    return reply.status(202).send(
      successResponse({
        message: 'Processing started',
        recordingId: id,
        queuePosition: processingQueue.queueLength,
      }),
    );
  }

  /**
   * GET /recordings/:id/status — Get processing status.
   */
  async getStatus(
    request: FastifyRequest<{ Params: { id: string } }>,
    reply: FastifyReply,
  ) {
    const { id } = request.params;
    const userId = DEV_USER_ID;

    const status = await getProcessingStatus(id, userId);
    if (!status) {
      return reply.status(404).send(errorResponse('NOT_FOUND', 'Recording not found'));
    }

    return reply.send(successResponse(status));
  }

  /**
   * GET /recordings/:id/transcript — Get the assembled transcript.
   */
  async getTranscript(
    request: FastifyRequest<{ Params: { id: string } }>,
    reply: FastifyReply,
  ) {
    const { id } = request.params;
    const userId = DEV_USER_ID;

    const transcript = await getTranscriptContent(id, userId);
    if (!transcript) {
      return reply.status(404).send(errorResponse('NOT_FOUND', 'Transcript not found'));
    }

    return reply.send(successResponse(transcript));
  }

  /**
   * GET /recordings/:id/summary — Get the AI-generated summary.
   */
  async getSummary(
    request: FastifyRequest<{ Params: { id: string } }>,
    reply: FastifyReply,
  ) {
    const { id } = request.params;
    const userId = DEV_USER_ID;

    const summary = await getSummaryContent(id, userId);
    if (!summary) {
      return reply.status(404).send(errorResponse('NOT_FOUND', 'Summary not found'));
    }

    return reply.send(successResponse(summary));
  }

  /**
   * GET /processing/queue — Get the processing queue status (debug).
   */
  async getQueueStatus(
    _request: FastifyRequest,
    reply: FastifyReply,
  ) {
    return reply.send(successResponse(processingQueue.getStatus()));
  }
}

export const processingController = new ProcessingController();
