import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/strings/app_strings.dart';

enum MembershipRequestErrorKind {
  requiredConsent,
  documentsChanged,
  network,
  forbidden,
  unexpected,
}

class MembershipRequestErrorPresentation {
  const MembershipRequestErrorPresentation({
    required this.kind,
    required this.title,
    required this.message,
  });

  final MembershipRequestErrorKind kind;
  final String title;
  final String message;

  bool get canReviewDocuments =>
      kind == MembershipRequestErrorKind.requiredConsent ||
      kind == MembershipRequestErrorKind.documentsChanged;
}

MembershipRequestErrorPresentation presentMembershipRequestError(Object error) {
  final technicalMessage = switch (error) {
    PostgrestException() => error.message,
    FunctionException() =>
      error.details?.toString() ?? error.reasonPhrase ?? '',
    _ => '',
  };
  final code = error is PostgrestException ? error.code : null;

  if (technicalMessage.contains('required_consent_missing')) {
    return MembershipRequestErrorPresentation(
      kind: MembershipRequestErrorKind.requiredConsent,
      title: appStrings.membershipConsentMissingTitle,
      message: appStrings.membershipConsentMissingMessage,
    );
  }
  if (technicalMessage.contains('documents_changed')) {
    return MembershipRequestErrorPresentation(
      kind: MembershipRequestErrorKind.documentsChanged,
      title: appStrings.membershipDocumentsChangedTitle,
      message: appStrings.documentsChangedRefresh,
    );
  }
  if (code == '42501' || technicalMessage.contains('forbidden')) {
    return MembershipRequestErrorPresentation(
      kind: MembershipRequestErrorKind.forbidden,
      title: appStrings.membershipRequestCouldNotComplete,
      message: appStrings.membershipRequestForbidden,
    );
  }
  if (error is SocketException || error is TimeoutException) {
    return MembershipRequestErrorPresentation(
      kind: MembershipRequestErrorKind.network,
      title: appStrings.membershipRequestCouldNotComplete,
      message: appStrings.membershipRequestConnection,
    );
  }
  return MembershipRequestErrorPresentation(
    kind: MembershipRequestErrorKind.unexpected,
    title: appStrings.membershipRequestCouldNotComplete,
    message: appStrings.membershipRequestUnexpected,
  );
}
