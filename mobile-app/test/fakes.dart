import 'dart:async';

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

  @override
  Future<void> deleteAll() async => _tasks.clear();

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
    String? language,
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

  @override
  Future<void> deleteRecording(String id) async {
    calls.add('delete');
    // Recordings that never reached the backend 404
    throw const ApiException(statusCode: 404, code: 'NOT_FOUND', message: 'not found');
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

