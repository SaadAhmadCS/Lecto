import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// API client for the Lecto backend.
///
/// Wraps HTTP calls and provides typed responses for
/// recording status, transcripts, and summaries.
class LectoApiClient {
  final String baseUrl;
  final http.Client _client;
  String? _authToken;

  void setAuthToken(String? token) => _authToken = token;

  Map<String, String> get _jsonHeaders => {
    'Content-Type': 'application/json',
    if (_authToken != null) 'Authorization': 'Bearer $_authToken',
  };

  Map<String, String>? get _authHeader =>
      _authToken != null ? {'Authorization': 'Bearer $_authToken'} : null;

  LectoApiClient({
    this.baseUrl = 'http://192.168.100.93:3000', // LAN IP for physical device
  }) : _client = http.Client();

  // ─── Processing ────────────────────────────────────────────────

  /// Trigger processing for a recording.
  Future<Map<String, dynamic>> startProcessing(String recordingId) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/v1/recordings/$recordingId/process'),
      headers: _jsonHeaders,
      body: '{}',
    );
    return _decode(response);
  }

  /// Get processing status for a recording.
  Future<Map<String, dynamic>> getProcessingStatus(String recordingId) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/v1/recordings/$recordingId/status'),
      headers: _authHeader,
    );
    return _decode(response);
  }

  /// Get the assembled transcript.
  Future<Map<String, dynamic>?> getTranscript(String recordingId) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/v1/recordings/$recordingId/transcript'),
      headers: _authHeader,
    );
    if (response.statusCode == 404) return null;
    return _decode(response);
  }

  /// Get the AI-generated summary.
  Future<Map<String, dynamic>?> getSummary(String recordingId) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/v1/recordings/$recordingId/summary'),
      headers: _authHeader,
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
      headers: _authHeader,
    );
    return _decode(response);
  }

  /// Get a single recording with chunks.
  Future<Map<String, dynamic>> getRecording(String recordingId) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/v1/recordings/$recordingId'),
      headers: _authHeader,
    );
    return _decode(response);
  }

  /// Create a new recording session on the backend.
  /// Returns the server-side recording data (including ID).
  Future<Map<String, dynamic>> createRecording({
    required String subjectId,
    required String title,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/v1/recordings'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'subjectId': subjectId,
        'title': title,
      }),
    );
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
      headers: _jsonHeaders,
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
      headers: _authHeader,
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
      headers: _jsonHeaders,
      body: jsonEncode(body),
    );
    return _decode(response);
  }

  /// Delete a subject.
  Future<void> deleteSubject(String id) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/api/v1/subjects/$id'),
      headers: _authHeader,
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
      headers: _jsonHeaders,
      body: jsonEncode(body),
    );
    return _decode(response);
  }

  /// Delete a recording and all its associated data.
  Future<void> deleteRecording(String id) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/api/v1/recordings/$id'),
      headers: _authHeader,
    );
    if (response.statusCode != 204) {
      _decode(response);
    }
  }

  // ─── Helpers ───────────────────────────────────────────────────

  Map<String, dynamic> _decode(http.Response response) {
    final body = jsonDecode(response.body) as Map<String, dynamic>;
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
