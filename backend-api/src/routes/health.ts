import type { FastifyInstance } from 'fastify';
import { prisma } from '../config/database.js';

export async function healthRoutes(app: FastifyInstance): Promise<void> {
  app.get('/health', async (request, reply) => {
    try {
      // Check database connectivity
      await prisma.$queryRaw`SELECT 1`;

      return reply.send({
        success: true,
        data: {
          status: 'healthy',
          version: '1.0.0',
          timestamp: new Date().toISOString(),
          uptime: process.uptime(),
          services: {
            database: 'connected',
          },
        },
      });
    } catch (error) {
      return reply.status(503).send({
        success: false,
        data: {
          status: 'unhealthy',
          timestamp: new Date().toISOString(),
          services: {
            database: 'disconnected',
          },
        },
      });
    }
  });
}
