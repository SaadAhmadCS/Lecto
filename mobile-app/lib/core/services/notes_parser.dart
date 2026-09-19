/// One item the students were asked to do.
class NoteTask {
  final String text;
  final bool done;

  /// Line index in the source markdown, so a tap can rewrite the right line.
  final int lineIndex;

  const NoteTask({
    required this.text,
    required this.done,
    required this.lineIndex,
  });
}

/// A dated commitment pulled out of the notes.
class NoteDeadline {
  final DateTime? date;
  final String rawDate;
  final String description;

  const NoteDeadline({
    required this.rawDate,
    required this.description,
    this.date,
  });
}

/// A lecture's notes broken into the parts Lecto renders separately.
///
/// [isStructured] is false when the reply did not follow the prompt's format,
/// in which case the UI falls back to rendering [rawMarkdown] as plain
/// markdown rather than showing empty sections.
class ParsedNotes {
  final String? summary;
  final List<String> concepts;
  final List<NoteTask> tasks;
  final List<NoteDeadline> deadlines;
  final String? transcript;
  final String rawMarkdown;

  const ParsedNotes({
    required this.rawMarkdown,
    this.summary,
    this.concepts = const [],
    this.tasks = const [],
    this.deadlines = const [],
    this.transcript,
  });

  bool get isStructured =>
      summary != null ||
      concepts.isNotEmpty ||
      tasks.isNotEmpty ||
      deadlines.isNotEmpty;

  bool get hasTranscript => transcript != null && transcript!.trim().isNotEmpty;
}

/// Turns an AI reply into [ParsedNotes].
///
/// Deliberately lenient: AI apps improvise with headings, so matching is
/// case-insensitive, tolerates `#`/`##`/`###` and bold headings, and accepts
/// reasonable synonyms. Anything it cannot place is left in [rawMarkdown].
class NotesParser {
  static final RegExp _heading = RegExp(
    r'^\s{0,3}(?:#{1,4}\s+|\*\*)\s*([^*#\n]+?)\s*(?:\*\*)?\s*:?\s*$',
  );
  static final RegExp _task = RegExp(r'^\s*[-*]\s*\[( |x|X)\]\s*(.+)$');
  static final RegExp _bullet = RegExp(r'^\s*[-*]\s+(.+)$');
  static final RegExp _leadingDate = RegExp(
    r'^\s*[-*]?\s*(\d{4}-\d{2}-\d{2}|\d{1,2}[/-]\d{1,2}[/-]\d{2,4})\s*(?:[—–\-:]\s*)?(.*)$',
  );

  static const _summaryNames = {'summary', 'overview', 'tl;dr', 'tldr'};
  static const _conceptNames = {
    'key concepts',
    'concepts',
    'key points',
    'key ideas',
    'main points',
  };
  static const _taskNames = {
    'tasks',
    'action items',
    'to do',
    'todo',
    'homework',
    'assignments',
  };
  static const _deadlineNames = {
    'deadlines',
    'due dates',
    'important dates',
    'dates',
  };
  static const _transcriptNames = {'transcript', 'full transcript'};

  static ParsedNotes parse(String markdown) {
    final lines = markdown.split('\n');

    final summaryLines = <String>[];
    final concepts = <String>[];
    final tasks = <NoteTask>[];
    final deadlines = <NoteDeadline>[];
    final transcriptLines = <String>[];

    var section = _Section.none;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final headingMatch = _heading.firstMatch(line);

      if (headingMatch != null) {
        final name = headingMatch.group(1)!.trim().toLowerCase();
        section = _sectionFor(name);
        continue;
      }

      switch (section) {
        case _Section.summary:
          if (line.trim().isNotEmpty) summaryLines.add(line.trim());
        case _Section.concepts:
          final bullet = _bullet.firstMatch(line);
          if (bullet != null) concepts.add(bullet.group(1)!.trim());
        case _Section.tasks:
          final task = _task.firstMatch(line);
          if (task != null) {
            tasks.add(NoteTask(
              text: task.group(2)!.trim(),
              done: task.group(1)!.toLowerCase() == 'x',
              lineIndex: i,
            ));
          }
        case _Section.deadlines:
          if (line.trim().isEmpty) continue;
          final dated = _leadingDate.firstMatch(line);
          if (dated != null && dated.group(2)!.trim().isNotEmpty) {
            deadlines.add(NoteDeadline(
              rawDate: dated.group(1)!,
              description: dated.group(2)!.trim(),
              date: DateTime.tryParse(dated.group(1)!),
            ));
          } else {
            final bullet = _bullet.firstMatch(line);
            if (bullet != null) {
              deadlines.add(NoteDeadline(
                rawDate: '',
                description: bullet.group(1)!.trim(),
              ));
            }
          }
        case _Section.transcript:
          transcriptLines.add(line);
        case _Section.none:
          break;
      }
    }

    // Checklist items sometimes appear outside a Tasks heading. Pick them up so
    // a reply that skipped the heading still gets tickable boxes.
    if (tasks.isEmpty) {
      for (var i = 0; i < lines.length; i++) {
        final task = _task.firstMatch(lines[i]);
        if (task != null) {
          tasks.add(NoteTask(
            text: task.group(2)!.trim(),
            done: task.group(1)!.toLowerCase() == 'x',
            lineIndex: i,
          ));
        }
      }
    }

    final transcript = transcriptLines.join('\n').trim();

    return ParsedNotes(
      rawMarkdown: markdown,
      summary: summaryLines.isEmpty ? null : summaryLines.join('\n'),
      concepts: concepts,
      tasks: tasks,
      deadlines: deadlines,
      transcript: _isMissingTranscript(transcript) ? null : transcript,
    );
  }

  /// Flip one checklist item and return the rewritten markdown.
  ///
  /// The markdown stays the source of truth, so a toggle survives into PDF
  /// export and search with no extra state to keep in step.
  static String toggleTask(String markdown, NoteTask task) {
    final lines = markdown.split('\n');
    if (task.lineIndex < 0 || task.lineIndex >= lines.length) return markdown;

    final line = lines[task.lineIndex];
    final match = _task.firstMatch(line);
    if (match == null) return markdown;

    final replacement = task.done ? '[ ]' : '[x]';
    lines[task.lineIndex] = line.replaceFirst(
      RegExp(r'\[( |x|X)\]'),
      replacement,
    );
    return lines.join('\n');
  }

  static bool _isMissingTranscript(String transcript) {
    if (transcript.isEmpty) return true;
    final normalized = transcript.toLowerCase();
    return normalized.length < 80 && normalized.contains('too long');
  }

  static _Section _sectionFor(String name) {
    if (_summaryNames.contains(name)) return _Section.summary;
    if (_conceptNames.contains(name)) return _Section.concepts;
    if (_taskNames.contains(name)) return _Section.tasks;
    if (_deadlineNames.contains(name)) return _Section.deadlines;
    if (_transcriptNames.contains(name)) return _Section.transcript;
    return _Section.none;
  }
}

enum _Section { none, summary, concepts, tasks, deadlines, transcript }
