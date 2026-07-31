import type { FastifyInstance } from 'fastify';
import { recordingController } from '../controllers/recording-controller.js';

export async function recordingRoutes(fastify: FastifyInstance) {
  // List recordings (with optional subject filter)
  fastify.get('/', recordingController.list.bind(recordingController));

  // Get recording by ID (with chunks)
  fastify.get('/:id', recordingController.getById.bind(recordingController));

  // Create a new recording session
  fastify.post('/', recordingController.create.bind(recordingController));

  // Update recording metadata
  fastify.patch('/:id', recordingController.update.bind(recordingController));

  // Delete recording and all chunks
  fastify.delete('/:id', recordingController.delete.bind(recordingController));

  // Upload a chunk for a recording
  fastify.post(
    '/:id/chunks',
    recordingController.uploadChunk.bind(recordingController),
  );

  // List chunks for a recording
  fastify.get(
    '/:id/chunks',
    recordingController.getChunks.bind(recordingController),
  );
}
