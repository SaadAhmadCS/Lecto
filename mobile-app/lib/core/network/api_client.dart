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

  LectoApiClient({
    this.baseUrl = 'http://10.0.2.2:3000', // Android emulator → host
  }) : _client = http.Client();

  // ─── Processing ────────────────────────────────────────────────

  /// Trigger processing for a recording.
  Future<Map<String, dynamic>> startProcessing(String recordingId) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/v1/recordings/$recordingId/process'),
      headers: {'Content-Type': 'application/json'},
      body: '{}',
    );
    return _decode(response);
  }

  /// Get processing status for a recording.
  Future<Map<String, dynamic>> getProcessingStatus(String recordingId) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/v1/recordings/$recordingId/status'),
    );
    return _decode(response);
  }

  /// Get the assembled transcript.
  Future<Map<String, dynamic>?> getTranscript(String recordingId) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/v1/recordings/$recordingId/transcript'),
    );
    if (response.statusCode == 404) return null;
    return _decode(response);
  }

  /// Get the AI-generated summary.
  Future<Map<String, dynamic>?> getSummary(String recordingId) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/v1/recordings/$recordingId/summary'),
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
    );
    return _decode(response);
  }

  /// Get a single recording with chunks.
  Future<Map<String, dynamic>> getRecording(String recordingId) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/v1/recordings/$recordingId'),
    );
    return _decode(response);
  }

  // ─── Subjects ──────────────────────────────────────────────────

  /// List all subjects.
  Future<Map<String, dynamic>> listSubjects() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/v1/subjects'),
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
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return _decode(response);
  }

  /// Delete a subject.
  Future<void> deleteSubject(String id) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/api/v1/subjects/$id'),
    );
    _decode(response);
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
