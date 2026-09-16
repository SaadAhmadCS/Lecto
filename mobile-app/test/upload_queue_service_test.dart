import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lecto/core/network/api_client.dart';
import 'package:lecto/core/network/connectivity_service.dart';
import 'package:lecto/core/network/upload_queue_service.dart';
import 'package:lecto/core/network/upload_task_store.dart';

class InMemoryUploadTaskStore implements UploadTaskStore {
  final Map<String, UploadTask> _tasks = {};

  @override
  Future<List<UploadTask>> loadAll() async => _tasks.values
      .map((t) => UploadTask(
            id: t.id,
            type: t.type,
            recordingId: t.recordingId,
            filePath: t.filePath,
            metadata: t.metadata,
            status: t.status,
            attempts: t.attempts,
            createdAt: t.createdAt,
          ))
      .toList();

  @override
  Future<void> save(UploadTask task) async => _tasks.putIfAbsent(task.id, () => task);

  @override
  Future<void> update(UploadTask task) async => _tasks[task.id] = task;

  @override
  Future<void> delete(String id) async => _tasks.remove(id);

  int get length => _tasks.length;
}

class FakeConnectivity extends ConnectivityService {
  final _changes = StreamController<bool>.broadcast();
  bool online;

  FakeConnectivity({required this.online});

  @override
  bool get isConnected => online;

  @override
  Stream<bool> get onConnectivityChanged => _changes.stream;

  void setOnline(bool value) {
    online = value;
    _changes.add(value);
  }
}

/// Records calls in order; fails the first [failCreateTimes] creates.
class FakeApiClient extends LectoApiClient {
  final List<String> calls = [];
  int failCreateTimes;

  FakeApiClient({this.failCreateTimes = 0});

  @override
  Future<Map<String, dynamic>> createRecording({
    required String id,
    required String subjectId,
    required String title,
  }) async {
    if (failCreateTimes > 0) {
      failCreateTimes--;
      calls.add('create:fail');
      throw const ApiException(statusCode: 503, code: 'DOWN', message: 'down');
    }
    calls.add('create:$subjectId');
    return {};
  }

  @override
  Future<Map<String, dynamic>> uploadChunk({
    required String recordingId,
    required String filePath,
    required int sequenceNumber,
    required int durationMs,
  }) async {
    calls.add('chunk:$sequenceNumber');
    return {};
  }

  @override
  Future<Map<String, dynamic>> completeRecording(
    String recordingId, {
    int totalDurationMs = 0,
  }) async {
    calls.add('complete');
    return {};
  }
}

Future<void> waitFor(bool Function() condition, {int seconds = 10}) async {
  final deadline = DateTime.now().add(Duration(seconds: seconds));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

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
}
