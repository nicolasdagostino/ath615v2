import 'dart:io';

import 'package:ath615v2/core/theme/app_theme.dart';
import 'package:ath615v2/core/widgets/app_avatar.dart';
import 'package:ath615v2/features/booking/presentation/widgets/booking_class_card.dart';
import 'package:ath615v2/features/booking/presentation/widgets/class_details_sheet.dart';
import 'package:ath615v2/features/members/presentation/widgets/member_list_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _photo =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ'
    'AAAADUlEQVQIHWP4z8DwHwAFgAI/ScL8WQAAAABJRU5ErkJggg==';

Widget _app(Widget child) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('real photo opens zoomable viewer and close exits', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const AppAvatar(name: 'Alex Duarte', avatarUrl: _photo, size: 44)),
    );

    await tester.tap(find.bySemanticsLabel('Ver foto de Alex Duarte'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('app-avatar-viewer')), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('app-avatar-viewer-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('app-avatar-viewer')), findsNothing);
  });

  testWidgets('fallback has no viewer action', (tester) async {
    await tester.pumpWidget(
      _app(const AppAvatar(name: 'Alex Duarte', size: 44)),
    );

    expect(find.text('AD'), findsOneWidget);
    expect(find.bySemanticsLabel('Ver foto de Alex Duarte'), findsNothing);
    await tester.tap(find.byType(AppAvatar));
    await tester.pump();
    expect(find.byKey(const ValueKey('app-avatar-viewer')), findsNothing);
  });

  testWidgets('failed network photo falls back without crashing', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const AppAvatar(
          name: 'Broken Photo',
          avatarUrl: 'https://invalid.invalid/avatar.jpg',
          size: 44,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('BP'), findsOneWidget);
    expect(find.byKey(const ValueKey('app-avatar-viewer')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('booking stack opens the selected photo and plus N does not', (
    tester,
  ) async {
    var cardTaps = 0;
    final profiles = [
      for (var index = 0; index < 6; index++)
        {
          'id': 'person-$index',
          'full_name': 'Person $index',
          'avatar_url': _photo,
        },
    ];
    await tester.pumpWidget(
      _app(
        SizedBox(
          width: 320,
          child: BookingClassCard(
            klass: const {
              'title': 'Class',
              'starts_at': '2030-01-01T10:00:00Z',
            },
            bookedCount: 6,
            capacity: 10,
            buttonLabel: 'Book',
            buttonAction: () {},
            onTap: () => cardTaps++,
            bookedProfiles: profiles,
            formatDateTime: (value) => value,
          ),
        ),
      ),
    );

    await tester.tap(find.bySemanticsLabel('Ver foto de Person 0'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Ver foto de Person 0'), findsWidgets);
    expect(cardTaps, 0);
    await tester.tap(find.byKey(const ValueKey('app-avatar-viewer-close')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('+2'));
    await tester.pump();
    expect(find.byKey(const ValueKey('app-avatar-viewer')), findsNothing);
  });

  testWidgets('class roster avatar is independent from its row action', (
    tester,
  ) async {
    var rowTaps = 0;
    await tester.pumpWidget(
      _app(
        ClassPersonRow(
          name: 'Roster Athlete',
          avatarUrl: _photo,
          onTap: () => rowTaps++,
        ),
      ),
    );

    await tester.tap(find.bySemanticsLabel('Ver foto de Roster Athlete'));
    await tester.pumpAndSettle();
    expect(rowTaps, 0);
    await tester.tap(find.byKey(const ValueKey('app-avatar-viewer-close')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Roster Athlete'));
    expect(rowTaps, 1);
  });

  testWidgets('class waitlist avatar uses the same viewer contract', (
    tester,
  ) async {
    var waitlistRowTaps = 0;
    await tester.pumpWidget(
      _app(
        ClassPersonRow(
          name: 'Waitlist Athlete',
          avatarUrl: _photo,
          position: 1,
          status: 'Waitlist',
          onTap: () => waitlistRowTaps++,
        ),
      ),
    );

    await tester.tap(find.bySemanticsLabel('Ver foto de Waitlist Athlete'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('app-avatar-viewer')), findsOneWidget);
    expect(waitlistRowTaps, 0);
  });

  testWidgets(
    'member avatar keeps row navigation independent at narrow width',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var rowTaps = 0;
      await tester.pumpWidget(
        _app(
          SizedBox(
            width: 320,
            child: MemberListRow(
              member: const {
                'full_name': 'Member With A Long Name',
                'email': 'member-with-a-long-address@example.com',
                'role': 'athlete',
                'is_active': true,
                'avatar_url': _photo,
              },
              onTap: () => rowTaps++,
              onMore: () {},
            ),
          ),
        ),
      );

      await tester.tap(
        find.bySemanticsLabel('Ver foto de Member With A Long Name'),
      );
      await tester.pumpAndSettle();
      expect(rowTaps, 0);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('app-avatar-viewer-close')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Member With A Long Name'));
      expect(rowTaps, 1);
    },
  );

  test('WOD comments use the shared avatar without profile queries', () {
    final source = File(
      'lib/features/workouts/presentation/screens/workout_detail_screen.dart',
    ).readAsStringSync();
    expect(source, contains('AppAvatar('));
    expect(source, contains('_authorAvatars[userId]'));
    expect(source, isNot(contains('get_profile_by_id')));
  });
}
