import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Shares a recording's audio into whichever AI app the student uses.
///
/// Android drops `EXTRA_TEXT` when a file is attached in most receiving apps,
/// so the prompt travels as its own `prompt.txt` file alongside the audio.
/// Multi-file shares of mixed types are handled by the system share sheet, and
/// Claude, Gemini and Grok all accept `.m4a`. ChatGPT accepts no audio at all —
/// [audioCapableApps] documents that for the UI.
class AiShareService {
  /// Apps known to accept shared audio. ChatGPT is deliberately absent: it
  /// registers for PDF and text only, so audio silently goes nowhere.
  static const List<String> audioCapableApps = ['Claude', 'Gemini', 'Grok'];

  /// Marker headings the reply must use so [parseAiReply] can find each part.
  static const String summaryHeading = '## Summary';
  static const String conceptsHeading = '## Key Concepts';
  static const String tasksHeading = '## Tasks';
  static const String deadlinesHeading = '## Deadlines';
  static const String transcriptHeading = '## Transcript';

  /// Build the instruction file that rides along with the audio.
  ///
  /// The output contract is strict because Lecto parses the reply back into
  /// real UI — tickable checkboxes and a deadlines section — rather than
  /// dumping it on screen as plain text.
  static String buildPrompt({
    required String title,
    String? subjectName,
    DateTime? recordingDate,
    Duration? duration,
    bool askForTranscript = true,
  }) {
    final buffer = StringBuffer()
      ..writeln('You are helping a student turn a lecture recording into '
          'study notes.')
      ..writeln()
      ..writeln('Attached is the audio of a lecture'
          '${subjectName != null ? ' for $subjectName' : ''}, titled '
          '"$title".');

    if (recordingDate != null) {
      buffer.writeln('It was recorded on ${_formatDate(recordingDate)}. '
          'Use that date to resolve any relative dates mentioned in the '
          'lecture, such as "next Tuesday".');
    }
    if (duration != null) {
      buffer.writeln('It runs for about ${_formatDuration(duration)}.');
    }

    buffer
      ..writeln()
      ..writeln('If the audio arrives as several files, they are consecutive '
          'parts of one lecture, in filename order. Treat them as a single '
          'continuous recording.')
      ..writeln()
      ..writeln('Listen to it and reply using EXACTLY the headings below, in '
          'this order. Do not add any other top-level headings, and do not '
          'write anything before the first heading.')
      ..writeln()
      ..writeln(summaryHeading)
      ..writeln('A short paragraph covering what the lecture was about.')
      ..writeln()
      ..writeln(conceptsHeading)
      ..writeln('- **Term** — what it means, as explained in the lecture.')
      ..writeln('- One bullet per concept. Use the lecturer\'s own '
          'definitions; do not add material that was not said.')
      ..writeln()
      ..writeln(tasksHeading)
      ..writeln('- [ ] One line per piece of work the students were asked to '
          'do.')
      ..writeln('- [ ] Leave every box unticked. Omit this section entirely if '
          'nothing was assigned.')
      ..writeln()
      ..writeln(deadlinesHeading)
      ..writeln('- YYYY-MM-DD — what is due. One line each, resolved to a real '
          'date. Omit this section if no dates were mentioned.');

    if (askForTranscript) {
      buffer
        ..writeln()
        ..writeln(transcriptHeading)
        ..writeln('The full transcript of the lecture, in paragraphs. If the '
            'lecture is too long to transcribe in full, write '
            '"(too long to transcribe)" here instead and keep the sections '
            'above complete — those matter more.');
    }

    buffer
      ..writeln()
      ..writeln('Ground everything in what was actually said. If something was '
          'inaudible, say so rather than guessing.')
      ..writeln()
      ..writeln('When you are done, the student will copy your whole reply and '
          'paste it back into their notes app, so reply with the notes only — '
          'no preamble, no closing remarks.');

    return buffer.toString();
  }

  /// Write the prompt to a file that can ride along in the share sheet.
  static Future<File> writePromptFile(String prompt) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/lecto_prompt.txt');
    await file.writeAsString(prompt);
    return file;
  }

  /// Open the system share sheet with the audio and the prompt.
  ///
  /// [audioPaths] should be in playback order; filenames carry that order to
  /// the AI app. Returns false when nothing could be shared.
  static Future<bool> shareToAiApp({
    required List<String> audioPaths,
    required String prompt,
    String? subjectLabel,
  }) async {
    final existing = <XFile>[];
    for (final path in audioPaths) {
      if (await File(path).exists()) {
        existing.add(XFile(path, mimeType: 'audio/mp4'));
      } else {
        debugPrint('AiShareService: missing audio chunk $path');
      }
    }

    if (existing.isEmpty) return false;

    final promptFile = await writePromptFile(prompt);
    existing.add(XFile(promptFile.path, mimeType: 'text/plain'));

    await SharePlus.instance.share(
      ShareParams(
        files: existing,
        // Some apps surface this as the chat's first message; harmless when
        // ignored, and the prompt file carries the real instructions.
        text: prompt,
        subject: subjectLabel ?? 'Lecture recording',
      ),
    );
    return true;
  }

  static String _formatDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0) return '$hours hr $minutes min';
    return '$minutes min';
  }
}
