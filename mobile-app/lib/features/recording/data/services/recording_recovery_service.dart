// ignore_for_file: prefer_initializing_formals
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../core/network/upload_queue_service.dart';
import '../local/recording_dao.dart';

/// Finishes recordings that were interrupted — the app was killed, crashed or
/// the phone died mid-lecture — so they don't sit at "Uploading audio"
/// forever.
///
/// Every chunk that finished recording was already saved and queued for
/// upload. The chunk being written when the app died is an unfinalized .m4a
/// that can't be decoded (and would fail transcription for the whole
/// recording), so it is discarded. What's left is completed like a normal
/// stop, which starts processing once the queued chunks upload.
class RecordingRecoveryService {
  final RecordingDao _dao;
  final UploadQueueService _uploadQueue;
  final Future<Directory> Function(String recordingId) _recordingDir;

  RecordingRecoveryService({
    required RecordingDao dao,
    required UploadQueueService uploadQueue,
    Future<Directory> Function(String recordingId)? recordingDir,
  })  : _dao = dao,
        _uploadQueue = uploadQueue,
        _recordingDir = recordingDir ?? _defaultRecordingDir;

  // Where AudioRecorderService writes a recording's chunks
  static Future<Directory> _defaultRecordingDir(String recordingId) async {
    final docsDir = await getApplicationDocumentsDirectory();
    return Directory('${docsDir.path}/recordings/$recordingId');
  }

  /// Call at launch, before any new recording can start.
  Future<List<RecoveredRecording>> recoverInterrupted() async {
    final recovered = <RecoveredRecording>[];
    final interrupted = await _dao.listRecordings(status: 'recording');

    for (final row in interrupted) {
      final id = row['id'] as String;
      try {
        final result = await _recover(id, row['title'] as String? ?? 'Recording');
        if (result != null) recovered.add(result);
      } catch (e) {
        debugPrint('RecordingRecovery: failed to recover $id: $e');
      }
    }
    return recovered;
  }

  Future<RecoveredRecording?> _recover(String id, String title) async {
    final saved = await _savedChunks(id);
    final dir = await _recordingDir(id);

    if (saved.isEmpty) {
      // Died before the first chunk finished: nothing usable to process.
      debugPrint('RecordingRecovery: $id has no finished audio, discarding');
      _uploadQueue.enqueueDeleteRecording(recordingId: id);
      await _dao.deleteRecording(id);
      if (await dir.exists()) await dir.delete(recursive: true);
      return null;
    }

    final lostEnd = await _deleteUnsavedChunkFiles(dir, keep: saved.values);

    final totalDurationMs = saved.values.fold<int>(0, (sum, c) => sum + c.durationMs);
    await _dao.updateRecording(
      id: id,
      status: 'completed',
      totalDurationMs: totalDurationMs,
    );
    // Queued behind the chunks restored from the last run
    _uploadQueue.enqueueCompleteRecording(
      recordingId: id,
      totalDurationMs: totalDurationMs,
    );

    debugPrint(
      'RecordingRecovery: recovered $id '
      '(${saved.length} chunk(s), ${totalDurationMs ~/ 1000}s)',
    );
    return RecoveredRecording(
      recordingId: id,
      title: title,
      duration: Duration(milliseconds: totalDurationMs),
      lostEnd: lostEnd,
    );
  }

  /// Finished chunks by sequence number: those saved to the local DB plus
  /// any still in the upload queue (a chunk is queued just before its DB
  /// row is written).
  Future<Map<int, _SavedChunk>> _savedChunks(String recordingId) async {
    final chunks = <int, _SavedChunk>{};
    for (final row in await _dao.getChunks(recordingId)) {
      chunks[row['sequence_number'] as int] = _SavedChunk(
        row['file_path'] as String,
        row['duration_ms'] as int? ?? 0,
      );
    }
    for (final task in _uploadQueue.getTasksForRecording(recordingId)) {
      if (task.type != UploadTaskType.audioChunk || task.filePath == null) continue;
      chunks.putIfAbsent(
        task.metadata['sequenceNumber'] as int,
        () => _SavedChunk(task.filePath!, task.metadata['durationMs'] as int? ?? 0),
      );
    }
    return chunks;
  }

  /// Remove chunk files in the recording's folder that were never finished.
  /// Returns whether any unfinished audio was discarded.
  Future<bool> _deleteUnsavedChunkFiles(
    Directory dir, {
    required Iterable<_SavedChunk> keep,
  }) async {
    if (!await dir.exists()) return false;
    final keepPaths = keep.map((c) => p.canonicalize(c.path)).toSet();

    var discarded = false;
    await for (final entity in dir.list()) {
      if (entity is File &&
          entity.path.endsWith('.m4a') &&
          !keepPaths.contains(p.canonicalize(entity.path))) {
        debugPrint('RecordingRecovery: discarding unfinished chunk ${entity.path}');
        await entity.delete();
        discarded = true;
      }
    }
    return discarded;
  }
}

class RecoveredRecording {
  final String recordingId;
  final String title;
  final Duration duration;

  /// Audio recorded after the last finished chunk couldn't be kept.
  final bool lostEnd;

  const RecoveredRecording({
    required this.recordingId,
    required this.title,
    required this.duration,
    required this.lostEnd,
  });
}

class _SavedChunk {
  final String path;
  final int durationMs;

  const _SavedChunk(this.path, this.durationMs);
}
