// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/network/upload_queue_service.dart';
import '../../../../core/permissions/permission_service.dart';
import '../../data/local/recording_dao.dart';
import '../../data/services/audio_recorder_service.dart';
import '../../data/services/photo_capture_service.dart';
import '../../data/services/storage_monitor_service.dart';
import 'recording_event.dart';
import 'recording_state.dart';

/// Recording BLoC — orchestrates the full recording experience.
///
/// Coordinates between:
/// - [AudioRecorderService] for actual audio capture
/// - [StorageMonitorService] for storage tracking
/// - [PhotoCaptureService] for board/formula photos
/// - [PermissionService] for runtime permissions
/// - [RecordingDao] for local persistence (crash recovery)
/// - [UploadQueueService] for offline-first chunk uploads
class RecordingBloc extends Bloc<RecordingBlocEvent, RecordingBlocState> {
  final AudioRecorderService _recorderService;
  final StorageMonitorService _storageMonitor;
  final PhotoCaptureService _photoService;
  final PermissionService _permissionService;
  final RecordingDao _recordingDao;
  final UploadQueueService _uploadQueue;
  final Uuid _uuid = const Uuid();

  StreamSubscription<RecordingEvent>? _recorderSub;
  StreamSubscription<StorageStatus>? _storageSub;

  // Track state for rebuilding after internal events
  int _completedChunks = 0;
  String _currentTitle = '';

  RecordingBloc({
    required AudioRecorderService recorderService,
    required StorageMonitorService storageMonitor,
    required PhotoCaptureService photoService,
    required PermissionService permissionService,
    required RecordingDao recordingDao,
    required UploadQueueService uploadQueue,
  })  : _recorderService = recorderService,
        _storageMonitor = storageMonitor,
        _photoService = photoService,
        _permissionService = permissionService,
        _recordingDao = recordingDao,
        _uploadQueue = uploadQueue,
        super(const RecordingIdle()) {
    on<StartRecordingEvent>(_onStartRecording);
    on<PauseRecordingEvent>(_onPauseRecording);
    on<ResumeRecordingEvent>(_onResumeRecording);
    on<StopRecordingEvent>(_onStopRecording);
    on<CapturePhotoEvent>(_onCapturePhoto);
    on<AmplitudeUpdatedEvent>(_onAmplitudeUpdated);
    on<DurationTickEvent>(_onDurationTick);
    on<ChunkCompletedBlocEvent>(_onChunkCompleted);
    on<StorageStatusChangedEvent>(_onStorageStatusChanged);
    on<RecordingErrorOccurredEvent>(_onError);
  }

  Future<void> _onStartRecording(
    StartRecordingEvent event,
    Emitter<RecordingBlocState> emit,
  ) async {
    // Request permissions first
    emit(const RecordingRequestingPermissions());

    final hasMic = await _permissionService.requestMicrophone();
    if (!hasMic) {
      emit(const RecordingError(
        message: 'Microphone permission is required to record lectures.',
        canRetry: true,
      ));
      return;
    }

    // Generate recording ID and title
    final recordingId = _uuid.v4();
    _currentTitle = event.title ??
        'Recording ${DateTime.now().day}/${DateTime.now().month} '
            '${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}';

    // Reset state
    _completedChunks = 0;
    _photoService.reset();

    // Persist recording to local DB (crash recovery)
    try {
      await _recordingDao.insertRecording(
        id: recordingId,
        subjectId: event.subjectId,
        title: _currentTitle,
      );
    } catch (e) {
      debugPrint('RecordingBloc: Failed to persist recording locally: $e');
    }

    // Listen to recorder events
    _recorderSub?.cancel();
    _recorderSub = _recorderService.events.listen(_handleRecorderEvent);

    // Listen to storage events
    _storageSub?.cancel();
    _storageMonitor.startMonitoring();
    _storageSub = _storageMonitor.statusStream.listen((status) {
      add(StorageStatusChangedEvent(
        availableMB: status.availableMB,
        isLow: status.isLow,
      ));
    });

    // Start recording
    try {
      await _recorderService.startRecording(recordingId);

      emit(RecordingInProgress(recordingId: recordingId));
    } catch (e) {
      emit(RecordingError(
        message: 'Failed to start recording: $e',
        canRetry: true,
      ));
    }
  }

  Future<void> _onPauseRecording(
    PauseRecordingEvent event,
    Emitter<RecordingBlocState> emit,
  ) async {
    if (state is! RecordingInProgress) return;
    final current = state as RecordingInProgress;

    await _recorderService.pauseRecording();

    emit(RecordingPaused(
      recordingId: current.recordingId,
      totalDuration: current.totalDuration,
      completedChunks: _completedChunks,
      photos: current.photos,
      availableStorageMB: current.availableStorageMB,
    ));
  }

  Future<void> _onResumeRecording(
    ResumeRecordingEvent event,
    Emitter<RecordingBlocState> emit,
  ) async {
    if (state is! RecordingPaused) return;
    final current = state as RecordingPaused;

    await _recorderService.resumeRecording();

    emit(RecordingInProgress(
      recordingId: current.recordingId,
      totalDuration: current.totalDuration,
      completedChunks: current.completedChunks,
      photos: current.photos,
      availableStorageMB: current.availableStorageMB,
    ));
  }

