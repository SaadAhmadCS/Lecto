import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lecto/core/network/upload_queue_service.dart';

import 'fakes.dart';

void main() {
  late Directory tempDir;
  late String chunkPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lecto_queue_test');
    chunkPath = '${tempDir.path}/chunk_000.m4a';
    await File(chunkPath).writeAsString('audio');
  });

  tearDown(() => tempDir.delete(recursive: true));

  void enqueueRecording(UploadQueueService queue) {
    queue.enqueueCreateRecording(
      recordingId: 'rec-1',
      subjectId: 'unsorted',
      title: 'Lecture',
    );
    for (var i = 0; i < 2; i++) {
      queue.enqueueChunk(
        recordingId: 'rec-1',
        chunkFilePath: chunkPath,
        sequenceNumber: i,
        durationMs: 1000,
        sizeBytes: 5,
      );
    }
    queue.enqueueCompleteRecording(recordingId: 'rec-1', totalDurationMs: 2000);
  }

  test('recording made offline syncs in order once back online', () async {
    final connectivity = FakeConnectivity(online: false);
    final api = FakeApiClient();
    final queue = UploadQueueService(
      connectivity: connectivity,
      apiClient: api,
      store: InMemoryUploadTaskStore(),
    );
    await queue.initialize();

    enqueueRecording(queue);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(api.calls, isEmpty);
    expect(queue.pendingCount, 4);

    connectivity.setOnline(true);
    await waitFor(() => queue.pendingCount == 0);

    expect(api.calls, ['create:unsorted', 'chunk:0', 'chunk:1', 'complete']);
    expect(queue.failedCount, 0);
  });

  test('a failing task is retried before later tasks run', () async {
    final connectivity = FakeConnectivity(online: true);
    final api = FakeApiClient(failCreateTimes: 1);
    final queue = UploadQueueService(
      connectivity: connectivity,
      apiClient: api,
      store: InMemoryUploadTaskStore(),
    );
    await queue.initialize();

    enqueueRecording(queue);
    await waitFor(() => queue.pendingCount == 0);

    expect(api.calls, [
      'create:fail',
      'create:unsorted',
      'chunk:0',
      'chunk:1',
      'complete',
    ]);
  });

  test('tasks queued before an app kill resume after restart', () async {
    final store = InMemoryUploadTaskStore();

    // First launch: record offline, then the app is killed
    final firstRun = UploadQueueService(
      connectivity: FakeConnectivity(online: false),
      apiClient: FakeApiClient(),
      store: store,
    );
    await firstRun.initialize();
    enqueueRecording(firstRun);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(store.length, 4);

    // Next launch, online: work resumes in the original order
    final api = FakeApiClient();
    final secondRun = UploadQueueService(
      connectivity: FakeConnectivity(online: true),
      apiClient: api,
      store: store,
    );
    await secondRun.initialize();
    await waitFor(() => secondRun.pendingCount == 0);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(api.calls, ['create:unsorted', 'chunk:0', 'chunk:1', 'complete']);
    expect(store.length, 0);
  });

  test('clear (sign-out) drops queued work so it never uploads', () async {
    final store = InMemoryUploadTaskStore();
    final connectivity = FakeConnectivity(online: false);
    final api = FakeApiClient();
    final queue = UploadQueueService(
      connectivity: connectivity,
      apiClient: api,
      store: store,
    );
    await queue.initialize();
    enqueueRecording(queue);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(queue.unsyncedRecordingCount, 1);

    await queue.clear();
    expect(queue.pendingCount, 0);
    expect(queue.unsyncedRecordingCount, 0);
    expect(store.length, 0);

    connectivity.setOnline(true);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(api.calls, isEmpty);
  });
}
