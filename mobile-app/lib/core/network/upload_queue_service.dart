// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';
import '../../core/network/connectivity_service.dart';
import 'upload_task_store.dart';

/// Manages the offline-first sync queue for recordings.
///
/// Each recording produces tasks in order: create → audio chunks → complete.
/// Tasks run strictly FIFO and a failing task stays at the head while it
/// retries, so the backend always sees a recording before its chunks, and
/// completion (which triggers AI processing) only after every chunk.
///
/// When online: tasks run immediately.
/// When offline: tasks wait and resume when connectivity returns.
/// Tasks are persisted, so work queued before an app kill resumes on the
/// next launch.
class UploadQueueService {
  final ConnectivityService _connectivity;
  final LectoApiClient _api;
  final UploadTaskStore _store;
  final Queue<UploadTask> _queue = Queue<UploadTask>();
  final List<UploadTask> _completed = [];
  final List<UploadTask> _failed = [];

  final _statusController = StreamController<UploadQueueStatus>.broadcast();
  final _taskCompletedController = StreamController<UploadTask>.broadcast();
  StreamSubscription<bool>? _connectivitySub;
  Timer? _retryTimer;
  bool _isProcessing = false;

  // Store writes are chained so they hit the database in call order.
  Future<void> _storeOps = Future.value();

  UploadQueueService({
    required ConnectivityService connectivity,
    required LectoApiClient apiClient,
    required UploadTaskStore store,
  })  : _connectivity = connectivity,
        _api = apiClient,
        _store = store;

  /// Stream of queue status updates.
  Stream<UploadQueueStatus> get statusStream => _statusController.stream;

  /// Emits each task after it succeeds against the backend.
  Stream<UploadTask> get taskCompleted => _taskCompletedController.stream;

  /// Current queue length.
  int get pendingCount => _queue.length;
  int get completedCount => _completed.length;
  int get failedCount => _failed.length;

  /// Restore persisted tasks, listen for connectivity, and resume work.
  Future<void> initialize() async {
    for (final task in await _store.loadAll()) {
      if (task.status == UploadTaskStatus.failed) {
        _failed.add(task);
      } else {
        task.status = UploadTaskStatus.pending;
        _queue.add(task);
      }
    }
    if (_queue.isNotEmpty) {
      debugPrint('UploadQueue: Restored ${_queue.length} pending task(s)');
    }

    _connectivitySub = _connectivity.onConnectivityChanged.listen((connected) {
      if (connected && _queue.isNotEmpty) {
        debugPrint('UploadQueue: Connectivity restored, processing queue...');
        _processQueue();
      }
    });

    _emitStatus();
    if (_connectivity.isConnected) {
      _processQueue();
    }
  }

  /// Enqueue creation of the recording on the backend.
  /// Must be enqueued before any of the recording's chunks.
  void enqueueCreateRecording({
    required String recordingId,
    required String subjectId,
    required String title,
    String? language,
  }) {
    _enqueue(UploadTask(
      id: '${recordingId}_create',
      type: UploadTaskType.createRecording,
      recordingId: recordingId,
      metadata: {
        'subjectId': subjectId,
        'title': title,
        if (language != null) 'language': language,
      },
    ));
  }

  /// Enqueue a chunk for upload.
  void enqueueChunk({
    required String recordingId,
    required String chunkFilePath,
    required int sequenceNumber,
    required int durationMs,
    required int sizeBytes,
  }) {
    _enqueue(UploadTask(
      id: '${recordingId}_chunk_$sequenceNumber',
      type: UploadTaskType.audioChunk,
      recordingId: recordingId,
      filePath: chunkFilePath,
      metadata: {
        'sequenceNumber': sequenceNumber,
        'durationMs': durationMs,
        'sizeBytes': sizeBytes,
      },
    ));
  }

  /// Enqueue marking the recording completed, which starts AI processing.
  /// Must be enqueued after the recording's final chunk.
  void enqueueCompleteRecording({
    required String recordingId,
    required int totalDurationMs,
  }) {
    _enqueue(UploadTask(
      id: '${recordingId}_complete',
      type: UploadTaskType.completeRecording,
      recordingId: recordingId,
      metadata: {'totalDurationMs': totalDurationMs},
    ));
  }

  void _enqueue(UploadTask task) {
    if (_queue.any((t) => t.id == task.id)) return;
    _queue.add(task);
    _persist(() => _store.save(task));
    _emitStatus();
    debugPrint('UploadQueue: Enqueued ${task.id}');

    // Try immediately if online
    if (_connectivity.isConnected && !_isProcessing) {
      _processQueue();
    }
  }

