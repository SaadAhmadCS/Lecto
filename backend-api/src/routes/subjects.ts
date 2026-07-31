import type { FastifyInstance } from 'fastify';
import { subjectController } from '../controllers/subject-controller.js';

export async function subjectRoutes(app: FastifyInstance): Promise<void> {
  app.get('/subjects', subjectController.list.bind(subjectController));
  app.get('/subjects/:id', subjectController.getById.bind(subjectController));
  app.post('/subjects', subjectController.create.bind(subjectController));
  app.put('/subjects/:id', subjectController.update.bind(subjectController));
  app.delete('/subjects/:id', subjectController.delete.bind(subjectController));
}
