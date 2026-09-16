// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

typedef TokenProvider = Future<String?> Function();

/// API client for the Lecto backend.
///
/// Wraps HTTP calls and provides typed responses for
/// recording status, transcripts, and summaries.
class LectoApiClient {
  /// Override per build: `flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000`
  static const String defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://192.168.100.93:3000', // LAN IP for physical device
  );

  final String baseUrl;
  final http.Client _client;
  final TokenProvider? _tokenProvider;

  LectoApiClient({
    this.baseUrl = defaultBaseUrl,
    TokenProvider? tokenProvider,
  })  : _client = http.Client(),
        _tokenProvider = tokenProvider;

  /// Headers for every request. The token is fetched per request because
  /// Firebase ID tokens expire hourly; getIdToken() refreshes when needed.
  Future<Map<String, String>> _headers({bool json = false}) async {
    final token = await _tokenProvider?.call();
    return {
      if (json) 'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // ─── Processing ────────────────────────────────────────────────

  /// Trigger processing for a recording.
  Future<Map<String, dynamic>> startProcessing(String recordingId) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/v1/recordings/$recordingId/process'),
      headers: await _headers(json: true),
      body: '{}',
    );
    return _decode(response);
  }

  /// Get processing status for a recording.
  Future<Map<String, dynamic>> getProcessingStatus(String recordingId) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/v1/recordings/$recordingId/status'),
      headers: await _headers(),
    );
    return _decode(response);
  }

  /// Get the assembled transcript.
  Future<Map<String, dynamic>?> getTranscript(String recordingId) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/v1/recordings/$recordingId/transcript'),
      headers: await _headers(),
    );
    if (response.statusCode == 404) return null;
    return _decode(response);
  }

  /// Get the AI-generated summary.
  Future<Map<String, dynamic>?> getSummary(String recordingId) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/v1/recordings/$recordingId/summary'),
      headers: await _headers(),
    );
    if (response.statusCode == 404) return null;
    return _decode(response);
  }

  // ─── Recordings ────────────────────────────────────────────────

  /// List all recordings.
  Future<Map<String, dynamic>> listRecordings({
    String? subjectId,
    int page = 1,
    int limit = 20,
  }) async {
    final params = <String, String>{
      'page': '$page',
      'limit': '$limit',
    };
    if (subjectId != null) params['subjectId'] = subjectId;

    final response = await _client.get(
      Uri.parse('$baseUrl/api/v1/recordings').replace(queryParameters: params),
      headers: await _headers(),
    );
    return _decode(response);
  }

  /// Get a single recording with chunks.
  Future<Map<String, dynamic>> getRecording(String recordingId) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/v1/recordings/$recordingId'),
      headers: await _headers(),
    );
    return _decode(response);
  }

  /// Create a recording session on the backend.
  ///
  /// [id] is generated on-device so a recording started offline keeps the
  /// same ID once it syncs. Idempotent: repeating it returns the existing row.
  /// Pass `'unsorted'` as [subjectId] for Quick Record.
  Future<Map<String, dynamic>> createRecording({
    required String id,
    required String subjectId,
    required String title,
    String? language,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/v1/recordings'),
      headers: await _headers(json: true),
      body: jsonEncode({
        'id': id,
        'subjectId': subjectId,
        'title': title,
        if (language != null) 'language': language,
      }),
    );
    return _decode(response);
  }

  /// Upload one audio chunk as multipart form data.
  Future<Map<String, dynamic>> uploadChunk({
    required String recordingId,
    required String filePath,
    required int sequenceNumber,
    required int durationMs,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/v1/recordings/$recordingId/chunks'),
    );
    request.headers.addAll(await _headers());
    request.fields['sequenceNumber'] = '$sequenceNumber';
    request.fields['durationMs'] = '$durationMs';
    request.files.add(await http.MultipartFile.fromPath('file', filePath));

    final response = await http.Response.fromStream(await _client.send(request));
    return _decode(response);
  }

  /// Mark a recording as completed and trigger AI processing.
  Future<Map<String, dynamic>> completeRecording(
    String recordingId, {
    int totalDurationMs = 0,
  }) async {
    // PATCH to completed status (auto-triggers processing on backend)
    final response = await _client.patch(
      Uri.parse('$baseUrl/api/v1/recordings/$recordingId'),
      headers: await _headers(json: true),
      body: jsonEncode({
        'status': 'completed',
        'totalDurationMs': totalDurationMs,
      }),
    );
    return _decode(response);
  }

  // ─── Subjects ──────────────────────────────────────────────────

  /// List all subjects.
  Future<Map<String, dynamic>> listSubjects() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/v1/subjects'),
      headers: await _headers(),
    );
    return _decode(response);
  }

  /// Create a new subject.
  Future<Map<String, dynamic>> createSubject({
    required String name,
    required String color,
    String? icon,
  }) async {
    final body = <String, dynamic>{
      'name': name,
      'color': color,
    };
    if (icon != null) body['icon'] = icon;

    final response = await _client.post(
      Uri.parse('$baseUrl/api/v1/subjects'),
      headers: await _headers(json: true),
      body: jsonEncode(body),
    );
    return _decode(response);
  }

  /// Get a single subject (includes recording count).
  Future<Map<String, dynamic>> getSubject(String id) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/v1/subjects/$id'),
      headers: await _headers(),
    );
    return _decode(response);
  }

  /// Delete a subject.
  Future<void> deleteSubject(String id) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/api/v1/subjects/$id'),
      headers: await _headers(),
    );
    _decode(response);
  }

  /// Update a subject (name, color, etc.).
  Future<Map<String, dynamic>> updateSubject(
    String id, {
    String? name,
    String? color,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (color != null) body['color'] = color;

    final response = await _client.put(
      Uri.parse('$baseUrl/api/v1/subjects/$id'),
      headers: await _headers(json: true),
      body: jsonEncode(body),
    );
    return _decode(response);
  }

  /// Rename a recording and/or move it to another subject.
  /// Pass `'unsorted'` as [subjectId] to move it to Unsorted.
  Future<Map<String, dynamic>> updateRecording(
    String id, {
    String? title,
    String? subjectId,
  }) async {
    final response = await _client.patch(
      Uri.parse('$baseUrl/api/v1/recordings/$id'),
      headers: await _headers(json: true),
      body: jsonEncode({
        if (title != null) 'title': title,
        if (subjectId != null) 'subjectId': subjectId,
      }),
    );
    return _decode(response);
  }

  /// Delete a recording and all its associated data.
  Future<void> deleteRecording(String id) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/api/v1/recordings/$id'),
      headers: await _headers(),
    );
    if (response.statusCode != 204) {
      _decode(response);
    }
  }

  // ─── Helpers ───────────────────────────────────────────────────

  Map<String, dynamic> _decode(http.Response response) {
    // 204 No Content (e.g. deletes) has an empty body
    final body = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      final error = body['error'] as Map<String, dynamic>?;
      throw ApiException(
        statusCode: response.statusCode,
        code: error?['code'] as String? ?? 'UNKNOWN',
        message: error?['message'] as String? ?? 'Unknown error',
      );
    }
    return body;
  }

  void dispose() {
    _client.close();
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String code;
  final String message;

  const ApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  @override
  String toString() => 'ApiException($statusCode): [$code] $message';
}
