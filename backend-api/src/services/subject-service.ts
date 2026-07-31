import { prisma } from '../config/database.js';
import { NotFoundError } from '../utils/errors.js';
import type { CreateSubjectInput, UpdateSubjectInput } from '../validators/subject.js';

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

  async delete(id: string, userId: string) {
    // Verify ownership
    await this.getById(id, userId);

    return prisma.subject.delete({
      where: { id },
    });
  }
}

export const subjectService = new SubjectService();
