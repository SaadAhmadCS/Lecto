import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../../core/network/upload_queue_service.dart';
import '../../../../core/network/upload_task_store.dart';
import 'recording_database.dart';

/// SQLite-backed [UploadTaskStore] in the local recordings database.
class SqliteUploadTaskStore implements UploadTaskStore {
  static const _table = 'upload_tasks';

  @override
  Future<List<UploadTask>> loadAll() async {
    final db = await RecordingDatabase.database;
    final rows = await db.query(_table, orderBy: 'seq ASC');
    return rows.map((row) {
      return UploadTask(
        id: row['id'] as String,
        type: UploadTaskType.values.byName(row['type'] as String),
        recordingId: row['recording_id'] as String,
        filePath: row['file_path'] as String?,
        metadata: jsonDecode(row['metadata'] as String) as Map<String, dynamic>,
        status: UploadTaskStatus.values.byName(row['status'] as String),
        attempts: row['attempts'] as int,
        createdAt: DateTime.parse(row['created_at'] as String),
      );
    }).toList();
  }

  @override
  Future<void> save(UploadTask task) async {
    final db = await RecordingDatabase.database;
    await db.insert(
      _table,
      {
        'id': task.id,
        'type': task.type.name,
        'recording_id': task.recordingId,
        'file_path': task.filePath,
        'metadata': jsonEncode(task.metadata),
        'status': task.status.name,
        'attempts': task.attempts,
        'created_at': task.createdAt.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  @override
  Future<void> update(UploadTask task) async {
    final db = await RecordingDatabase.database;
    await db.update(
      _table,
      {'status': task.status.name, 'attempts': task.attempts},
      where: 'id = ?',
      whereArgs: [task.id],
    );
  }

  @override
  Future<void> delete(String id) async {
    final db = await RecordingDatabase.database;
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> deleteAll() async {
    final db = await RecordingDatabase.database;
    await db.delete(_table);
  }
}
