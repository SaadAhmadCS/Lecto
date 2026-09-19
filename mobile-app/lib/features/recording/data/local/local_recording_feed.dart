import 'package:flutter/foundation.dart';

import '../../../../core/constants/notes_source.dart';
import 'recording_dao.dart';

/// Surfaces recordings that live only on this device.
///
/// Home and the transcripts list are backend-driven, but a recording captured
/// in [NotesSource.ownAiApp] never uploads — without this it would be invisible
/// everywhere except the screen you happened to be on when you made it.
///
/// Rows are shaped like the API's so the existing cards and sorting work
/// unchanged.
class LocalRecordingFeed {
  final RecordingDao _dao;

  const LocalRecordingFeed({required RecordingDao dao}) : this._(dao);

  const LocalRecordingFeed._(this._dao);

  /// On-device recordings, newest first, in API row shape.
  ///
  /// [subjectsById] supplies subject names, which the local tables do not hold.
  Future<List<Map<String, dynamic>>> list({
    String? subjectId,
    Map<String, Map<String, dynamic>> subjectsById = const {},
  }) async {
    try {
      final rows = await _dao.listRecordings(subjectId: subjectId);
      final local = <Map<String, dynamic>>[];

      for (final row in rows) {
        final source =
            NotesSource.fromCode(row['capture_notes_source'] as String?);
        if (source.uploadsAudio) continue; // the backend already lists these

        final id = row['id'] as String;
        final hasNotes = (row['notes_markdown'] as String?)?.isNotEmpty ?? false;
        final rowSubjectId = row['subject_id'] as String?;

        local.add({
          'id': id,
          'title': row['title'] as String? ?? 'Untitled',
          'processingStatus': hasNotes ? 'completed' : 'awaiting_paste',
          'createdAt': row['created_at'] as String?,
          'totalDurationMs': row['total_duration_ms'] as int? ?? 0,
          '_count': {'chunks': (await _dao.getChunks(id)).length},
          'subject': rowSubjectId == null ? null : subjectsById[rowSubjectId],
          // Lets callers tell these apart without re-reading the database.
          'isLocalOnly': true,
        });
      }

      return local;
    } catch (e) {
      // A list that is missing local rows is better than one that fails to load.
      debugPrint('LocalRecordingFeed: failed to read local recordings: $e');
      return const [];
    }
  }

  /// How many on-device recordings each subject holds, keyed by subject id.
  ///
  /// The subjects grid takes its counts from the backend, which has never seen
  /// these, so a subject full of them would otherwise read "0 recordings".
  Future<Map<String, int>> countsBySubject() async {
    try {
      final rows = await _dao.listRecordings();
      final counts = <String, int>{};

      for (final row in rows) {
        final source =
            NotesSource.fromCode(row['capture_notes_source'] as String?);
        if (source.uploadsAudio) continue;

        final subjectId = row['subject_id'] as String?;
        if (subjectId == null) continue;
        counts[subjectId] = (counts[subjectId] ?? 0) + 1;
      }

      return counts;
    } catch (e) {
      debugPrint('LocalRecordingFeed: failed to count local recordings: $e');
      return const {};
    }
  }

  /// Add on-device counts into subject rows fetched from the backend.
  ///
  /// Returns new rows; the input list is left untouched.
  static List<Map<String, dynamic>> withLocalCounts(
    List<Map<String, dynamic>> subjects,
    Map<String, int> localCounts,
  ) {
    if (localCounts.isEmpty) return subjects;

    return subjects.map((subject) {
      final extra = localCounts[subject['id'] as String?] ?? 0;
      if (extra == 0) return subject;

      final counts = subject['_count'] as Map<String, dynamic>?;
      final remote = counts?['recordings'] as int? ?? 0;

      return {
        ...subject,
        '_count': {...?counts, 'recordings': remote + extra},
      };
    }).toList();
  }

  /// Merge on-device recordings into a list fetched from the backend.
  ///
  /// Backend rows win on ID collision, which can only happen if a recording was
  /// later uploaded.
  static List<Map<String, dynamic>> merge(
    List<Map<String, dynamic>> remote,
    List<Map<String, dynamic>> local,
  ) {
    final seen = remote.map((row) => row['id'] as String?).toSet();
    return [
      ...remote,
      ...local.where((row) => !seen.contains(row['id'] as String?)),
    ];
  }
}
