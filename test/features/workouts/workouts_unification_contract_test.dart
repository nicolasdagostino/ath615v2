import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('date source queries one exact date and preserves social payload', () {
    final source = File(
      'lib/features/workouts/data/workouts_date_data_source.dart',
    ).readAsStringSync();

    expect(source, contains(".eq('workout_date', value)"));
    expect(source, contains('workout_likes(user_id)'));
    expect(source, contains('workout_comments(id, body, user_id, created_at)'));
    expect(source, isNot(contains(".gt('workout_date'")));
    expect(source, isNot(contains(".lt('workout_date'")));
  });

  test('future visibility is blocked before the data source is called', () {
    final source = File(
      'lib/features/workouts/presentation/screens/workouts_screen.dart',
    ).readAsStringSync();

    expect(source, contains("bool get _canSeeFuture => _role == 'admin'"));
    expect(source, contains('(_selectedIsFuture && !_canSeeFuture)'));
    expect(source, contains('initialDate: _selectedDate'));
    expect(source, contains('showManageProgramsSheet'));
    expect(source, contains('showAppConfirmationDialog'));
  });

  test('database model permits one workout per program and date', () {
    final migration = File(
      'supabase/migrations/001_programs_workouts.sql',
    ).readAsStringSync();

    expect(migration, contains('unique (gym_id, program_id, workout_date)'));
  });

  test('shared visual primitives prevent Booking and WOD divergence', () {
    final bookingCalendar = File(
      'lib/features/booking/presentation/widgets/booking_day_chips.dart',
    ).readAsStringSync();
    final bookingHeader = File(
      'lib/features/booking/presentation/widgets/booking_header.dart',
    ).readAsStringSync();
    final wodScreen = File(
      'lib/features/workouts/presentation/screens/workouts_screen.dart',
    ).readAsStringSync();
    final classForm = File(
      'lib/features/booking/presentation/widgets/class_form_components.dart',
    ).readAsStringSync();
    final workoutForm = File(
      'lib/features/workouts/presentation/widgets/workout_form_controls.dart',
    ).readAsStringSync();

    expect(bookingCalendar, contains('AppWeekDateSelector('));
    expect(bookingHeader, contains('AppSelectedDateLabel('));
    expect(wodScreen, contains('AppWeekDateSelector('));
    expect(wodScreen, contains('AppSelectedDateLabel('));
    expect(
      wodScreen,
      isNot(contains("DateFormat(\n                  'EEEE, d MMMM y'")),
    );
    expect(classForm, contains('AppFormHeader('));
    expect(workoutForm, contains('AppFormHeader('));
    expect(classForm, contains('AppFormSubmitButton('));
    expect(workoutForm, contains('AppFormSubmitButton('));
  });

  test('social modal uses localized comments identity instead of Program', () {
    final detail = File(
      'lib/features/workouts/presentation/screens/workout_detail_screen.dart',
    ).readAsStringSync();
    expect(detail, contains('appStrings.workoutCommentsTitle'));
  });

  test('Booking, WOD and Profile share the main header height token', () {
    final booking = File(
      'lib/features/booking/presentation/widgets/booking_header.dart',
    ).readAsStringSync();
    final workouts = File(
      'lib/features/workouts/presentation/screens/workouts_screen.dart',
    ).readAsStringSync();
    final profile = File(
      'lib/features/profile/presentation/screens/profile_screen.dart',
    ).readAsStringSync();
    final tokens = File(
      'lib/core/theme/app_design_tokens.dart',
    ).readAsStringSync();

    expect(tokens, contains('mainHeaderHeight = 50'));
    expect(booking, contains('height: AppSizes.mainHeaderHeight'));
    expect(workouts, contains('height: AppSizes.mainHeaderHeight'));
    expect(profile, contains('height: AppSizes.mainHeaderHeight'));
  });

  test('workout detail retains social behavior with shared admin actions', () {
    final detail = File(
      'lib/features/workouts/presentation/screens/workout_detail_screen.dart',
    ).readAsStringSync();

    expect(detail, contains('AppOutlinedAdminButton('));
    expect(detail, contains('AppAdminActionSheet('));
    expect(detail, contains("from('workout_likes')"));
    expect(detail, contains("from('workout_comments')"));
    expect(detail, contains('CircleAvatar('));
    expect(detail, contains('_commentFocus'));
    expect(detail, contains('AppSecondaryActionHeader('));
    expect(detail, isNot(contains('title: programName')));
    expect(detail, isNot(contains('0xFFB59B6A')));
    expect(detail, isNot(contains('AppColors.accent')));
  });

  test('WOD uses a social sheet while the deep-link detail route remains', () {
    final card = File(
      'lib/features/workouts/presentation/widgets/workout_card.dart',
    ).readAsStringSync();
    final detail = File(
      'lib/features/workouts/presentation/screens/workout_detail_screen.dart',
    ).readAsStringSync();
    final router = File('lib/core/router/app_router.dart').readAsStringSync();

    expect(card, contains('showWorkoutSocialSheet('));
    expect(card, contains('await widget.onChanged?.call()'));
    expect(card, contains('void didUpdateWidget'));
    expect(card, contains('_comments = widget.comments'));
    expect(card, isNot(contains('Navigator.of(context).push')));
    expect(card, isNot(contains('.take(4)')));
    expect(card, isNot(contains('maxLines: 5')));
    expect(detail, contains('heightFactor: 0.92'));
    expect(detail, contains('socialOnly: true'));
    expect(detail, contains("key: const ValueKey('workout-social-composer')"));
    expect(router, contains("path: '/workout/:id'"));
  });

  test('WOD uses the same header-to-content spacing token as Booking', () {
    final booking = File(
      'lib/features/booking/presentation/screens/booking_screen.dart',
    ).readAsStringSync();
    final workouts = File(
      'lib/features/workouts/presentation/screens/workouts_screen.dart',
    ).readAsStringSync();

    expect(
      booking,
      contains(
        'BookingHeader(gymName: widget.gymName),\n'
        '                const SizedBox(height: AppSpacing.md)',
      ),
    );
    expect(workouts, contains("ValueKey('workout-header-content-spacing')"));
    expect(workouts, contains('height: AppSpacing.md'));
  });

  test(
    'Class and Workout destructive flows use one confirmation primitive',
    () {
      final booking = File(
        'lib/features/booking/presentation/screens/booking_screen.dart',
      ).readAsStringSync();
      final workouts = File(
        'lib/features/workouts/presentation/screens/workouts_screen.dart',
      ).readAsStringSync();
      final workoutDetail = File(
        'lib/features/workouts/presentation/screens/workout_detail_screen.dart',
      ).readAsStringSync();
      final confirmation = File(
        'lib/core/widgets/app_confirmation_dialog.dart',
      ).readAsStringSync();

      expect(booking, contains('showAppConfirmationDialog('));
      expect(workouts, contains('showAppConfirmationDialog('));
      expect(workoutDetail, contains('showAppConfirmationDialog('));
      expect(workoutDetail, isNot(contains('showModalBottomSheet<bool>(')));
      expect(booking, isNot(contains('Icons.warning_amber_rounded')));
      expect(confirmation, contains('AppColors.danger'));
      expect(confirmation, contains('Icons.delete_outline_rounded'));
      expect(confirmation, contains('AppRadii.card'));
      expect(confirmation, contains('AppSpacing.cardPadding'));
    },
  );
}
