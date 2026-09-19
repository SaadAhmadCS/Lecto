import 'package:flutter_test/flutter_test.dart';
import 'package:lecto/core/services/notes_parser.dart';

void main() {
  const wellFormed = '''
## Summary
Newton's laws of motion, covering inertia and F=ma.

## Key Concepts
- **Inertia** — an object resists changes to its motion.
- **Force** — mass times acceleration.

## Tasks
- [ ] Read chapter 4 before the next class
- [ ] Attempt problems 1 to 10

## Deadlines
- 2026-09-26 — Problem set 3 due
- 2026-10-03 — Midterm exam

## Transcript
Right, so today we are going to talk about Newton's laws.
''';

  group('parse', () {
    test('pulls every section out of a well-formed reply', () {
      final notes = NotesParser.parse(wellFormed);

      expect(notes.isStructured, isTrue);
      expect(notes.summary, contains('Newton'));
      expect(notes.concepts, hasLength(2));
      expect(notes.concepts.first, contains('Inertia'));
      expect(notes.tasks, hasLength(2));
      expect(notes.tasks.every((t) => !t.done), isTrue);
      expect(notes.deadlines, hasLength(2));
      expect(notes.deadlines.first.date, DateTime(2026, 9, 26));
      expect(notes.deadlines.first.description, 'Problem set 3 due');
      expect(notes.hasTranscript, isTrue);
    });

    test('accepts heading synonyms and different heading levels', () {
      final notes = NotesParser.parse('''
# Overview
A lecture about databases.

### Action Items
- [x] Install Postgres

**Due Dates**
- 2026-11-01 — Project proposal
''');

      expect(notes.summary, contains('databases'));
      expect(notes.tasks.single.done, isTrue);
      expect(notes.deadlines.single.description, 'Project proposal');
    });

    test('finds checklist items even with no Tasks heading', () {
      final notes = NotesParser.parse('''
## Summary
Short lecture.

- [ ] Revise slide deck
''');

      expect(notes.tasks.single.text, 'Revise slide deck');
    });

    test('treats an unstructured reply as plain markdown', () {
      final notes = NotesParser.parse(
        'Here are some thoughts about the lecture with no headings at all.',
      );

      expect(notes.isStructured, isFalse);
      expect(notes.rawMarkdown, contains('no headings'));
    });

    test('ignores a transcript the AI declined to produce', () {
      final notes = NotesParser.parse('''
## Summary
A long lecture.

## Transcript
(too long to transcribe)
''');

      expect(notes.hasTranscript, isFalse);
    });

    test('keeps a deadline that has no parseable date', () {
      final notes = NotesParser.parse('''
## Deadlines
- End of term — portfolio submission
''');

      expect(notes.deadlines.single.date, isNull);
      expect(notes.deadlines.single.description, contains('portfolio'));
    });
  });

  group('toggleTask', () {
    test('ticks an unticked item and leaves the rest alone', () {
      final notes = NotesParser.parse(wellFormed);
      final updated = NotesParser.toggleTask(wellFormed, notes.tasks.first);
      final reparsed = NotesParser.parse(updated);

      expect(reparsed.tasks.first.done, isTrue);
      expect(reparsed.tasks.last.done, isFalse);
      expect(reparsed.summary, contains('Newton'));
      expect(reparsed.deadlines, hasLength(2));
    });

    test('unticks a ticked item', () {
      const markdown = '## Tasks\n- [x] Already done';
      final notes = NotesParser.parse(markdown);
      final updated = NotesParser.toggleTask(markdown, notes.tasks.single);

      expect(NotesParser.parse(updated).tasks.single.done, isFalse);
    });

    test('survives a stale line index', () {
      final notes = NotesParser.parse(wellFormed);
      final updated = NotesParser.toggleTask('## Tasks\n', notes.tasks.first);

      expect(updated, '## Tasks\n');
    });
  });
}
