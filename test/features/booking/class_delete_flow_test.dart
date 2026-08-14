import 'package:ath615v2/features/booking/presentation/screens/booking_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final scenario in [
    'single class',
    'recurring occurrence',
    'this and future occurrences',
  ]) {
    test(
      '$scenario closes detail only after delete and refreshes selected date',
      () async {
        var detailClosed = false;
        var refreshedDay = DateTime(2026, 8, 13);

        final deleted = await completeClassDeletion(
          delete: () async {},
          closeDetail: () => detailClosed = true,
          refreshSelectedDate: () async {
            refreshedDay = DateTime(2026, 8, 13);
          },
          onError: (_) => fail('Successful deletion must not report an error.'),
        );

        expect(deleted, isTrue);
        expect(detailClosed, isTrue);
        expect(refreshedDay, DateTime(2026, 8, 13));
      },
    );
  }

  test(
    'delete failure leaves Class Detail open and does not refresh',
    () async {
      var detailClosed = false;
      var refreshed = false;
      Object? capturedError;

      final deleted = await completeClassDeletion(
        delete: () async => throw StateError('delete failed'),
        closeDetail: () => detailClosed = true,
        refreshSelectedDate: () async => refreshed = true,
        onError: (error) => capturedError = error,
      );

      expect(deleted, isFalse);
      expect(detailClosed, isFalse);
      expect(refreshed, isFalse);
      expect(capturedError, isA<StateError>());
    },
  );
}
