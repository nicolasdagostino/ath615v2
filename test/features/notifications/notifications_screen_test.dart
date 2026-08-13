import 'package:ath615v2/features/notifications/data/notifications_repository.dart';
import 'package:ath615v2/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

class _FakeNotificationsRepository implements NotificationsRepository {
  var listCalls = 0;
  var markAllCalls = 0;
  var clearCalls = 0;
  var markReadCalls = 0;

  @override
  Future<List<NotificationRecord>> listOwn() async {
    listCalls += 1;
    return [
      {
        'id': '10000000-0000-0000-0000-000000000000',
        'title': 'Horario especial',
        'body': 'El sábado abrimos a las 9.',
        'type': 'communication',
        'data': <String, dynamic>{'channel': 'admin'},
        'scheduled_for': '2026-08-10T10:00:00Z',
        'sent_at': '2026-08-10T10:00:00Z',
        'read_at': null,
      },
      {
        'id': '10000000-0000-0000-0000-000000000001',
        'title': 'Clase actualizada',
        'body': 'Revisa el nuevo horario.',
        'type': 'class_updated',
        'data': <String, dynamic>{},
        'scheduled_for': '2026-08-11T10:00:00Z',
        'sent_at': '2026-08-11T10:00:00Z',
        'read_at': null,
      },
    ];
  }

  @override
  Future<int> unreadCount() async => 1;

  @override
  Future<bool> markRead(String notificationId) async {
    markReadCalls += 1;
    return true;
  }

  @override
  Future<int> markAllRead() async {
    markAllCalls += 1;
    return 1;
  }

  @override
  Future<int> clearOwn() async {
    clearCalls += 1;
    return 2;
  }
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('defaults to communications and separates personal events', (
    tester,
  ) async {
    final repository = _FakeNotificationsRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsScreen(
          repository: repository,
          gymName: 'Athlete 615',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ATHLETE 615'), findsOneWidget);
    expect(find.text('COMMUNICATIONS'), findsOneWidget);
    expect(find.text('NOTIFICATIONS'), findsOneWidget);
    expect(find.text('Horario especial'), findsOneWidget);
    expect(find.text('Clase actualizada'), findsNothing);

    await tester.tap(find.text('NOTIFICATIONS'));
    await tester.pump();

    expect(find.text('Horario especial'), findsNothing);
    expect(find.text('Clase actualizada'), findsOneWidget);
    expect(find.text('Revisa el nuevo horario.'), findsOneWidget);
    expect(repository.listCalls, 1);
    expect(repository.markAllCalls, 0);
  });

  testWidgets('clear keeps the active chip and removes the full inbox', (
    tester,
  ) async {
    final repository = _FakeNotificationsRepository();
    var refreshes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsScreen(
          repository: repository,
          onNotificationsRead: () => refreshes += 1,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('NOTIFICATIONS'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('messages-clear-action')));
    await tester.pumpAndSettle();
    expect(find.text('DELETE ALL MESSAGES?'), findsOneWidget);
    expect(
      find.text(
        'All your communications and notifications from this gym will be deleted.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Clear'));
    await tester.pumpAndSettle();

    expect(repository.clearCalls, 1);
    expect(find.text('No personal notifications yet.'), findsOneWidget);
    expect(refreshes, greaterThanOrEqualTo(2));
  });

  testWidgets('messages remains overflow-free at 320 px', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsScreen(
          repository: _FakeNotificationsRepository(),
          gymName: 'A very long gym name for mobile',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('opening one notification marks only that record as read', (
    tester,
  ) async {
    final repository = _FakeNotificationsRepository();
    var refreshes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsScreen(
          repository: repository,
          onNotificationsRead: () => refreshes += 1,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Horario especial'));
    await tester.pumpAndSettle();

    expect(repository.markReadCalls, 1);
    expect(repository.markAllCalls, 0);
    expect(refreshes, greaterThanOrEqualTo(2));
  });

  testWidgets('membership request opens the administrative destination', (
    tester,
  ) async {
    final repository = _MembershipRequestNotificationsRepository();
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsScreen(
          repository: repository,
          onOpenMembershipRequests: () => opened += 1,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('NOTIFICATIONS'));
    await tester.pump();
    await tester.tap(find.text('New membership request'));
    await tester.pump();

    expect(opened, 1);
  });
}

class _MembershipRequestNotificationsRepository
    extends _FakeNotificationsRepository {
  @override
  Future<List<NotificationRecord>> listOwn() async => [
    {
      'id': '10000000-0000-0000-0000-000000000099',
      'title': 'New membership request',
      'body': 'Nicolás requested 5 classes.',
      'type': 'membership_request',
      'data': <String, dynamic>{'requestId': 'request-1'},
      'scheduled_for': '2026-08-14T10:00:00Z',
      'sent_at': '2026-08-14T10:00:00Z',
      'read_at': null,
    },
  ];
}
