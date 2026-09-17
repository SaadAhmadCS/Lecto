import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:go_router/go_router.dart';

import 'core/di/service_locator.dart';
import 'core/errors/app_error_handler.dart';
import 'core/network/api_client.dart';
import 'core/network/upload_queue_service.dart';
import 'core/permissions/permission_service.dart';
import 'core/routes/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/services/foreground_recording_service.dart';
import 'core/services/auth_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/session_service.dart';
import 'features/recording/data/local/recording_dao.dart';
import 'features/recording/data/services/audio_recorder_service.dart';
import 'features/recording/data/services/photo_capture_service.dart';
import 'features/recording/data/services/recording_recovery_service.dart';
import 'features/recording/data/services/storage_monitor_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppErrorHandler.install();

  await Firebase.initializeApp();

  final prefs = await SharedPreferences.getInstance();
  final hasCompletedOnboarding = prefs.getBool('hasCompletedOnboarding') ?? false;

  // Initialize foreground service
  ForegroundRecordingService.init();

  // Lock to portrait mode
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Initialize dependencies
  await initServiceLocator();
  final isAuthenticated = sl<AuthService>().isSignedIn;

  final router = AppRouter.router(
    showOnboarding: !hasCompletedOnboarding,
    isAuthenticated: isAuthenticated,
  );

  // Tapping a "notes ready" notification opens that recording
  final notifications = sl<NotificationService>();
  void openRecording(String id) => router.push('/recording/$id');
  notifications.onRecordingTapped = openRecording;

  runApp(LectoApp(router: router));

  if (isAuthenticated) unawaited(_recoverInterruptedRecordings());

  final launchRecordingId = await notifications.launchRecordingId();
  if (launchRecordingId != null && isAuthenticated) {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => openRecording(launchRecordingId),
    );
  }
}

/// Finish recordings cut off by an app kill or crash, and tell the user.
Future<void> _recoverInterruptedRecordings() async {
  try {
    final recovered = await sl<RecordingRecoveryService>().recoverInterrupted();
    if (recovered.isEmpty) return;

    final notifications = sl<NotificationService>();
    await notifications.requestPermissionIfNeeded();
    for (final recording in recovered) {
      final minutes = recording.duration.inMinutes;
      await notifications.showRecordingUpdate(
        recordingId: recording.recordingId,
        title: 'Recording saved: ${recording.title}',
        body: 'Lecto closed while recording. '
            '${minutes < 1 ? 'Less than a minute' : '$minutes min'} of audio was '
            'saved and will be processed'
            '${recording.lostEnd ? '; the last part before it closed couldn\'t be saved.' : '.'}',
      );
    }
  } catch (e, stack) {
    AppErrorHandler.report(e, stack, context: 'recording recovery');
  }
}

/// Root application widget.
class LectoApp extends StatelessWidget {
  final GoRouter router;

  const LectoApp({super.key, required this.router});

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<PermissionService>.value(
          value: sl<PermissionService>(),
        ),
        RepositoryProvider<StorageMonitorService>.value(
          value: sl<StorageMonitorService>(),
        ),
        RepositoryProvider<AudioRecorderService>.value(
          value: sl<AudioRecorderService>(),
        ),
        RepositoryProvider<PhotoCaptureService>.value(
          value: sl<PhotoCaptureService>(),
        ),
        RepositoryProvider<RecordingDao>.value(
          value: sl<RecordingDao>(),
        ),
        RepositoryProvider<UploadQueueService>.value(
          value: sl<UploadQueueService>(),
        ),
        RepositoryProvider<LectoApiClient>.value(
          value: sl<LectoApiClient>(),
        ),
        RepositoryProvider<AuthService>.value(
          value: sl<AuthService>(),
        ),
        RepositoryProvider<SessionService>.value(
          value: sl<SessionService>(),
        ),
      ],
      child: MaterialApp.router(
        title: 'Lecto',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark, // Default to dark
        routerConfig: router,
      ),
    );
  }
}
