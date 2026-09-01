import 'dart:async';
import 'dart:io';

import 'package:ath615v2/core/theme/app_theme.dart';
import 'package:ath615v2/core/widgets/app_avatar.dart';
import 'package:ath615v2/features/workouts/presentation/screens/workout_detail_screen.dart';
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
  testWidgets('renders unliked, liked and count states', (tester) async {
    await tester.pumpWidget(
      _app(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            WorkoutCommentLikeButton(
              liked: false,
              count: 0,
              onToggle: () async =>
                  const WorkoutCommentLikeResult(liked: true, count: 1),
              onError: () {},
            ),
            WorkoutCommentLikeButton(
              liked: true,
              count: 4,
              onToggle: () async =>
                  const WorkoutCommentLikeResult(liked: false, count: 3),
              onError: () {},
            ),
          ],
        ),
      ),
    );

    expect(find.byKey(const ValueKey('comment-unliked')), findsOneWidget);
    expect(find.byKey(const ValueKey('comment-liked')), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('optimistic like and unlike update immediately', (tester) async {
    final like = Completer<WorkoutCommentLikeResult>();
    await tester.pumpWidget(
      _app(
        WorkoutCommentLikeButton(
          liked: false,
          count: 4,
          onToggle: () => like.future,
          onError: () {},
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('workout-comment-like')));
    await tester.pump();
    expect(find.byKey(const ValueKey('comment-liked')), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    like.complete(const WorkoutCommentLikeResult(liked: true, count: 5));
    await tester.pump();

    final unlike = Completer<WorkoutCommentLikeResult>();
    await tester.pumpWidget(
      _app(
        WorkoutCommentLikeButton(
          liked: true,
          count: 5,
          onToggle: () => unlike.future,
          onError: () {},
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('workout-comment-like')));
    await tester.pump();
    expect(find.byKey(const ValueKey('comment-unliked')), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('failure rolls back and exposes only a human error callback', (
    tester,
  ) async {
    var errors = 0;
    await tester.pumpWidget(
      _app(
        WorkoutCommentLikeButton(
          liked: false,
          count: 2,
          onToggle: () async => throw Exception('P0001 raw SQL'),
          onError: () => errors++,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('workout-comment-like')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('comment-unliked')), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.textContaining('P0001'), findsNothing);
    expect(errors, 1);
  });

  testWidgets('double tap is serialized while request is pending', (
    tester,
  ) async {
    final pending = Completer<WorkoutCommentLikeResult>();
    var calls = 0;
    await tester.pumpWidget(
      _app(
        WorkoutCommentLikeButton(
          liked: false,
          count: 1,
          onToggle: () {
            calls++;
            return pending.future;
          },
          onError: () {},
        ),
      ),
    );

    final button = find.byKey(const ValueKey('workout-comment-like'));
    await tester.tap(button);
    await tester.tap(button);
    await tester.pump();
    expect(calls, 1);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('avatar viewer and comment like remain independent at 320 px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var likes = 0;
    await tester.pumpWidget(
      _app(
        Row(
          children: [
            const AppAvatar(
              name: 'Comment Author',
              avatarUrl: _photo,
              size: 38,
            ),
            const SizedBox(width: 8),
            const Expanded(child: Text('Comment body remains unchanged')),
            WorkoutCommentLikeButton(
              liked: false,
              count: 0,
              onToggle: () async {
                likes++;
                return const WorkoutCommentLikeResult(liked: true, count: 1);
              },
              onError: () {},
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.bySemanticsLabel('Ver foto de Comment Author'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('app-avatar-viewer')), findsOneWidget);
    expect(likes, 0);
    expect(tester.takeException(), isNull);
  });

  test('comments are loaded once through the aggregate RPC', () {
    final source = File(
      'lib/features/workouts/presentation/screens/workout_detail_screen.dart',
    ).readAsStringSync();
    expect(
      RegExp('list_effective_workout_comments').allMatches(source).length,
      1,
    );
    expect(source, isNot(contains('workout_comment_likes(user_id)')));
  });
}
