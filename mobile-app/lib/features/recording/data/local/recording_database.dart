import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Local SQLite database for offline persistence.
///
/// Stores recording sessions, chunk metadata, and photo references
/// so the app can recover from kills, crashes, and restarts.
class RecordingDatabase {
  static Database? _database;
  static const String _dbName = 'lecto_recordings.db';
  static const int _dbVersion = 3;

  /// Get the database instance, creating it if needed.
  static Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    // Recording sessions table
    await db.execute('''
      CREATE TABLE recordings (
        id TEXT PRIMARY KEY,
        subject_id TEXT NOT NULL,
        title TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'recording',
        audio_format TEXT NOT NULL DEFAULT 'aac',
        chunk_duration_min INTEGER NOT NULL DEFAULT 15,
        total_duration_ms INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0,
        notes_markdown TEXT,
        transcript_markdown TEXT,
        notes_source TEXT,
        notes_updated_at TEXT,
        capture_notes_source TEXT
      )
    ''');

    // Audio chunks table
    await db.execute('''
      CREATE TABLE audio_chunks (
        id TEXT PRIMARY KEY,
        recording_id TEXT NOT NULL,
        sequence_number INTEGER NOT NULL,
        file_path TEXT NOT NULL,
        duration_ms INTEGER NOT NULL DEFAULT 0,
        size_bytes INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'recorded',
        upload_status TEXT NOT NULL DEFAULT 'pending',
        created_at TEXT NOT NULL,
        FOREIGN KEY (recording_id) REFERENCES recordings(id) ON DELETE CASCADE
      )
    ''');

    // Captured photos table
    await db.execute('''
      CREATE TABLE photos (
        id TEXT PRIMARY KEY,
        recording_id TEXT NOT NULL,
        chunk_index INTEGER NOT NULL,
        file_path TEXT NOT NULL,
        timestamp_ms INTEGER NOT NULL,
        size_bytes INTEGER NOT NULL DEFAULT 0,
        upload_status TEXT NOT NULL DEFAULT 'pending',
        created_at TEXT NOT NULL,
        FOREIGN KEY (recording_id) REFERENCES recordings(id) ON DELETE CASCADE
      )
    ''');

    // Indexes for fast queries
    await db.execute(
      'CREATE INDEX idx_chunks_recording ON audio_chunks(recording_id)',
    );
    await db.execute(
      'CREATE INDEX idx_photos_recording ON photos(recording_id)',
    );
    await db.execute(
      'CREATE INDEX idx_recordings_status ON recordings(status)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX idx_chunks_unique ON audio_chunks(recording_id, sequence_number)',
    );

    await _createUploadTasksTable(db);
  }

  static Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await _createUploadTasksTable(db);
    }
    if (oldVersion < 3) {
      await _addLocalNotesColumns(db);
    }
  }

  /// Notes and transcript kept on the device (v3).
  ///
  /// Needed for notes pasted back from the student's own AI app, and it also
  /// means notes stay readable with no connection.
  static Future<void> _addLocalNotesColumns(Database db) async {
    for (final column in const [
      'notes_markdown TEXT',
      'transcript_markdown TEXT',
      'notes_source TEXT',
      'notes_updated_at TEXT',
      // Which mode the recording was captured in, so crash recovery knows
      // whether its audio was ever meant to be uploaded.
      'capture_notes_source TEXT',
    ]) {
      await db.execute('ALTER TABLE recordings ADD COLUMN $column');
    }
  }

  /// Persistent sync queue (v2). `seq` preserves enqueue order across restarts.
  static Future<void> _createUploadTasksTable(Database db) async {
    await db.execute('''
      CREATE TABLE upload_tasks (
        seq INTEGER PRIMARY KEY AUTOINCREMENT,
        id TEXT NOT NULL UNIQUE,
        type TEXT NOT NULL,
        recording_id TEXT NOT NULL,
        file_path TEXT,
        metadata TEXT NOT NULL,
        status TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
  }

  /// Delete every row (sign-out). The schema stays in place.
  static Future<void> clearAll() async {
    final db = await database;
    await db.transaction((txn) async {
      for (final table in ['photos', 'audio_chunks', 'recordings', 'upload_tasks']) {
        await txn.delete(table);
      }
    });
  }

  /// Close the database.
  static Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
