import type { FastifyReply, FastifyRequest } from 'fastify';
import { initializeApp, getApps } from 'firebase-admin/app';
import { getAuth, type DecodedIdToken } from 'firebase-admin/auth';
import { prisma } from '../config/database.js';
import { env } from '../config/env.js';
import { errorResponse } from '../utils/response.js';

// Verifying ID tokens only needs the project ID — Firebase's public signing
// keys are fetched automatically, so no service account is required.
if (!getApps().length) {
  initializeApp(env.FIREBASE_PROJECT_ID ? { projectId: env.FIREBASE_PROJECT_ID } : undefined);
}

declare module 'fastify' {
  interface FastifyRequest {
    userId: string;
  }
}

const DEV_USER_ID = 'dev-user-001';
const PUBLIC_ROUTES = new Set(['/health']);

// Firebase UID → internal user ID. Users are never deleted while the
// server runs, so the mapping can't go stale.
const userIdCache = new Map<string, string>();

export async function authMiddleware(request: FastifyRequest, reply: FastifyReply) {
  if (PUBLIC_ROUTES.has(request.routeOptions.url ?? '')) {
    return;
  }

  const authHeader = request.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) {
    // Local scripts (e.g. test-ai.ps1) can opt in to acting as the seeded dev user
    if (env.AUTH_DEV_BYPASS) {
      request.userId = DEV_USER_ID;
      return;
    }
    return reply.status(401).send(errorResponse('UNAUTHORIZED', 'Missing bearer token'));
  }

  let decodedToken: DecodedIdToken;
  try {
    decodedToken = await getAuth().verifyIdToken(authHeader.substring(7));
  } catch (error) {
    request.log.warn({ err: error }, 'Rejected Firebase ID token');
    return reply.status(401).send(errorResponse('UNAUTHORIZED', 'Invalid or expired token'));
  }

  request.userId = await resolveUserId(decodedToken);
}

/** Map a Firebase user to our users table, creating the row on first request. */
async function resolveUserId(token: DecodedIdToken): Promise<string> {
  const cached = userIdCache.get(token.uid);
  if (cached) return cached;

  const user = await prisma.user.upsert({
    where: { firebaseUid: token.uid },
    update: {},
    create: {
      firebaseUid: token.uid,
      // email is required and unique; phone/anonymous accounts have none
      email: token.email ?? `${token.uid}@users.lecto.invalid`,
      displayName: token.name ?? null,
      avatarUrl: token.picture ?? null,
    },
  });

  userIdCache.set(token.uid, user.id);
  return user.id;
}
