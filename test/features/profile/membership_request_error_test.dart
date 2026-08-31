import 'dart:async';
import 'dart:io';

import 'package:ath615v2/features/profile/presentation/membership_request_error.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('maps documents_changed without exposing backend details', () {
    final result = presentMembershipRequestError(
      const PostgrestException(
        message: 'documents_changed',
        code: 'P0001',
        details: 'Bad Request',
      ),
    );
    expect(result.kind, MembershipRequestErrorKind.documentsChanged);
    expect(result.message, contains('documents changed'));
    expect(result.message, isNot(contains('P0001')));
  });

  test('maps socket and timeout failures to connection guidance', () {
    for (final error in <Object>[
      const SocketException('raw socket detail'),
      TimeoutException('raw timeout detail'),
    ]) {
      final result = presentMembershipRequestError(error);
      expect(result.kind, MembershipRequestErrorKind.network);
      expect(result.message, contains('Check your connection'));
      expect(result.message, isNot(contains('raw')));
    }
  });

  test('maps forbidden code and message to permission guidance', () {
    for (final error in <Object>[
      const PostgrestException(message: 'anything', code: '42501'),
      const PostgrestException(message: 'forbidden', code: 'P0001'),
    ]) {
      final result = presentMembershipRequestError(error);
      expect(result.kind, MembershipRequestErrorKind.forbidden);
      expect(result.message, contains('permission'));
      expect(result.message, isNot(contains('42501')));
    }
  });

  test('unexpected failures use a technical-detail-free fallback', () {
    final result = presentMembershipRequestError(
      StateError('RPC secret_internal_name exploded'),
    );
    expect(result.kind, MembershipRequestErrorKind.unexpected);
    expect(result.message, 'We could not complete the request. Try again.');
    expect(result.message, isNot(contains('secret_internal_name')));
  });
}
