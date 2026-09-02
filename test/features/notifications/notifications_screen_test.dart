import 'package:ath615v2/features/notifications/data/notifications_repository.dart';
import 'package:ath615v2/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:ath615v2/core/widgets/app_message_detail_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

class _FakeNotificationsRepository implements NotificationsRepository {
  var listCalls = 0;
  var markAllCalls = 0;
  var clearCalls = 0;
  String? clearedCategory;
  var markReadCalls = 0;
  var reaction = const CommunicationReactionSummary(
    thumbsUpCount: 1,
    heartCount: 2,
    myReaction: null,
  );

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
  Future<int> clearCategory(String category) async {
    clearCalls += 1;
    clearedCategory = category;
    return 1;
  }

  @override
  Future<CommunicationReactionSummary> loadCommunicationReactions(
    String notificationId,
  ) async => reaction;

  @override
  Future<CommunicationReactionSummary> setCommunicationReaction(
    String notificationId,
    String? nextReaction,
  ) async {
    reaction = switch ((reaction.myReaction, nextReaction)) {
      (final current, final next) when current == next =>
        CommunicationReactionSummary(
          thumbsUpCount: reaction.thumbsUpCount - (next == 'thumbs_up' ? 1 : 0),
          heartCount: reaction.heartCount - (next == 'heart' ? 1 : 0),
          myReaction: null,
        ),
      (_, 'thumbs_up') => CommunicationReactionSummary(
        thumbsUpCount:
            reaction.thumbsUpCount + (reaction.myReaction == null ? 1 : 1),
        heartCount:
            reaction.heartCount - (reaction.myReaction == 'heart' ? 1 : 0),
        myReaction: 'thumbs_up',
      ),
      (_, 'heart') => CommunicationReactionSummary(
        thumbsUpCount:
            reaction.thumbsUpCount -
            (reaction.myReaction == 'thumbs_up' ? 1 : 0),
        heartCount: reaction.heartCount + (reaction.myReaction == null ? 1 : 1),
        myReaction: 'heart',
      ),
      _ => reaction,
    };
    return reaction;
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

  testWidgets('admin capability exposes the existing create action', (
    tester,
  ) async {
    var opens = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsScreen(
          repository: _FakeNotificationsRepository(),
          canCreateNotification: true,
          onCreateNotification: () async => opens += 1,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('messages-create-notification')),
    );
    await tester.pump();
    expect(opens, 1);
  });

