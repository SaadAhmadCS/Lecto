import { FastifyRequest, FastifyReply } from 'fastify';
import { initializeApp, getApps, cert } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';

// Initialize Firebase Admin SDK
// Uses Application Default Credentials or service account
if (!getApps().length) {
  initializeApp();
}

declare module 'fastify' {
  interface FastifyRequest {
    userId: string;
  }
}

export async function authMiddleware(
  request: FastifyRequest,
  reply: FastifyReply
) {
  // Skip auth for health check
  if (request.url === '/health' || request.url === '/api/health') {
    return;
  }

  const authHeader = request.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) {
    // For now, fall back to dev user if no auth header
    // This allows gradual migration
    request.userId = 'dev-user-001';
    return;
  }

  const token = authHeader.substring(7);
  try {
    const decodedToken = await getAuth().verifyIdToken(token);
    request.userId = decodedToken.uid;
  } catch (error) {
    // If token is invalid, fall back to dev user for now
    // In production, this should return 401
    request.userId = 'dev-user-001';
  }
}
