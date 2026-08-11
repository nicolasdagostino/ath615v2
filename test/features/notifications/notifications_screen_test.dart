import 'package:ath615v2/features/notifications/data/notifications_repository.dart';
import 'package:ath615v2/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

class _FakeNotificationsRepository implements NotificationsRepository {
  var listCalls = 0;
  var markAllCalls = 0;

  @override
  Future<List<NotificationRecord>> listOwn() async {
    listCalls += 1;
    return [
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
  Future<bool> markRead(String notificationId) async => true;

  @override
  Future<int> markAllRead() async {
    markAllCalls += 1;
    return 1;
  }

  @override
  Future<int> clearOwn() async => 1;
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('loads the effective inbox and marks loaded items as read', (
    tester,
  ) async {
    final repository = _FakeNotificationsRepository();

    await tester.pumpWidget(
      MaterialApp(home: NotificationsScreen(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Clase actualizada'), findsOneWidget);
    expect(find.text('Revisa el nuevo horario.'), findsOneWidget);
    expect(repository.listCalls, 1);
    expect(repository.markAllCalls, 1);
  });
}
