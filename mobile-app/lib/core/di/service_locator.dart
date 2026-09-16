import 'package:get_it/get_it.dart';

import '../network/api_client.dart';
import '../services/auth_service.dart';
import '../network/connectivity_service.dart';
import '../network/upload_queue_service.dart';
import '../permissions/permission_service.dart';
import '../../features/recording/data/local/recording_dao.dart';
import '../../features/recording/data/local/sqlite_upload_task_store.dart';
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

  // === Auth & API Client ===
  sl.registerLazySingleton<AuthService>(() => AuthService());

  sl.registerLazySingleton<LectoApiClient>(
    () => LectoApiClient(tokenProvider: () => sl<AuthService>().getIdToken()),
  );

  // === Upload Queue ===
  // Created eagerly so tasks persisted before an app kill resume at launch.
  final uploadQueue = UploadQueueService(
    connectivity: sl<ConnectivityService>(),
    apiClient: sl<LectoApiClient>(),
    store: SqliteUploadTaskStore(),
  );
  await uploadQueue.initialize();
  sl.registerSingleton<UploadQueueService>(uploadQueue);

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
}