  testWidgets('athlete capability does not expose create action', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsScreen(repository: _FakeNotificationsRepository()),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('messages-create-notification')),
      findsNothing,
    );
  });

  testWidgets('create action opens the shared admin communication sheet', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsScreen(
          repository: _FakeNotificationsRepository(),
          canCreateNotification: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('messages-create-notification')),
    );
    await tester.pumpAndSettle();
    expect(find.text('SEND COMMUNICATION'), findsWidgets);
    expect(find.byType(ChoiceChip), findsNWidgets(4));
  });

  testWidgets('clear keeps active chip and preserves the other category', (
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
    expect(find.text('DELETE ALL NOTIFICATIONS?'), findsOneWidget);
    expect(
      find.text('Notifications from this gym will be deleted from your inbox.'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Clear'));
    await tester.pumpAndSettle();

    expect(repository.clearCalls, 1);
    expect(repository.clearedCategory, 'notification');
    expect(find.text('No personal notifications yet.'), findsOneWidget);
    await tester.tap(find.text('COMMUNICATIONS'));
    await tester.pump();
    expect(find.text('Horario especial'), findsOneWidget);
    expect(refreshes, greaterThanOrEqualTo(2));
  });

  testWidgets('clearing communications preserves personal notifications', (
    tester,
  ) async {
    final repository = _FakeNotificationsRepository();
    await tester.pumpWidget(
      MaterialApp(home: NotificationsScreen(repository: repository)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('messages-clear-action')));
    await tester.pumpAndSettle();
    expect(find.text('DELETE ALL COMMUNICATIONS?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Clear'));
    await tester.pumpAndSettle();
    expect(repository.clearedCategory, 'communication');
    expect(find.text('No gym communications yet.'), findsOneWidget);
    await tester.tap(find.text('NOTIFICATIONS'));
    await tester.pump();
    expect(find.text('Clase actualizada'), findsOneWidget);
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
    expect(find.byType(AppMessageDetailSheet), findsOneWidget);
    final detailIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byType(AppMessageDetailSheet),
        matching: find.byIcon(Icons.campaign_outlined),
      ),
    );
    expect(detailIcon.color, const Color(0xFF159ED1));
    expect(
      find.byKey(const ValueKey('communication-reactions')),
      findsOneWidget,
    );
    expect(find.text('👍 1'), findsOneWidget);
    expect(find.text('❤️ 2'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reaction-thumbs-up')));
    await tester.pumpAndSettle();
    expect(find.text('👍 2'), findsOneWidget);
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

  testWidgets('workout notification opens WOD date without a detail sheet', (
    tester,
  ) async {
    DateTime? openedDate;
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsScreen(
          repository: _WorkoutNotificationsRepository(),
          workoutDateResolver: (_) async => DateTime(2026, 8, 13),
          onOpenWorkoutDate: (date) => openedDate = date,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('NOTIFICATIONS'));
    await tester.pump();
    await tester.tap(find.text('How did it go?'));
    await tester.pumpAndSettle();

    expect(openedDate, DateTime(2026, 8, 13));
    expect(find.byType(AppMessageDetailSheet), findsNothing);
  });

  testWidgets('published workout uses embedded historical date directly', (
    tester,
  ) async {
    DateTime? openedDate;
    Map<String, dynamic>? resolvedData;
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsScreen(
          repository: _WorkoutNotificationsRepository(
            type: 'workout_published',
            data: const {
              'workoutId': 'workout-modern',
              'workoutDate': '2026-08-10',
            },
          ),
          workoutDateResolver: (data) async {
            resolvedData = data;
            return DateTime.parse(data['workoutDate'].toString());
          },
          onOpenWorkoutDate: (date) => openedDate = date,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('NOTIFICATIONS'));
    await tester.pump();
    await tester.tap(find.text('How did it go?'));
    await tester.pumpAndSettle();

    expect(resolvedData?['workoutDate'], '2026-08-10');
    expect(openedDate, DateTime(2026, 8, 10));
    expect(find.byType(AppMessageDetailSheet), findsNothing);
  });

  for (final entry in <String, IconData>{
    'class_reminder': Icons.calendar_month_outlined,
    'birthday': Icons.cake_outlined,
    'membership_approved': Icons.card_membership_outlined,
    'unknown_type': Icons.notifications_none_rounded,
  }.entries) {
    testWidgets('${entry.key} uses the shared primary detail', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: NotificationsScreen(
            repository: _TypedNotificationsRepository(entry.key),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('NOTIFICATIONS'));
      await tester.pump();
      await tester.tap(find.text('Typed notification'));
      await tester.pumpAndSettle();

      expect(find.byType(AppMessageDetailSheet), findsOneWidget);
      expect(
        find.byKey(const ValueKey('communication-reactions')),
        findsNothing,
      );
      final icon = tester.widget<Icon>(find.byIcon(entry.value));
      expect(icon.color, const Color(0xFF159ED1));
    });
  }
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

class _WorkoutNotificationsRepository extends _FakeNotificationsRepository {
  _WorkoutNotificationsRepository({
    this.type = 'post_score_reminder',
    this.data = const {'workoutId': 'workout-1'},
  });

  final String type;
  final Map<String, dynamic> data;

  @override
  Future<List<NotificationRecord>> listOwn() async => [
    {
      'id': '10000000-0000-0000-0000-000000000088',
      'title': 'How did it go?',
      'body': 'Share your score.',
      'type': type,
      'data': data,
      'scheduled_for': '2026-08-13T10:00:00Z',
      'sent_at': '2026-08-13T10:00:00Z',
      'read_at': null,
    },
  ];
}

class _TypedNotificationsRepository extends _FakeNotificationsRepository {
  _TypedNotificationsRepository(this.type);
  final String type;

  @override
  Future<List<NotificationRecord>> listOwn() async => [
    {
      'id': '10000000-0000-0000-0000-000000000077',
      'title': 'Typed notification',
      'body': 'A message body.',
      'type': type,
      'data': <String, dynamic>{},
      'scheduled_for': '2026-08-13T10:00:00Z',
      'sent_at': '2026-08-13T10:00:00Z',
      'read_at': null,
    },
  ];
}
