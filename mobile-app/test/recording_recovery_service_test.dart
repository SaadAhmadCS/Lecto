import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lecto/core/network/upload_queue_service.dart';
import 'package:lecto/features/recording/data/local/recording_dao.dart';
import 'package:lecto/features/recording/data/services/recording_recovery_service.dart';

import 'fakes.dart';

/// In-memory stand-in for the recordings/audio_chunks tables.
class FakeRecordingDao extends RecordingDao {
  final Map<String, Map<String, dynamic>> recordings = {};
  final Map<String, List<Map<String, dynamic>>> chunks = {};

  @override
  Future<List<Map<String, dynamic>>> listRecordings({
    String? subjectId,
    String? status,
  }) async =>
      recordings.values.where((r) => status == null || r['status'] == status).toList();

  @override
  Future<List<Map<String, dynamic>>> getChunks(String recordingId) async =>
      chunks[recordingId] ?? [];

  @override
  Future<void> updateRecording({
    required String id,
    String? status,
    int? totalDurationMs,
    bool? synced,
  }) async {
    final row = recordings[id]!;
    if (status != null) row['status'] = status;
    if (totalDurationMs != null) row['total_duration_ms'] = totalDurationMs;
  }

  @override
  Future<void> deleteRecording(String id) async {
    recordings.remove(id);
    chunks.remove(id);
  }
}

void main() {
  late Directory root;
  late FakeRecordingDao dao;
  late FakeConnectivity connectivity;
  late FakeApiClient api;
  late UploadQueueService queue;
  late RecordingRecoveryService recovery;

  Directory dirFor(String id) => Directory('${root.path}/$id');

  Future<String> writeChunk(String id, int seq) async {
    final file = File('${dirFor(id).path}/chunk_${seq.toString().padLeft(3, '0')}.m4a');
    await file.create(recursive: true);
    await file.writeAsString('audio');
    return file.path;
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lecto_recovery_test');
    dao = FakeRecordingDao();
    connectivity = FakeConnectivity(online: false);
    api = FakeApiClient();
    queue = UploadQueueService(
      connectivity: connectivity,
      apiClient: api,
      store: InMemoryUploadTaskStore(),
    );
    await queue.initialize();
    recovery = RecordingRecoveryService(
      dao: dao,
      uploadQueue: queue,
      recordingDir: (id) async => dirFor(id),
    );
  });

  tearDown(() => root.delete(recursive: true));

  test('killed mid-recording: finished chunks are completed, the unfinished one discarded',
      () async {
    dao.recordings['rec-1'] = {'id': 'rec-1', 'title': 'Physics', 'status': 'recording'};
    // Chunk 0 finished and was saved; chunk 1 was being written when the app died
    final chunk0 = await writeChunk('rec-1', 0);
    final partial = await writeChunk('rec-1', 1);
    dao.chunks['rec-1'] = [
      {'sequence_number': 0, 'file_path': chunk0, 'duration_ms': 900000},
    ];
    // Last run's queue, restored at launch
    queue.enqueueCreateRecording(recordingId: 'rec-1', subjectId: 'unsorted', title: 'Physics');
    queue.enqueueChunk(
      recordingId: 'rec-1',
      chunkFilePath: chunk0,
      sequenceNumber: 0,
      durationMs: 900000,
      sizeBytes: 5,
    );

    final recovered = await recovery.recoverInterrupted();

    expect(recovered, hasLength(1));
    expect(recovered.single.duration, const Duration(minutes: 15));
    expect(recovered.single.lostEnd, isTrue);
    expect(dao.recordings['rec-1']!['status'], 'completed');
    expect(await File(chunk0).exists(), isTrue);
    expect(await File(partial).exists(), isFalse);

    connectivity.setOnline(true);
    await waitFor(() => queue.pendingCount == 0);
    expect(api.calls, ['create:unsorted', 'chunk:0', 'complete']);
  });

  test('a chunk queued but not yet in the local DB is kept', () async {
    dao.recordings['rec-1'] = {'id': 'rec-1', 'title': 'Maths', 'status': 'recording'};
    final chunk0 = await writeChunk('rec-1', 0);
    queue.enqueueChunk(
      recordingId: 'rec-1',
      chunkFilePath: chunk0,
      sequenceNumber: 0,
      durationMs: 60000,
      sizeBytes: 5,
    );

    final recovered = await recovery.recoverInterrupted();

    expect(recovered.single.duration, const Duration(minutes: 1));
    expect(recovered.single.lostEnd, isFalse);
    expect(await File(chunk0).exists(), isTrue);
  });

  test('killed before any chunk finished: the recording is discarded everywhere', () async {
    dao.recordings['rec-1'] = {'id': 'rec-1', 'title': 'Chemistry', 'status': 'recording'};
    await writeChunk('rec-1', 0); // unfinished
    queue.enqueueCreateRecording(recordingId: 'rec-1', subjectId: 'unsorted', title: 'Chemistry');

    final recovered = await recovery.recoverInterrupted();

    expect(recovered, isEmpty);
    expect(dao.recordings, isEmpty);
    expect(await dirFor('rec-1').exists(), isFalse);

    connectivity.setOnline(true);
    await waitFor(() => queue.pendingCount == 0);
    // Created then removed; the 404-tolerant delete doesn't get stuck retrying
    expect(api.calls, ['create:unsorted', 'delete']);
    expect(queue.failedCount, 0);
  });

  test('finished recordings are left alone', () async {
    dao.recordings['rec-1'] = {'id': 'rec-1', 'title': 'History', 'status': 'completed'};

    expect(await recovery.recoverInterrupted(), isEmpty);
    expect(dao.recordings['rec-1']!['status'], 'completed');
  });

  group('my own AI app mode', () {
    test('a recovered recording is never queued for upload', () async {
      dao.recordings['rec-1'] = {
        'id': 'rec-1',
        'title': 'Physics',
        'status': 'recording',
        'capture_notes_source': 'own_ai_app',
      };
      final chunk0 = await writeChunk('rec-1', 0);
      dao.chunks['rec-1'] = [
        {'sequence_number': 0, 'file_path': chunk0, 'duration_ms': 900000},
      ];

      final recovered = await recovery.recoverInterrupted();

      // Still recovered and playable, just never sent anywhere.
      expect(recovered, hasLength(1));
      expect(dao.recordings['rec-1']!['status'], 'completed');
      expect(await File(chunk0).exists(), isTrue);

      connectivity.setOnline(true);
      await waitFor(() => queue.pendingCount == 0);
      expect(api.calls, isEmpty);
    });

    test('a recording with no usable audio is dropped without calling the '
        'backend', () async {
      dao.recordings['rec-1'] = {
        'id': 'rec-1',
        'title': 'Physics',
        'status': 'recording',
        'capture_notes_source': 'own_ai_app',
      };

      expect(await recovery.recoverInterrupted(), isEmpty);
      expect(dao.recordings.containsKey('rec-1'), isFalse);

      connectivity.setOnline(true);
      await waitFor(() => queue.pendingCount == 0);
      // No backend row was ever created, so there is nothing to delete.
      expect(api.calls, isEmpty);
    });
  });
}
