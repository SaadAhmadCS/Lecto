/// Standardized API response helpers

export interface ApiResponse<T> {
  success: boolean;
  data?: T;
  error?: {
    code: string;
    message: string;
    details?: unknown;
  };
  meta?: {
    page?: number;
    limit?: number;
    total?: number;
  };
}

export function successResponse<T>(data: T, meta?: ApiResponse<T>['meta']): ApiResponse<T> {
  const response: ApiResponse<T> = { success: true, data };
  if (meta) response.meta = meta;
  return response;
}

export function errorResponse(code: string, message: string, details?: unknown): ApiResponse<never> {
  const error: ApiResponse<never>['error'] = { code, message };
  if (details) error!.details = details;
  return { success: false, error };
}

export function paginatedResponse<T>(
  data: T[],
  total: number,
  page: number,
  limit: number,
): ApiResponse<T[]> {
  return {
    success: true,
    data,
    meta: {
      page,
      limit,
      total,
    },
  };
}
