import { z } from 'zod';

export const UNSORTED_SUBJECT_ID = 'unsorted';

export const createRecordingSchema = z.object({
  // Client-generated ID so offline recordings keep the same ID once synced
  id: z.string().uuid().optional(),
  // 'unsorted' resolves to the user's Unsorted subject (Quick Record)
  subjectId: z.union([z.string().uuid(), z.literal(UNSORTED_SUBJECT_ID)]),
  title: z.string().min(1).max(100).optional(),
  audioFormat: z.enum(['aac', 'm4a', 'wav']).default('aac'),
  chunkDurationMin: z.number().int().min(3).max(30).default(15),
});

export type CreateRecordingInput = z.infer<typeof createRecordingSchema>;

export const updateRecordingSchema = z.object({
  title: z.string().min(1).max(100).optional(),
  status: z.enum(['completed', 'processing', 'transcribed']).optional(),
});

export type UpdateRecordingInput = z.infer<typeof updateRecordingSchema>;

export const listRecordingsQuerySchema = z.object({
  subjectId: z.string().uuid().optional(),
  status: z.string().optional(),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(50).default(20),
});

export type ListRecordingsQuery = z.infer<typeof listRecordingsQuerySchema>;
