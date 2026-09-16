import { prisma } from '../config/database.js';
import { ConflictError, NotFoundError } from '../utils/errors.js';
import type { CreateSubjectInput, UpdateSubjectInput } from '../validators/subject.js';

export const UNSORTED_SUBJECT_NAME = 'Unsorted';

export class SubjectService {
  async list(userId: string) {
    return prisma.subject.findMany({
      where: { userId },
      orderBy: [{ sortOrder: 'asc' }, { createdAt: 'desc' }],
      include: {
        _count: {
          select: { recordings: true },
        },
      },
    });
  }

  async getById(id: string, userId: string) {
    const subject = await prisma.subject.findFirst({
      where: { id, userId },
      include: {
        _count: {
          select: { recordings: true },
        },
      },
    });

    if (!subject) {
      throw new NotFoundError('Subject', id);
    }

    return subject;
  }

  async create(userId: string, data: CreateSubjectInput) {
    const maxOrder = await prisma.subject.aggregate({
      where: { userId },
      _max: { sortOrder: true },
    });

    return prisma.subject.create({
      data: {
        ...data,
        userId,
        sortOrder: (maxOrder._max.sortOrder ?? -1) + 1,
      },
    });
  }

  async update(id: string, userId: string, data: UpdateSubjectInput) {
    // Verify ownership
    await this.getById(id, userId);

    return prisma.subject.update({
      where: { id },
      data,
    });
  }

  /**
   * Find the user's "Unsorted" subject, creating it if needed.
   * Used for Quick Record and for recordings orphaned by subject deletion.
   */
  async getOrCreateUnsorted(userId: string) {
    const existing = await prisma.subject.findFirst({
      where: { userId, name: UNSORTED_SUBJECT_NAME },
      orderBy: { createdAt: 'asc' },
    });
    if (existing) return existing;

    return this.create(userId, {
      name: UNSORTED_SUBJECT_NAME,
      color: '#6B7280',
      icon: 'inbox',
    });
  }

  async delete(id: string, userId: string) {
    // Verify ownership
    const subject = await this.getById(id, userId);

    // Recordings cascade-delete with their subject, so move them to
    // Unsorted first. Deleting Unsorted itself while it has recordings
    // would destroy them, so refuse.
    if (subject._count.recordings > 0) {
      if (subject.name === UNSORTED_SUBJECT_NAME) {
        throw new ConflictError(
          'Move or delete the recordings in Unsorted before deleting it',
        );
      }
      const unsorted = await this.getOrCreateUnsorted(userId);
      return prisma.$transaction([
        prisma.recording.updateMany({
          where: { subjectId: id, userId },
          data: { subjectId: unsorted.id },
        }),
        prisma.subject.delete({ where: { id } }),
      ]);
    }

    return prisma.subject.delete({
      where: { id },
    });
  }
}

export const subjectService = new SubjectService();
