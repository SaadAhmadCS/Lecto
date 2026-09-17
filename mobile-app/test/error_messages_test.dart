import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lecto/core/errors/error_messages.dart';
import 'package:lecto/core/network/api_client.dart';

void main() {
  test('network failures ask the user to check their connection', () {
    expect(
      ErrorMessages.from(const SocketException('Connection refused')),
      ErrorMessages.offline,
    );
    expect(
      ErrorMessages.from(FirebaseAuthException(code: 'network-request-failed')),
      ErrorMessages.offline,
    );
  });

  test('wrong sign-in details never reveal which part was wrong', () {
    for (final code in ['user-not-found', 'wrong-password', 'invalid-credential']) {
      expect(
        ErrorMessages.from(FirebaseAuthException(code: code)),
        'Incorrect email or password.',
      );
    }
  });

  test('API errors map by status, and raw details never leak', () {
    const serverDown = ApiException(statusCode: 503, code: 'DOWN', message: 'prisma exploded');
    expect(ErrorMessages.from(serverDown), isNot(contains('prisma')));
    expect(ErrorMessages.from(serverDown), contains('servers'));

    const missing = ApiException(statusCode: 404, code: 'NOT_FOUND', message: 'Recording x not found');
    expect(ErrorMessages.from(missing), contains('no longer exists'));
  });

  test('validation messages from the API are shown as written', () {
    const invalid = ApiException(
      statusCode: 400,
      code: 'VALIDATION_ERROR',
      message: 'Subject name is required',
    );
    expect(ErrorMessages.from(invalid), 'Subject name is required');
  });

  test('unknown errors fall back to the action that failed', () {
    expect(
      ErrorMessages.from(StateError('boom'), action: 'rename the recording'),
      'Couldn\'t rename the recording. Please try again.',
    );
    expect(ErrorMessages.from(StateError('boom')), ErrorMessages.generic);
  });
}
