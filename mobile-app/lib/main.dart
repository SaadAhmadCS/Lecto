import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/di/service_locator.dart';
import 'core/network/upload_queue_service.dart';
import 'core/permissions/permission_service.dart';
import 'core/routes/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/recording/data/local/recording_dao.dart';
import 'features/recording/data/services/audio_recorder_service.dart';
import 'features/recording/data/services/photo_capture_service.dart';
import 'features/recording/data/services/storage_monitor_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait mode
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Initialize dependencies
  await initServiceLocator();

  runApp(const LectoApp());
}

/// Root application widget.
class LectoApp extends StatelessWidget {
  const LectoApp({super.key});

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
      ],
      child: MaterialApp.router(
        title: 'Lecto',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark, // Default to dark
        routerConfig: AppRouter.router,
      ),
    );
  }
}
