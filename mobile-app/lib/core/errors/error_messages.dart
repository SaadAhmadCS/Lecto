import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../network/api_client.dart';

/// Turns exceptions into sentences a student can act on. Raw exception text
/// (`ApiException(503): ...`) never reaches the UI; it goes to the log.
class ErrorMessages {
  ErrorMessages._();

  static const generic = 'Something went wrong. Please try again.';
  static const offline =
      'Can\'t reach Lecto. Check your internet connection and try again.';

  /// [action] names what failed, e.g. "rename the recording", and is used
  /// when the error itself says nothing more useful.
  static String from(Object error, {String? action}) {
    debugPrint('Error${action == null ? '' : ' ($action)'}: $error');
    final fallback = action == null ? generic : 'Couldn\'t $action. Please try again.';

    return switch (error) {
      SocketException() || TimeoutException() || http.ClientException() => offline,
      FirebaseAuthException(:final code) => _auth(code) ?? fallback,
      PlatformException(:final code) => _platform(code) ?? fallback,
      ApiException() => _api(error) ?? fallback,
      _ => fallback,
    };
  }

  static String? _api(ApiException e) {
    switch (e.statusCode) {
      case 401:
        return 'Your session has expired. Please sign in again.';
      case 403:
        return 'You don\'t have access to this.';
      case 404:
        return 'This item no longer exists. It may have been deleted.';
      case 409:
        return 'That already exists.';
      case 429:
        return 'Too many requests. Please wait a moment and try again.';
      case 400:
        // Validation messages from the API are written for people
        return e.code == 'VALIDATION_ERROR' && e.message.isNotEmpty ? e.message : null;
    }
    if (e.statusCode >= 500) {
      return 'Lecto\'s servers are having trouble. Please try again shortly.';
    }
    return null;
  }

  static String? _auth(String code) => switch (code) {
        'invalid-email' => 'That email address doesn\'t look right.',
        'user-disabled' => 'This account has been disabled.',
        'user-not-found' ||
        'wrong-password' ||
        'invalid-credential' ||
        'INVALID_LOGIN_CREDENTIALS' =>
          'Incorrect email or password.',
        'email-already-in-use' =>
          'An account already exists for this email. Try signing in.',
        'weak-password' => 'Choose a stronger password (at least 6 characters).',
        'too-many-requests' =>
          'Too many attempts. Please wait a few minutes and try again.',
        'network-request-failed' => offline,
        'account-exists-with-different-credential' =>
          'This email is already linked to a different sign-in method.',
        'operation-not-allowed' => 'This sign-in method isn\'t available.',
        _ => null,
      };

  // google_sign_in reports failures as PlatformExceptions
  static String? _platform(String code) => switch (code) {
        'network_error' => offline,
        'sign_in_failed' => 'Google sign-in failed. Please try again.',
        _ => null,
      };
}
