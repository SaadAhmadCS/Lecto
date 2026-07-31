import 'package:get_it/get_it.dart';

import '../network/api_client.dart';
import '../network/connectivity_service.dart';
import '../network/upload_queue_service.dart';
import '../permissions/permission_service.dart';
import '../../features/recording/data/local/recording_dao.dart';
import '../../features/recording/data/services/audio_recorder_service.dart';
import '../../features/recording/data/services/photo_capture_service.dart';
import '../../features/recording/data/services/storage_monitor_service.dart';

final sl = GetIt.instance;

/// Initialize all dependency injection bindings.
///
/// Called once at app startup before runApp().
Future<void> initServiceLocator() async {
  // === Core Services ===
  final connectivityService = ConnectivityService();
  await connectivityService.initialize();
  sl.registerLazySingleton<ConnectivityService>(
    () => connectivityService,
  );

  sl.registerLazySingleton<PermissionService>(
    () => PermissionService(),
  );

  // === Upload Queue ===
  sl.registerLazySingleton<UploadQueueService>(() {
    final service = UploadQueueService(
      connectivity: sl<ConnectivityService>(),
    );
    service.initialize();
    return service;
  });

  // === Recording Services ===
  sl.registerLazySingleton<StorageMonitorService>(
    () => StorageMonitorService(),
  );

  sl.registerLazySingleton<AudioRecorderService>(
    () => AudioRecorderService(
      storageMonitor: sl<StorageMonitorService>(),
    ),
  );

  sl.registerLazySingleton<PhotoCaptureService>(
    () => PhotoCaptureService(),
  );

  // === Data Layer ===
  sl.registerLazySingleton<RecordingDao>(
    () => RecordingDao(),
  );

  // === API Client ===
  sl.registerLazySingleton<LectoApiClient>(
    () => LectoApiClient(),
  );
}
