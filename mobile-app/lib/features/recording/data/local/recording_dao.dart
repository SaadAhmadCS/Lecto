import 'package:sqflite/sqflite.dart';

import 'recording_database.dart';

/// Data Access Object for recording persistence.
///
/// Handles all CRUD operations against the local SQLite database.
/// Ensures recordings survive app kills, crashes, and restarts.
class RecordingDao {
  /// Insert a new recording session.
  Future<void> insertRecording({
    required String id,
    required String subjectId,
    required String title,
    String status = 'recording',
    String audioFormat = 'aac',
    int chunkDurationMin = 15,
  }) async {
    final db = await RecordingDatabase.database;
    final now = DateTime.now().toIso8601String();

    await db.insert(
      'recordings',
      {
        'id': id,
        'subject_id': subjectId,
        'title': title,
        'status': status,
        'audio_format': audioFormat,
        'chunk_duration_min': chunkDurationMin,
        'total_duration_ms': 0,
        'created_at': now,
        'updated_at': now,
        'synced': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Update recording status and duration.
  Future<void> updateRecording({
    required String id,
    String? status,
    int? totalDurationMs,
    bool? synced,
  }) async {
    final db = await RecordingDatabase.database;
    final updates = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (status != null) updates['status'] = status;
    if (totalDurationMs != null) updates['total_duration_ms'] = totalDurationMs;
    if (synced != null) updates['synced'] = synced ? 1 : 0;

    await db.update('recordings', updates, where: 'id = ?', whereArgs: [id]);
  }

  /// Get a recording by ID.
  Future<Map<String, dynamic>?> getRecording(String id) async {
    final db = await RecordingDatabase.database;
    final results = await db.query(
      'recordings',
      where: 'id = ?',
      whereArgs: [id],
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// List all recordings, optionally filtered by subject.
  Future<List<Map<String, dynamic>>> listRecordings({
    String? subjectId,
    String? status,
  }) async {
    final db = await RecordingDatabase.database;
    String? where;
    List<dynamic>? whereArgs;

    if (subjectId != null && status != null) {
      where = 'subject_id = ? AND status = ?';
      whereArgs = [subjectId, status];
    } else if (subjectId != null) {
      where = 'subject_id = ?';
      whereArgs = [subjectId];
    } else if (status != null) {
      where = 'status = ?';
      whereArgs = [status];
    }

    return db.query(
      'recordings',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'created_at DESC',
    );
  }

  /// Get recordings that need to be synced to the backend.
  Future<List<Map<String, dynamic>>> getUnsyncedRecordings() async {
    final db = await RecordingDatabase.database;
    return db.query(
      'recordings',
      where: 'synced = 0',
      orderBy: 'created_at ASC',
    );
  }

  /// Delete a recording and all its chunks/photos (via CASCADE).
  Future<void> deleteRecording(String id) async {
    final db = await RecordingDatabase.database;
    // Manual cascade since sqflite doesn't enforce FK constraints by default
    await db.delete('photos', where: 'recording_id = ?', whereArgs: [id]);
    await db.delete('audio_chunks', where: 'recording_id = ?', whereArgs: [id]);
    await db.delete('recordings', where: 'id = ?', whereArgs: [id]);
  }

  // === Audio Chunks ===

  /// Insert a completed chunk.
  Future<void> insertChunk({
    required String id,
    required String recordingId,
    required int sequenceNumber,
    required String filePath,
    required int durationMs,
    required int sizeBytes,
  }) async {
    final db = await RecordingDatabase.database;

    await db.insert(
      'audio_chunks',
      {
        'id': id,
        'recording_id': recordingId,
        'sequence_number': sequenceNumber,
        'file_path': filePath,
        'duration_ms': durationMs,
        'size_bytes': sizeBytes,
        'status': 'recorded',
        'upload_status': 'pending',
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Update chunk upload status.
  Future<void> updateChunkUploadStatus(String id, String uploadStatus) async {
    final db = await RecordingDatabase.database;
    await db.update(
      'audio_chunks',
      {'upload_status': uploadStatus},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Get all chunks for a recording.
  Future<List<Map<String, dynamic>>> getChunks(String recordingId) async {
    final db = await RecordingDatabase.database;
    return db.query(
      'audio_chunks',
      where: 'recording_id = ?',
      whereArgs: [recordingId],
      orderBy: 'sequence_number ASC',
    );
  }

  /// Get chunks pending upload.
  Future<List<Map<String, dynamic>>> getPendingChunks() async {
    final db = await RecordingDatabase.database;
    return db.query(
      'audio_chunks',
      where: "upload_status = 'pending'",
      orderBy: 'created_at ASC',
    );
  }

  // === Photos ===

  /// Insert a captured photo.
  Future<void> insertPhoto({
    required String id,
    required String recordingId,
    required int chunkIndex,
    required String filePath,
    required int timestampMs,
    required int sizeBytes,
  }) async {
    final db = await RecordingDatabase.database;

    await db.insert(
      'photos',
      {
        'id': id,
        'recording_id': recordingId,
        'chunk_index': chunkIndex,
        'file_path': filePath,
        'timestamp_ms': timestampMs,
        'size_bytes': sizeBytes,
        'upload_status': 'pending',
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get all photos for a recording.
  Future<List<Map<String, dynamic>>> getPhotos(String recordingId) async {
    final db = await RecordingDatabase.database;
    return db.query(
      'photos',
      where: 'recording_id = ?',
      whereArgs: [recordingId],
      orderBy: 'timestamp_ms ASC',
    );
  }

  /// Get total storage used by all local audio files (in bytes).
  Future<int> getTotalLocalStorageBytes() async {
    final db = await RecordingDatabase.database;
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(size_bytes), 0) as total FROM audio_chunks',
    );
    return (result.first['total'] as int?) ?? 0;
  }

  /// Count recordings by status.
  Future<Map<String, int>> getRecordingCountsByStatus() async {
    final db = await RecordingDatabase.database;
    final results = await db.rawQuery(
      'SELECT status, COUNT(*) as count FROM recordings GROUP BY status',
    );

    final counts = <String, int>{};
    for (final row in results) {
      counts[row['status'] as String] = (row['count'] as int?) ?? 0;
    }
    return counts;
  }
}
