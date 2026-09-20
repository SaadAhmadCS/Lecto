/// App-wide constants
class AppConstants {
  AppConstants._();

  static const String appName = 'Lecto';
  static const String appTagline = 'Never miss a word.';

  // Recording
  /// Minutes of audio per chunk.
  ///
  /// 20 rather than 15 so a 3-hour lecture is 9 chunks. AI apps take 10 files
  /// per prompt — one of which is the prompt itself — so 15-minute chunks made
  /// a 3-hour lecture unshareable in one go. 3 hours is also Gemini's own
  /// audio ceiling, so this covers everything it can accept.
  ///
  /// Overridable so a long lecture's chunk count can be reproduced in minutes
  /// rather than hours:
  /// `flutter run --dart-define=CHUNK_MINUTES=1`
  static const int defaultChunkDurationMinutes = int.fromEnvironment(
    'CHUNK_MINUTES',
    defaultValue: 20,
  );
  static const int minChunkDurationMinutes = 5;
  static const int maxChunkDurationMinutes = 30;
  // HE-AAC at 24kbps mono keeps a 3-hour lecture around 32MB instead of the
  // ~173MB the old 128kbps setting produced. Speech survives this bitrate
  // comfortably, Whisper accepts it, and the .m4a container is what the AI
  // apps accept when a recording is shared out.
  static const int audioSampleRate = 22050;
  static const int audioBitRate = 24000;

  // REC-016: sessions stop automatically at 8 hours, with a warning 15 min before
  static const Duration maxRecordingDuration = Duration(hours: 8);
  static const Duration maxRecordingWarningAt = Duration(hours: 7, minutes: 45);

  // Storage
  static const int storageWarningThresholdMB = 500;
  static const int storageCriticalThresholdMB = 100;
  static const int audioRetentionDays = 7;

  // API
  static const Duration apiTimeout = Duration(seconds: 30);
  static const Duration uploadTimeout = Duration(minutes: 5);
  static const int maxRetryAttempts = 3;

  // UI
  static const Duration splashDuration = Duration(seconds: 2);
  static const int maxSubjectNameLength = 50;
  static const int maxRecordingTitleLength = 100;
}
