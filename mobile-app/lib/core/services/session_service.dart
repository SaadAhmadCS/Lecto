// ignore_for_file: prefer_initializing_formals
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/recording/data/local/recording_database.dart';
import '../network/upload_queue_service.dart';
import 'auth_service.dart';
import 'notification_service.dart';
import 'processing_notifier.dart';

/// Signs the user out and removes everything the app kept on this device
/// for them, so the next account starts clean and never uploads, sees or
/// is notified about the previous account's recordings.
class SessionService {
  final AuthService _auth;
  final UploadQueueService _uploadQueue;
  final ProcessingNotifier _processingNotifier;
  final NotificationService _notifications;

  SessionService({
    required AuthService auth,
    required UploadQueueService uploadQueue,
    required ProcessingNotifier processingNotifier,
    required NotificationService notifications,
  })  : _auth = auth,
        _uploadQueue = uploadQueue,
        _processingNotifier = processingNotifier,
        _notifications = notifications;

  /// Recordings whose audio hasn't fully reached the server; signing out
  /// deletes them for good.
  int get unsyncedRecordingCount => _uploadQueue.unsyncedRecordingCount;

  Future<void> signOut() async {
    // Stop network work first, while nothing has been deleted under it.
    _processingNotifier.reset();
    await _cleanup('upload queue', _uploadQueue.clear);

    await _cleanup('local database', RecordingDatabase.clearAll);
    await _cleanup('recording files', () async {
      final docsDir = await getApplicationDocumentsDirectory();
      final recordings = Directory('${docsDir.path}/recordings');
      if (await recordings.exists()) {
        await recordings.delete(recursive: true);
      }
    });
    await _cleanup('notifications', _notifications.cancelAll);
    // Includes the onboarding flag, so the next account gets the
    // first-subject setup.
    await _cleanup('preferences', () async {
      await (await SharedPreferences.getInstance()).clear();
    });

    await _auth.signOut();
  }

  /// A failed cleanup step must not keep the user signed in.
  Future<void> _cleanup(String what, Future<void> Function() step) async {
    try {
      await step();
    } catch (e) {
      debugPrint('SessionService: failed to clear $what: $e');
    }
  }
}
