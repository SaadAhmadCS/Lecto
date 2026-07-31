import { prisma } from '../config/database.js';
import { NotFoundError } from '../utils/errors.js';
import { processingQueue } from './processing-queue.js';
import type {
  CreateRecordingInput,
  UpdateRecordingInput,
  ListRecordingsQuery,
} from '../validators/recording.js';

export class RecordingService {
  async list(userId: string, query: ListRecordingsQuery) {
    const where: Record<string, unknown> = { userId };
    if (query.subjectId) where.subjectId = query.subjectId;
    if (query.status) where.status = query.status;

    const skip = (query.page - 1) * query.limit;

    const [recordings, total] = await Promise.all([
      prisma.recording.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip,
        take: query.limit,
        include: {
          subject: { select: { id: true, name: true, color: true } },
          _count: {
            select: { chunks: true },
          },
        },
      }),
      prisma.recording.count({ where }),
    ]);

    return { recordings, total, page: query.page, limit: query.limit };
  }

  async getById(id: string, userId: string) {
    const recording = await prisma.recording.findFirst({
      where: { id, userId },
      include: {
        subject: { select: { id: true, name: true, color: true } },
        chunks: {
          orderBy: { sequenceNumber: 'asc' },
          select: {
            id: true,
            sequenceNumber: true,
            status: true,
            durationMs: true,
            sizeBytes: true,
            createdAt: true,
          },
        },
        _count: { select: { chunks: true } },
      },
    });

    if (!recording) {
      throw new NotFoundError('Recording', id);
    }

    return recording;
  }

  async create(userId: string, data: CreateRecordingInput) {
    // Auto-generate title if not provided
    const now = new Date();
    const title =
      data.title ??
      `Recording ${now.toLocaleDateString()} ${now.toLocaleTimeString([], {
        hour: '2-digit',
        minute: '2-digit',
      })}`;

    // Verify subject exists and belongs to user
    const subject = await prisma.subject.findFirst({
      where: { id: data.subjectId, userId },
    });

    if (!subject) {
      throw new NotFoundError('Subject', data.subjectId);
    }

    return prisma.recording.create({
      data: {
        userId,
        subjectId: data.subjectId,
        title,
        audioFormat: data.audioFormat,
        chunkDurationMin: data.chunkDurationMin,
        status: 'recording',
      },
      include: {
        subject: { select: { id: true, name: true, color: true } },
      },
    });
  }

  async update(id: string, userId: string, data: UpdateRecordingInput) {
    // Verify ownership
    await this.getById(id, userId);

    const updated = await prisma.recording.update({
      where: { id },
      data,
    });

    // Auto-trigger processing when recording is completed
    if (data.status === 'completed') {
      console.log(`🤖 Auto-processing triggered for recording ${id}`);
      processingQueue.enqueue(id, userId);
    }

    return updated;
  }

  async delete(id: string, userId: string) {
    // Verify ownership
    await this.getById(id, userId);

    // Cascade delete: chunks first, then recording
    await prisma.audioChunk.deleteMany({ where: { recordingId: id } });
    return prisma.recording.delete({ where: { id } });
  }

  async addChunk(
    recordingId: string,
    userId: string,
    chunkData: {
      sequenceNumber: number;
      filePath: string;
      durationMs: number;
      sizeBytes: number;
    },
  ) {
    // Verify recording ownership
    const recording = await this.getById(recordingId, userId);

    const chunk = await prisma.audioChunk.create({
      data: {
        recordingId,
        sequenceNumber: chunkData.sequenceNumber,
        filePath: chunkData.filePath,
        durationMs: chunkData.durationMs,
        sizeBytes: chunkData.sizeBytes,
        status: 'uploaded',
      },
    });

    // Update recording's total duration
    await prisma.recording.update({
      where: { id: recordingId },
      data: {
        totalDurationMs: { increment: chunkData.durationMs },
      },
    });

    return chunk;
  }

  async getChunks(recordingId: string, userId: string) {
    // Verify ownership
    await this.getById(recordingId, userId);

    return prisma.audioChunk.findMany({
      where: { recordingId },
      orderBy: { sequenceNumber: 'asc' },
    });
  }
}

export const recordingService = new RecordingService();
