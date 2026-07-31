import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Local SQLite database for offline persistence.
///
/// Stores recording sessions, chunk metadata, and photo references
/// so the app can recover from kills, crashes, and restarts.
class RecordingDatabase {
  static Database? _database;
  static const String _dbName = 'lecto_recordings.db';
  static const int _dbVersion = 1;

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
        synced INTEGER NOT NULL DEFAULT 0
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
  }

  static Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    // Future schema migrations go here
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
