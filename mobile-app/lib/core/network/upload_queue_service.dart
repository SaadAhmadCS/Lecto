// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/network/connectivity_service.dart';

/// Manages the offline-first upload queue for audio chunks and photos.
///
/// When online: uploads immediately after each chunk completes.
/// When offline: queues items and auto-retries when connectivity returns.
/// Implements exponential backoff for failed uploads.
class UploadQueueService {
  final ConnectivityService _connectivity;
  final Queue<UploadTask> _queue = Queue<UploadTask>();
  final List<UploadTask> _completed = [];
  final List<UploadTask> _failed = [];

  final _statusController = StreamController<UploadQueueStatus>.broadcast();
  StreamSubscription<bool>? _connectivitySub;
  Timer? _retryTimer;
  bool _isProcessing = false;

  UploadQueueService({required ConnectivityService connectivity})
      : _connectivity = connectivity;

  /// Stream of queue status updates.
  Stream<UploadQueueStatus> get statusStream => _statusController.stream;

  /// Current queue length.
  int get pendingCount => _queue.length;
  int get completedCount => _completed.length;
  int get failedCount => _failed.length;

  /// Initialize and listen for connectivity changes.
  void initialize() {
    _connectivitySub = _connectivity.onConnectivityChanged.listen((connected) {
      if (connected && _queue.isNotEmpty) {
        debugPrint('UploadQueue: Connectivity restored, processing queue...');
        _processQueue();
      }
    });
  }

  /// Enqueue a chunk for upload.
  void enqueueChunk({
    required String recordingId,
    required String chunkFilePath,
    required int sequenceNumber,
    required int durationMs,
    required int sizeBytes,
  }) {
    final task = UploadTask(
      id: '${recordingId}_chunk_$sequenceNumber',
      type: UploadTaskType.audioChunk,
      recordingId: recordingId,
      filePath: chunkFilePath,
      metadata: {
        'sequenceNumber': sequenceNumber,
        'durationMs': durationMs,
        'sizeBytes': sizeBytes,
      },
    );

    _queue.add(task);
    _emitStatus();
    debugPrint('UploadQueue: Enqueued chunk $sequenceNumber for $recordingId');

    // Try uploading immediately if online
    if (_connectivity.isConnected && !_isProcessing) {
      _processQueue();
    }
  }

  /// Enqueue a photo for upload.
  void enqueuePhoto({
    required String recordingId,
    required String photoFilePath,
    required String photoId,
    required int timestampMs,
    required int chunkIndex,
  }) {
    final task = UploadTask(
      id: '${recordingId}_photo_$photoId',
      type: UploadTaskType.photo,
      recordingId: recordingId,
      filePath: photoFilePath,
      metadata: {
        'photoId': photoId,
        'timestampMs': timestampMs,
        'chunkIndex': chunkIndex,
      },
    );

    _queue.add(task);
    _emitStatus();
    debugPrint('UploadQueue: Enqueued photo $photoId for $recordingId');

    if (_connectivity.isConnected && !_isProcessing) {
      _processQueue();
    }
  }

  /// Process the upload queue sequentially.
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
        await _uploadTask(task);
        _queue.removeFirst();
        task.status = UploadTaskStatus.completed;
        _completed.add(task);
        _emitStatus();
        debugPrint('UploadQueue: ✅ Uploaded ${task.id}');
      } catch (e) {
        debugPrint('UploadQueue: ❌ Failed ${task.id} (attempt ${task.attempts}): $e');

        if (task.attempts >= UploadTask.maxRetries) {
          _queue.removeFirst();
          task.status = UploadTaskStatus.failed;
          _failed.add(task);
          _emitStatus();
          debugPrint('UploadQueue: Task ${task.id} permanently failed after ${task.attempts} attempts');
        } else {
          task.status = UploadTaskStatus.pending;
          // Move to back of queue
          _queue.removeFirst();
          _queue.add(task);
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

  /// Upload a single task to the backend.
  Future<void> _uploadTask(UploadTask task) async {
    // Verify file exists before uploading
    final file = File(task.filePath);
    if (!await file.exists()) {
      throw UploadException('File not found: ${task.filePath}');
    }

    // TODO: Replace with actual HTTP upload via Dio
    // For now, simulate upload with a delay
    await Future.delayed(const Duration(milliseconds: 500));

    // In real implementation:
    // final dio = sl<Dio>();
    // switch (task.type) {
    //   case UploadTaskType.audioChunk:
    //     final formData = FormData.fromMap({
    //       'file': await MultipartFile.fromFile(task.filePath),
    //       'sequenceNumber': task.metadata['sequenceNumber'],
    //       'durationMs': task.metadata['durationMs'],
    //       'sizeBytes': task.metadata['sizeBytes'],
    //     });
    //     await dio.post(
    //       '/api/v1/recordings/${task.recordingId}/chunks',
    //       data: formData,
    //     );
    //   case UploadTaskType.photo:
    //     final formData = FormData.fromMap({
    //       'file': await MultipartFile.fromFile(task.filePath),
    //       'timestampMs': task.metadata['timestampMs'],
    //       'chunkIndex': task.metadata['chunkIndex'],
    //     });
    //     await dio.post(
    //       '/api/v1/recordings/${task.recordingId}/photos',
    //       data: formData,
    //     );
    // }
  }

  /// Retry all permanently failed tasks.
  void retryFailed() {
    for (final task in _failed) {
      task.attempts = 0;
      task.status = UploadTaskStatus.pending;
      _queue.add(task);
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

  /// Check if all chunks for a recording have been uploaded.
  bool isRecordingFullyUploaded(String recordingId) {
    final pending = _queue.where((t) => t.recordingId == recordingId);
    return pending.isEmpty;
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
  }
}

/// A single upload task in the queue.
class UploadTask {
  static const int maxRetries = 5;

  final String id;
  final UploadTaskType type;
  final String recordingId;
  final String filePath;
  final Map<String, dynamic> metadata;
  UploadTaskStatus status;
  int attempts;
  final DateTime createdAt;

  UploadTask({
    required this.id,
    required this.type,
    required this.recordingId,
    required this.filePath,
    required this.metadata,
    this.status = UploadTaskStatus.pending,
    this.attempts = 0,
  }) : createdAt = DateTime.now();
}

enum UploadTaskType { audioChunk, photo }

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
