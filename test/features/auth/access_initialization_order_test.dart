import 'dart:async';

import 'package:ath615v2/app/app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'cold start completes access validation before starting deep links',
    () async {
      final validation = Completer<void>();
      final calls = <String>[];

      final initialization = initializeAccessBeforeDeepLinks(
        revalidateAccess: () async {
          calls.add('revalidate-start');
          await validation.future;
          calls.add('revalidate-end');
        },
        startDeepLinks: () async => calls.add('deep-links'),
      );

      await Future<void>.delayed(Duration.zero);
      expect(calls, ['revalidate-start']);
      validation.complete();
      await initialization;
      expect(calls, ['revalidate-start', 'revalidate-end', 'deep-links']);
    },
  );
}
