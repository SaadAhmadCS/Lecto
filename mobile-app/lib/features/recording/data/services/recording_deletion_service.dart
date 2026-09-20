import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/services/audio_merge_service.dart';
import '../local/recording_dao.dart';

/// Deletes a recording everywhere it exists.
///
/// Every caller used to delete only part of it: the backend row, or the local
/// database rows, but never the audio on disk — so a deleted recording left
/// its chunks behind forever. That matters most in "my own AI app" mode, where
/// the audio is the only copy and is meant to stay on the device.
class RecordingDeletionService {
  final LectoApiClient _api;
  final RecordingDao _dao;
  final Future<Directory> Function(String recordingId) _recordingDir;

  RecordingDeletionService({
    required LectoApiClient api,
    required RecordingDao dao,
    Future<Directory> Function(String)? recordingDir,
  })  : this._(api, dao, recordingDir ?? _defaultRecordingDir);

  RecordingDeletionService._(this._api, this._dao, this._recordingDir);

  static Future<Directory> _defaultRecordingDir(String recordingId) async {
    final docsDir = await getApplicationDocumentsDirectory();
    return Directory('${docsDir.path}/recordings/$recordingId');
  }

  /// Remove [recordingId] from the backend, this device's database and disk.
  ///
  /// [localOnly] skips the backend for a recording that never uploaded. A 404
  /// is treated as success either way: it means the row is already gone, and
  /// refusing to clean up locally would strand the audio.
  ///
  /// The backend goes first so that a genuine failure — offline, or a server
  /// error — aborts before anything local is destroyed.
  Future<void> delete(String recordingId, {bool localOnly = false}) async {
    if (!localOnly) {
      try {
        await _api.deleteRecording(recordingId);
      } on ApiException catch (e) {
        if (e.statusCode != 404) rethrow;
        debugPrint('RecordingDeletion: $recordingId already gone on backend');
      }
    }

    await _deleteFiles(recordingId);
    await _dao.deleteRecording(recordingId);
  }

  /// Delete the audio directory and any captured photos.
  ///
  /// Failures here are logged, not thrown: leaving a stray file behind is a
  /// better outcome than a half-deleted recording the user cannot remove.
  Future<void> _deleteFiles(String recordingId) async {
    try {
      for (final photo in await _dao.getPhotos(recordingId)) {
        final path = photo['file_path'] as String?;
        if (path == null) continue;
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    } catch (e) {
      debugPrint('RecordingDeletion: could not delete photos: $e');
    }

    try {
      final dir = await _recordingDir(recordingId);
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      debugPrint('RecordingDeletion: could not delete audio: $e');
    }

    // The merged copy made for sharing lives in the cache directory, so it
    // would otherwise outlive the recording it came from.
    await AudioMergeService.clearCache(recordingId);
  }
}
