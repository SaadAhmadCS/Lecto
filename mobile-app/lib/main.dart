import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';

import 'core/di/service_locator.dart';
import 'core/network/api_client.dart';
import 'core/network/upload_queue_service.dart';
import 'core/permissions/permission_service.dart';
import 'core/routes/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/services/foreground_recording_service.dart';
import 'core/services/auth_service.dart';
import 'features/recording/data/local/recording_dao.dart';
import 'features/recording/data/services/audio_recorder_service.dart';
import 'features/recording/data/services/photo_capture_service.dart';
import 'features/recording/data/services/storage_monitor_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();

  final prefs = await SharedPreferences.getInstance();
  final hasCompletedOnboarding = prefs.getBool('hasCompletedOnboarding') ?? false;
  
  final authService = AuthService();
  final isAuthenticated = authService.isSignedIn;

  // Initialize foreground service
  ForegroundRecordingService.init();

  // Lock to portrait mode
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Initialize dependencies
  await initServiceLocator();

  runApp(LectoApp(
    hasCompletedOnboarding: hasCompletedOnboarding,
    isAuthenticated: isAuthenticated,
  ));
}

/// Root application widget.
class LectoApp extends StatelessWidget {
  final bool hasCompletedOnboarding;
  final bool isAuthenticated;
  
  const LectoApp({
    super.key, 
    required this.hasCompletedOnboarding,
    required this.isAuthenticated,
  });

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
        RepositoryProvider<AuthService>(
          create: (_) => AuthService(),
        ),
      ],
      child: MaterialApp.router(
        title: 'Lecto',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark, // Default to dark
        routerConfig: AppRouter.router(
          showOnboarding: !hasCompletedOnboarding,
          isAuthenticated: isAuthenticated,
        ),
      ),
    );
  }
}
