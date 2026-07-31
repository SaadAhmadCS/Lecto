import type { FastifyInstance } from 'fastify';
import { processingController } from '../controllers/processing-controller.js';

export async function processingRoutes(app: FastifyInstance): Promise<void> {
  // Allow empty POST body for the process trigger
  app.addContentTypeParser('application/json', { parseAs: 'string' }, (req, body, done) => {
    try {
      const json = (body as string).length > 0 ? JSON.parse(body as string) : {};
      done(null, json);
    } catch (err) {
      done(err as Error, undefined);
    }
  });

  // Processing actions on a recording
  app.post('/recordings/:id/process', processingController.startProcessing.bind(processingController));
  app.get('/recordings/:id/status', processingController.getStatus.bind(processingController));
  app.get('/recordings/:id/transcript', processingController.getTranscript.bind(processingController));
  app.get('/recordings/:id/summary', processingController.getSummary.bind(processingController));

  // Debug endpoint for queue status
  app.get('/processing/queue', processingController.getQueueStatus.bind(processingController));
}