  Future<void> _onStopRecording(
    StopRecordingEvent event,
    Emitter<RecordingBlocState> emit,
  ) async {
    final recordingId = _getCurrentRecordingId();
    if (recordingId == null) return;

    final result = await _recorderService.stopRecording();
    _storageMonitor.stopMonitoring();
    _recorderSub?.cancel();
    _storageSub?.cancel();

    if (result != null) {
      // Update local DB with final status
      try {
        await _recordingDao.updateRecording(
          id: result.recordingId,
          status: 'completed',
          totalDurationMs: result.totalDuration.inMilliseconds,
        );
      } catch (e) {
        debugPrint('RecordingBloc: Failed to update recording in DB: $e');
      }

      emit(RecordingCompleted(
        recordingId: result.recordingId,
        totalDuration: result.totalDuration,
        totalChunks: result.totalChunks,
        totalPhotos: _photoService.photos.length,
        recordingPath: result.recordingPath,
      ));
    } else {
      emit(const RecordingIdle());
    }
  }

  Future<void> _onCapturePhoto(
    CapturePhotoEvent event,
    Emitter<RecordingBlocState> emit,
  ) async {
    if (state is! RecordingInProgress) return;
    final current = state as RecordingInProgress;

    try {
      final photo = await _photoService.registerPhoto(
        sourceFilePath: event.photoFilePath,
        recordingId: current.recordingId,
        timestampInRecording: current.totalDuration,
        currentChunkIndex: current.chunkIndex,
      );

      // Persist photo to local DB
      try {
        await _recordingDao.insertPhoto(
          id: photo.id,
          recordingId: photo.recordingId,
          chunkIndex: photo.chunkIndex,
          filePath: photo.filePath,
          timestampMs: photo.timestampMs,
          sizeBytes: photo.sizeBytes,
        );
      } catch (e) {
        debugPrint('RecordingBloc: Failed to persist photo: $e');
      }

      // Enqueue for upload
      _uploadQueue.enqueuePhoto(
        recordingId: photo.recordingId,
        photoFilePath: photo.filePath,
        photoId: photo.id,
        timestampMs: photo.timestampMs,
        chunkIndex: photo.chunkIndex,
      );

      emit(current.copyWith(
        photos: [...current.photos, photo],
      ));
    } catch (e) {
      // Don't interrupt recording for a photo error
      debugPrint('RecordingBloc: Photo capture error: $e');
    }
  }

  void _onAmplitudeUpdated(
    AmplitudeUpdatedEvent event,
    Emitter<RecordingBlocState> emit,
  ) {
    if (state is! RecordingInProgress) return;
    final current = state as RecordingInProgress;
    emit(current.copyWith(amplitude: event.amplitude));
  }

  void _onDurationTick(
    DurationTickEvent event,
    Emitter<RecordingBlocState> emit,
  ) {
    if (state is! RecordingInProgress) return;
    final current = state as RecordingInProgress;
    emit(current.copyWith(
      totalDuration: event.totalDuration,
      chunkDuration: event.chunkDuration,
      chunkIndex: event.chunkIndex,
    ));
  }

  void _onChunkCompleted(
    ChunkCompletedBlocEvent event,
    Emitter<RecordingBlocState> emit,
  ) {
    _completedChunks++;
    if (state is! RecordingInProgress) return;
    final current = state as RecordingInProgress;

    final chunkId = _uuid.v4();

    // Persist chunk to local DB
    _recordingDao
        .insertChunk(
          id: chunkId,
          recordingId: current.recordingId,
          sequenceNumber: event.chunkIndex,
          filePath: event.filePath,
          durationMs: 0, // Will be calculated from chunk rotation timing
          sizeBytes: event.sizeBytes,
        )
        .catchError((e) {
      debugPrint('RecordingBloc: Failed to persist chunk: $e');
    });

    // Enqueue for upload
    _uploadQueue.enqueueChunk(
      recordingId: current.recordingId,
      chunkFilePath: event.filePath,
      sequenceNumber: event.chunkIndex,
      durationMs: 0,
      sizeBytes: event.sizeBytes,
    );

    emit(current.copyWith(completedChunks: _completedChunks));
  }

  void _onStorageStatusChanged(
    StorageStatusChangedEvent event,
    Emitter<RecordingBlocState> emit,
  ) {
    if (state is! RecordingInProgress) return;
    final current = state as RecordingInProgress;
    emit(current.copyWith(
      availableStorageMB: event.availableMB,
      isStorageLow: event.isLow,
    ));
  }

  void _onError(
    RecordingErrorOccurredEvent event,
    Emitter<RecordingBlocState> emit,
  ) {
    emit(RecordingError(message: event.message));
  }

  /// Route recorder events to BLoC events.
  void _handleRecorderEvent(RecordingEvent event) {
    switch (event) {
      case AmplitudeEvent(:final normalizedAmplitude):
        add(AmplitudeUpdatedEvent(normalizedAmplitude));
      case DurationUpdateEvent(
          :final totalDuration,
          :final chunkDuration,
          :final chunkIndex
        ):
        add(DurationTickEvent(
          totalDuration: totalDuration,
          chunkDuration: chunkDuration,
          chunkIndex: chunkIndex,
        ));
      case ChunkCompletedEvent(
          :final chunkIndex,
          :final filePath,
          :final sizeBytes
        ):
        add(ChunkCompletedBlocEvent(
          chunkIndex: chunkIndex,
          filePath: filePath,
          sizeBytes: sizeBytes,
        ));
      case RecordingErrorEvent(:final message):
        add(RecordingErrorOccurredEvent(message));
      case RecordingStartedEvent():
      case RecordingStoppedEvent():
      case RecordingPausedEvent():
      case RecordingResumedEvent():
      case ChunkDurationAdjustedEvent():
        break;
    }
  }

  String? _getCurrentRecordingId() {
    if (state is RecordingInProgress) {
      return (state as RecordingInProgress).recordingId;
    }
    if (state is RecordingPaused) {
      return (state as RecordingPaused).recordingId;
    }
    return null;
  }

  @override
  Future<void> close() async {
    _recorderSub?.cancel();
    _storageSub?.cancel();
    _storageMonitor.stopMonitoring();
    return super.close();
  }
}
