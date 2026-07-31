/// App-wide constants
class AppConstants {
  AppConstants._();

  static const String appName = 'Lecto';
  static const String appTagline = 'Never miss a word.';

  // Recording
  static const int defaultChunkDurationMinutes = 15;
  static const int minChunkDurationMinutes = 5;
  static const int maxChunkDurationMinutes = 30;
  static const int audioSampleRate = 44100;
  static const int audioBitRate = 128000;

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
