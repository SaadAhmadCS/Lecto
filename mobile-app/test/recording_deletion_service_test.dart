import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lecto/core/network/api_client.dart';
import 'package:lecto/features/recording/data/local/recording_dao.dart';
import 'package:lecto/features/recording/data/services/recording_deletion_service.dart';

/// Records what the backend was asked to delete, and can fail on demand.
class _FakeApi implements LectoApiClient {
  final List<String> deleted = [];
  ApiException? throwOnDelete;

  @override
  Future<void> deleteRecording(String id) async {
    final failure = throwOnDelete;
    if (failure != null) throw failure;
    deleted.add(id);
  }

  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// In-memory stand-in for the recordings/photos tables.
class _FakeDao extends RecordingDao {
  final List<String> deleted = [];
  final Map<String, List<Map<String, dynamic>>> photos = {};

  @override
  Future<void> deleteRecording(String id) async => deleted.add(id);

  @override
  Future<List<Map<String, dynamic>>> getPhotos(String recordingId) async =>
      photos[recordingId] ?? [];
}

void main() {
  late Directory root;
  late _FakeApi api;
  late _FakeDao dao;
  late RecordingDeletionService deleter;

  Directory dirFor(String id) => Directory('${root.path}/$id');

  Future<File> writeChunk(String id, int seq) async {
    final file = File('${dirFor(id).path}/chunk_00$seq.m4a');
    await file.create(recursive: true);
    await file.writeAsString('audio');
    return file;
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lecto_delete_test');
    api = _FakeApi();
    dao = _FakeDao();
    deleter = RecordingDeletionService(
      api: api,
      dao: dao,
      recordingDir: (id) async => dirFor(id),
    );
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('removes the backend row, the local rows and the audio', () async {
    final chunk = await writeChunk('rec-1', 0);

    await deleter.delete('rec-1');

    expect(api.deleted, ['rec-1']);
    expect(dao.deleted, ['rec-1']);
    // The whole point: audio used to survive every delete.
    expect(await chunk.exists(), isFalse);
    expect(await dirFor('rec-1').exists(), isFalse);
  });

  test('a local-only recording never calls the backend', () async {
    // It has no backend row, so asking would 404 and the delete would fail.
    final chunk = await writeChunk('rec-1', 0);

    await deleter.delete('rec-1', localOnly: true);

    expect(api.deleted, isEmpty);
    expect(dao.deleted, ['rec-1']);
    expect(await chunk.exists(), isFalse);
  });

  test('a 404 still cleans up locally', () async {
    // Already deleted on the backend: refusing to clean up would strand the
    // audio on the device with no way to remove it.
    api.throwOnDelete = const ApiException(statusCode: 404, code: 'NOT_FOUND', message: 'Not found');
    final chunk = await writeChunk('rec-1', 0);

    await deleter.delete('rec-1');

    expect(dao.deleted, ['rec-1']);
    expect(await chunk.exists(), isFalse);
  });

  test('a real backend failure leaves everything intact', () async {
    // Aborting before local deletion means a failed delete can be retried
    // rather than leaving a recording half gone.
    api.throwOnDelete = const ApiException(statusCode: 500, code: 'SERVER_ERROR', message: 'Server error');
    final chunk = await writeChunk('rec-1', 0);

    await expectLater(deleter.delete('rec-1'), throwsA(isA<ApiException>()));

    expect(dao.deleted, isEmpty);
    expect(await chunk.exists(), isTrue);
  });

  test('deletes captured photos too', () async {
    final photo = File('${root.path}/photo.jpg');
    await photo.create(recursive: true);
    await photo.writeAsString('image');
    dao.photos['rec-1'] = [
      {'file_path': photo.path},
    ];

    await deleter.delete('rec-1');

    expect(await photo.exists(), isFalse);
  });

  test('a recording whose audio is already gone still deletes', () async {
    // Nothing on disk — the rows must still go, or the entry is undeletable.
    await deleter.delete('rec-1');

    expect(dao.deleted, ['rec-1']);
  });

  test('leaves other recordings alone', () async {
    final mine = await writeChunk('rec-1', 0);
    final theirs = await writeChunk('rec-2', 0);

    await deleter.delete('rec-1');

    expect(await mine.exists(), isFalse);
    expect(await theirs.exists(), isTrue);
  });
}