  /// Process the queue sequentially.
  Future<void> _processQueue() async {
    if (_isProcessing || _queue.isEmpty) return;
    _isProcessing = true;

    while (_queue.isNotEmpty) {
      if (!_connectivity.isConnected) {
        debugPrint('UploadQueue: Offline, pausing queue processing');
        break;
      }

      final task = _queue.first;
      task.status = UploadTaskStatus.uploading;
      task.attempts++;
      _emitStatus();

      try {
        await _runTask(task);
        _queue.removeFirst();
        task.status = UploadTaskStatus.completed;
        _completed.add(task);
        _taskCompletedController.add(task);
        _persist(() => _store.delete(task.id));
        _emitStatus();
        debugPrint('UploadQueue: ✅ ${task.id}');
      } catch (e) {
        debugPrint('UploadQueue: ❌ Failed ${task.id} (attempt ${task.attempts}): $e');

        if (task.attempts >= UploadTask.maxRetries) {
          _queue.removeFirst();
          task.status = UploadTaskStatus.failed;
          _failed.add(task);
          _persist(() => _store.update(task));
          _emitStatus();
          debugPrint('UploadQueue: Task ${task.id} permanently failed after ${task.attempts} attempts');
        } else {
          // Keep the task at the head so later tasks for the same recording
          // don't run out of order.
          task.status = UploadTaskStatus.pending;
          _persist(() => _store.update(task));
          _emitStatus();

          // Exponential backoff before retrying
          final delay = Duration(seconds: (2 << (task.attempts - 1)).clamp(1, 60));
          debugPrint('UploadQueue: Retrying ${task.id} in ${delay.inSeconds}s');
          _isProcessing = false;
          _retryTimer?.cancel();
          _retryTimer = Timer(delay, _processQueue);
          return;
        }
      }
    }

    _isProcessing = false;
    if (_queue.isEmpty && _completed.isNotEmpty) {
      debugPrint('UploadQueue: All uploads complete!');
    }
  }

  /// Run a single task against the backend. Throws on failure.
  Future<void> _runTask(UploadTask task) async {
    switch (task.type) {
      case UploadTaskType.createRecording:
        await _api.createRecording(
          id: task.recordingId,
          subjectId: task.metadata['subjectId'] as String,
          title: task.metadata['title'] as String,
          language: task.metadata['language'] as String?,
        );

      case UploadTaskType.audioChunk:
        final filePath = task.filePath!;
        if (!await File(filePath).exists()) {
          throw UploadException('File not found: $filePath');
        }
        await _api.uploadChunk(
          recordingId: task.recordingId,
          filePath: filePath,
          sequenceNumber: task.metadata['sequenceNumber'] as int,
          durationMs: task.metadata['durationMs'] as int,
        );

      case UploadTaskType.completeRecording:
        await _api.completeRecording(
          task.recordingId,
          totalDurationMs: task.metadata['totalDurationMs'] as int,
        );
    }
  }

  /// Retry all permanently failed tasks.
  void retryFailed() {
    for (final task in _failed) {
      task.attempts = 0;
      task.status = UploadTaskStatus.pending;
      _queue.add(task);
      _persist(() => _store.update(task));
    }
    _failed.clear();
    _emitStatus();

    if (_connectivity.isConnected) {
      _processQueue();
    }
  }

  /// Get all tasks for a specific recording.
  List<UploadTask> getTasksForRecording(String recordingId) {
    return [
      ..._queue.where((t) => t.recordingId == recordingId),
      ..._completed.where((t) => t.recordingId == recordingId),
      ..._failed.where((t) => t.recordingId == recordingId),
    ];
  }

  /// Check if all tasks for a recording have finished.
  bool isRecordingFullyUploaded(String recordingId) {
    final pending = _queue.where((t) => t.recordingId == recordingId);
    return pending.isEmpty;
  }

  void _persist(Future<void> Function() op) {
    _storeOps = _storeOps.then((_) => op()).catchError((Object e) {
      debugPrint('UploadQueue: Failed to persist task change: $e');
    });
  }

  void _emitStatus() {
    _statusController.add(UploadQueueStatus(
      pending: _queue.length,
      completed: _completed.length,
      failed: _failed.length,
      isProcessing: _isProcessing,
      isOnline: _connectivity.isConnected,
    ));
  }

  void dispose() {
    _connectivitySub?.cancel();
    _retryTimer?.cancel();
    _statusController.close();
    _taskCompletedController.close();
  }
}

/// A single task in the sync queue.
class UploadTask {
  static const int maxRetries = 5;

  final String id;
  final UploadTaskType type;
  final String recordingId;
  final String? filePath;
  final Map<String, dynamic> metadata;
  UploadTaskStatus status;
  int attempts;
  final DateTime createdAt;

  UploadTask({
    required this.id,
    required this.type,
    required this.recordingId,
    this.filePath,
    required this.metadata,
    this.status = UploadTaskStatus.pending,
    this.attempts = 0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
}

enum UploadTaskType { createRecording, audioChunk, completeRecording }

enum UploadTaskStatus { pending, uploading, completed, failed }

/// Queue status snapshot.
class UploadQueueStatus {
  final int pending;
  final int completed;
  final int failed;
  final bool isProcessing;
  final bool isOnline;

  const UploadQueueStatus({
    required this.pending,
    required this.completed,
    required this.failed,
    required this.isProcessing,
    required this.isOnline,
  });

  bool get hasWork => pending > 0 || isProcessing;
  int get total => pending + completed + failed;
}

class UploadException implements Exception {
  final String message;
  const UploadException(this.message);

  @override
  String toString() => 'UploadException: $message';
}
