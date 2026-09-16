import type { FastifyReply, FastifyRequest } from 'fastify';
import { subjectService } from '../services/subject-service.js';
import { createSubjectSchema, updateSubjectSchema } from '../validators/subject.js';
import { successResponse } from '../utils/response.js';


export class SubjectController {
  async list(request: FastifyRequest, reply: FastifyReply) {
    const subjects = await subjectService.list(request.userId);
    return reply.send(successResponse(subjects));
  }

  async getById(
    request: FastifyRequest<{ Params: { id: string } }>,
    reply: FastifyReply,
  ) {
    const subject = await subjectService.getById(request.params.id, request.userId);
    return reply.send(successResponse(subject));
  }

  async create(request: FastifyRequest, reply: FastifyReply) {
    const data = createSubjectSchema.parse(request.body);
    const subject = await subjectService.create(request.userId, data);
    return reply.status(201).send(successResponse(subject));
  }

  async update(
    request: FastifyRequest<{ Params: { id: string } }>,
    reply: FastifyReply,
  ) {
    const data = updateSubjectSchema.parse(request.body);
    const subject = await subjectService.update(request.params.id, request.userId, data);
    return reply.send(successResponse(subject));
  }

  async delete(
    request: FastifyRequest<{ Params: { id: string } }>,
    reply: FastifyReply,
  ) {
    await subjectService.delete(request.params.id, request.userId);
    return reply.status(204).send();
  }
}

export const subjectController = new SubjectController();
