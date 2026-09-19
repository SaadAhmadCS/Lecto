import 'package:flutter_test/flutter_test.dart';
import 'package:lecto/features/recording/data/local/local_recording_feed.dart';

void main() {
  Map<String, dynamic> row(String id, {bool local = false}) => {
        'id': id,
        'title': 'Recording $id',
        if (local) 'isLocalOnly': true,
      };

  group('merge', () {
    test('appends on-device recordings after backend ones', () {
      final merged = LocalRecordingFeed.merge(
        [row('a'), row('b')],
        [row('x', local: true)],
      );

      expect(merged.map((r) => r['id']), ['a', 'b', 'x']);
    });

    test('a recording already on the backend is not duplicated', () {
      // Can happen if a recording was later uploaded: the backend row wins.
      final merged = LocalRecordingFeed.merge(
        [row('a')],
        [row('a', local: true), row('x', local: true)],
      );

      expect(merged.map((r) => r['id']), ['a', 'x']);
      expect(merged.first['isLocalOnly'], isNull);
    });

    test('works with either side empty', () {
      expect(LocalRecordingFeed.merge([], [row('x', local: true)]), hasLength(1));
      expect(LocalRecordingFeed.merge([row('a')], []), hasLength(1));
      expect(LocalRecordingFeed.merge([], []), isEmpty);
    });

    test('leaves the backend list untouched', () {
      final remote = [row('a')];
      LocalRecordingFeed.merge(remote, [row('x', local: true)]);

      expect(remote, hasLength(1));
    });
  });

  group('withLocalCounts', () {
    Map<String, dynamic> subject(String id, int recordings) => {
          'id': id,
          'name': 'Subject $id',
          '_count': {'recordings': recordings},
        };

    test('adds on-device recordings to a subject count', () {
      final result = LocalRecordingFeed.withLocalCounts(
        [subject('s1', 3)],
        {'s1': 2},
      );

      expect(result.single['_count']['recordings'], 5);
    });

    test('leaves subjects with nothing on the device alone', () {
      final result = LocalRecordingFeed.withLocalCounts(
        [subject('s1', 3), subject('s2', 0)],
        {'s1': 1},
      );

      expect(result[0]['_count']['recordings'], 4);
      expect(result[1]['_count']['recordings'], 0);
    });

    test('handles a subject the backend reports no count for', () {
      final result = LocalRecordingFeed.withLocalCounts(
        [
          {'id': 's1', 'name': 'New'},
        ],
        {'s1': 2},
      );

      expect(result.single['_count']['recordings'], 2);
    });

    test('keeps other keys in the count map', () {
      final result = LocalRecordingFeed.withLocalCounts(
        [
          {
            'id': 's1',
            '_count': {'recordings': 1, 'notes': 7},
          },
        ],
        {'s1': 1},
      );

      expect(result.single['_count']['recordings'], 2);
      expect(result.single['_count']['notes'], 7);
    });

    test('does not mutate the input rows', () {
      final subjects = [subject('s1', 3)];
      LocalRecordingFeed.withLocalCounts(subjects, {'s1': 2});

      expect(subjects.single['_count']['recordings'], 3);
    });

    test('no local recordings returns the list as-is', () {
      final subjects = [subject('s1', 3)];
      expect(
        LocalRecordingFeed.withLocalCounts(subjects, const {}),
        same(subjects),
      );
    });
  });
}
