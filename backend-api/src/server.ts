import Fastify from 'fastify';
import cors from '@fastify/cors';
import rateLimit from '@fastify/rate-limit';
import { env } from './config/env.js';
import { connectDatabase, disconnectDatabase } from './config/database.js';
import { errorHandler } from './middleware/error-handler.js';
import { healthRoutes } from './routes/health.js';
import { subjectRoutes } from './routes/subjects.js';
import { recordingRoutes } from './routes/recordings.js';
import { processingRoutes } from './routes/processing.js';

async function buildApp() {
  const app = Fastify({
    logger: {
      level: env.LOG_LEVEL,
      transport: env.NODE_ENV === 'development'
        ? { target: 'pino-pretty', options: { colorize: true } }
        : undefined,
    },
  });

  // === Plugins ===
  await app.register(cors, {
    origin: env.CORS_ORIGIN === '*' ? true : env.CORS_ORIGIN.split(','),
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization'],
    credentials: true,
  });

  await app.register(rateLimit, {
    max: env.RATE_LIMIT_MAX,
    timeWindow: '1 minute',
  });

  // === Error Handler ===
  app.setErrorHandler(errorHandler);

  // === Routes ===
  await app.register(healthRoutes);
  await app.register(subjectRoutes, { prefix: '/api/v1' });
  await app.register(recordingRoutes, { prefix: '/api/v1/recordings' });
  await app.register(processingRoutes, { prefix: '/api/v1' });

  return app;
}

async function start() {
  try {
    // Connect to database
    await connectDatabase();

    // Build and start server
    const app = await buildApp();
    
    await app.listen({ port: env.PORT, host: env.HOST });
    
    console.log(`\n🚀 Lecto API running at http://${env.HOST}:${env.PORT}`);
    console.log(`📋 Health check: http://localhost:${env.PORT}/health`);
    console.log(`📚 Subjects API: http://localhost:${env.PORT}/api/v1/subjects`);
    console.log(`🎙️  Recordings API: http://localhost:${env.PORT}/api/v1/recordings`);
    console.log(`🧠 Processing API: http://localhost:${env.PORT}/api/v1/recordings/:id/process\n`);

    // Graceful shutdown
    const signals: NodeJS.Signals[] = ['SIGINT', 'SIGTERM'];
    for (const signal of signals) {
      process.on(signal, async () => {
        console.log(`\n${signal} received. Shutting down gracefully...`);
        await app.close();
        await disconnectDatabase();
        process.exit(0);
      });
    }
  } catch (error) {
    console.error('❌ Failed to start server:', error);
    process.exit(1);
  }
}

start();
