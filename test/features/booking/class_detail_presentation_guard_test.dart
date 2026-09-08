import 'dart:async';

import 'package:ath615v2/features/booking/presentation/widgets/class_details_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('single tap opens one Class Detail', () async {
    final guard = ClassDetailPresentationGuard();
    var openings = 0;

    final accepted = await guard.run(() async => openings++);

    expect(accepted, isTrue);
    expect(openings, 1);
    expect(guard.isActive, isFalse);
  });

  test('double tap and five rapid taps remain single-flight', () async {
    final guard = ClassDetailPresentationGuard();
    final closed = Completer<void>();
    var openings = 0;

    Future<void> present() async {
      openings++;
      await closed.future;
    }

    final first = guard.run(present);
    final rapidResults = await Future.wait([
      guard.run(present),
      guard.run(present),
      guard.run(present),
      guard.run(present),
    ]);

    expect(openings, 1);
    expect(rapidResults, everyElement(isFalse));
    expect(guard.isActive, isTrue);
    closed.complete();
    expect(await first, isTrue);
  });

  test('tap while open is ignored and close permits a new opening', () async {
    final guard = ClassDetailPresentationGuard();
    final firstClosed = Completer<void>();
    var openings = 0;

    final first = guard.run(() async {
      openings++;
      await firstClosed.future;
    });
    expect(await guard.run(() async => openings++), isFalse);
    firstClosed.complete();
    await first;

    expect(await guard.run(() async => openings++), isTrue);
    expect(openings, 2);
  });

  test('presentation failure releases the lock', () async {
    final guard = ClassDetailPresentationGuard();

    await expectLater(
      guard.run(() async => throw StateError('presentation failed')),
      throwsStateError,
    );

    expect(guard.isActive, isFalse);
    expect(await guard.run(() async {}), isTrue);
  });

  test('different class cards share one active-detail lock', () async {
    final guard = ClassDetailPresentationGuard();
    final closed = Completer<void>();
    final openedClassIds = <String>[];

    final first = guard.run(() async {
      openedClassIds.add('class-a');
      await closed.future;
    });
    final secondAccepted = await guard.run(() async {
      openedClassIds.add('class-b');
    });

    expect(secondAccepted, isFalse);
    expect(openedClassIds, ['class-a']);
    closed.complete();
    await first;

    expect(await guard.run(() async => openedClassIds.add('class-b')), isTrue);
    expect(openedClassIds, ['class-a', 'class-b']);
  });
}
