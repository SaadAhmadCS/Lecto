// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../network/api_client.dart';
import '../network/upload_queue_service.dart';
import 'notification_service.dart';

/// Notifies the user when a recording's transcript and notes are ready.
///
/// Watching starts when a recording's completion syncs to the backend (not
/// from the detail screen), so the user is told wherever they are in the app
/// — or while it's in the background. No notification is shown for the
/// recording the user is already looking at.
class ProcessingNotifier {
  final LectoApiClient _api;
  final UploadQueueService _uploadQueue;
  final NotificationService _notifications;

  /// Recording currently open in the detail screen, if any.
  static String? viewingRecordingId;

  static const _pollInterval = Duration(seconds: 15);
  // Long lectures can take a while; stop watching after 3 hours.
  static const _maxPolls = 720;

  final Set<String> _watching = {};
  // Bumped by [reset] so polls scheduled before it stop.
  int _generation = 0;
  StreamSubscription<UploadTask>? _queueSub;

  ProcessingNotifier({
    required LectoApiClient apiClient,
    required UploadQueueService uploadQueue,
    required NotificationService notifications,
  })  : _api = apiClient,
        _uploadQueue = uploadQueue,
        _notifications = notifications;

  void start() {
    _queueSub = _uploadQueue.taskCompleted
        .where((task) => task.type == UploadTaskType.completeRecording)
        .listen((task) => watch(task.recordingId));
  }

  void watch(String recordingId) {
    if (!_watching.add(recordingId)) return;
    _notifications.requestPermissionIfNeeded();
    _poll(recordingId, 0, _generation);
  }

  /// Stop watching everything (sign-out).
  void reset() {
    _generation++;
    _watching.clear();
  }

  Future<void> _poll(String recordingId, int attempt, int generation) async {
    if (generation != _generation) return;
    try {
      final response = await _api.getProcessingStatus(recordingId);
      final data = response['data'] as Map<String, dynamic>;
      final status = data['processingStatus'] as String? ?? '';

      if (generation != _generation) return;
      if (status == 'completed' || status.startsWith('failed')) {
        _watching.remove(recordingId);
        await _notify(recordingId, succeeded: status == 'completed');
        return;
      }
    } catch (e) {
      // Offline or server hiccup — keep trying
      debugPrint('ProcessingNotifier: status check failed for $recordingId: $e');
    }

    if (attempt + 1 >= _maxPolls) {
      _watching.remove(recordingId);
      return;
    }
    Timer(_pollInterval, () => _poll(recordingId, attempt + 1, generation));
  }

  Future<void> _notify(String recordingId, {required bool succeeded}) async {
    if (viewingRecordingId == recordingId) return;

    var title = 'Your lecture';
    try {
      final response = await _api.getRecording(recordingId);
      title = (response['data'] as Map<String, dynamic>)['title'] as String? ?? title;
    } catch (_) {
      // Fall back to the generic title
    }

    await _notifications.showRecordingUpdate(
      recordingId: recordingId,
      title: succeeded ? 'Notes ready: $title' : 'Processing failed: $title',
      body: succeeded
          ? 'Your transcript and study notes are ready to review.'
          : 'Tap to open the recording and retry.',
    );
  }

  void dispose() {
    _queueSub?.cancel();
  }
}
