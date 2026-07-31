import type { FastifyError, FastifyReply, FastifyRequest } from 'fastify';
import { AppError } from '../utils/errors.js';
import { errorResponse } from '../utils/response.js';
import { ZodError } from 'zod';

export function errorHandler(
  error: FastifyError | Error,
  request: FastifyRequest,
  reply: FastifyReply,
): void {
  request.log.error(error);

  // Handle our custom AppError
  if (error instanceof AppError) {
    reply.status(error.statusCode).send(
      errorResponse(error.code, error.message, error.details),
    );
    return;
  }

  // Handle Zod validation errors
  if (error instanceof ZodError) {
    reply.status(400).send(
      errorResponse('VALIDATION_ERROR', 'Invalid request data', error.flatten()),
    );
    return;
  }

  // Handle Fastify validation errors
  if ('validation' in error && error.validation) {
    reply.status(400).send(
      errorResponse('VALIDATION_ERROR', error.message),
    );
    return;
  }

  // Handle rate limit errors
  if ('statusCode' in error && error.statusCode === 429) {
    reply.status(429).send(
      errorResponse('RATE_LIMITED', 'Too many requests'),
    );
    return;
  }

  // Default 500 error
  reply.status(500).send(
    errorResponse('INTERNAL_ERROR', 'An unexpected error occurred'),
  );
}
