import 'package:shared_preferences/shared_preferences.dart';

/// Where a recording's notes come from.
///
/// [lectoAi] is the default: audio uploads to the backend, which transcribes
/// with Whisper and writes the notes.
///
/// [ownAiApp] never uploads. The audio stays on the device and the student
/// shares it into their own AI app (Claude, Gemini, Grok), then pastes the
/// reply back. Free for them, and nothing reaches our servers — but there is
/// no Whisper transcript, so the prompt asks the AI for one alongside the
/// notes.
enum NotesSource {
  lectoAi(
    'lecto_ai',
    'Lecto AI',
    'Notes are generated automatically after each recording',
  ),
  ownAiApp(
    'own_ai_app',
    'My own AI app',
    'Share the audio to Claude, Gemini or Grok and paste the reply back',
  );

  const NotesSource(this.code, this.label, this.description);

  final String code;
  final String label;
  final String description;

  /// True when recordings in this mode must not leave the device.
  bool get uploadsAudio => this == NotesSource.lectoAi;

  static const _prefKey = 'notesSource';

  static NotesSource fromCode(String? code) => values.firstWhere(
        (source) => source.code == code,
        orElse: () => NotesSource.lectoAi,
      );

  static Future<NotesSource> load() async {
    final prefs = await SharedPreferences.getInstance();
    return fromCode(prefs.getString(_prefKey));
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, code);
  }
}
