import 'upload_queue_service.dart';

/// Persistence for [UploadQueueService] so queued work survives app kills.
abstract class UploadTaskStore {
  /// All stored tasks in the order they were first saved.
  Future<List<UploadTask>> loadAll();

  /// Insert a task. Saving an ID that already exists is a no-op.
  Future<void> save(UploadTask task);

  /// Persist a task's attempts and status.
  Future<void> update(UploadTask task);

  Future<void> delete(String id);

  Future<void> deleteAll();
}
