import { PrismaClient } from '@prisma/client';
import { PrismaLibSql } from '@prisma/adapter-libsql';
import { env } from './env.js';

const adapter = new PrismaLibSql({
  url: env.DATABASE_URL,
});

export const prisma = new PrismaClient({
  adapter,
  log: env.NODE_ENV === 'development' ? ['query', 'error', 'warn'] : ['error'],
});

export async function connectDatabase(): Promise<void> {
  try {
    await prisma.$connect();
    console.log('✅ Database connected successfully');

    // Seed dev user for development
    if (env.NODE_ENV === 'development') {
      await seedDevUser();
    }
  } catch (error) {
    console.error('❌ Database connection failed:', error);
    process.exit(1);
  }
}

async function seedDevUser(): Promise<void> {
  const DEV_USER_ID = 'dev-user-001';
  const existing = await prisma.user.findUnique({ where: { id: DEV_USER_ID } });
  if (!existing) {
    await prisma.user.create({
      data: {
        id: DEV_USER_ID,
        firebaseUid: 'dev-firebase-uid',
        email: 'dev@lecto.app',
        displayName: 'Dev User',
      },
    });
    console.log('🌱 Dev user seeded');
  }
}

export async function disconnectDatabase(): Promise<void> {
  await prisma.$disconnect();
  console.log('📴 Database disconnected');
}
