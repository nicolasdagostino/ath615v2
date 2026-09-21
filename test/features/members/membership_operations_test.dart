import 'dart:async';

import 'package:ath615v2/core/theme/app_colors.dart';
import 'package:ath615v2/core/widgets/app_confirmation_dialog.dart';

import 'package:ath615v2/core/locale/locale_controller.dart';
import 'package:ath615v2/core/theme/app_theme.dart';
import 'package:ath615v2/features/members/data/membership_operations_repository.dart';
import 'package:ath615v2/features/members/presentation/widgets/membership_operations_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeOperations implements MembershipOperationsDataSource {
  _FakeOperations(this.value);
  MembershipOperationPreview value;
  int previewCalls = 0;
  int voidCalls = 0;
  int cancelCalls = 0;
  int expirationCalls = 0;
  String? reason;
  String? note;
  bool? cancelConflicts;
  Completer<void>? pendingCancel;

  @override
  Future<MembershipOperationPreview> preview(
    String membershipId, {
    DateTime? newExpiration,
  }) async {
    previewCalls++;
    return value;
  }

  @override
  Future<void> voidMembership({
    required String membershipId,
    required String reason,
    String? note,
  }) async {
    voidCalls++;
    this.reason = reason;
    this.note = note;
  }

  @override
  Future<void> cancelMembership({
    required String membershipId,
    required String reason,
    String? note,
  }) async {
    cancelCalls++;
    this.reason = reason;
    this.note = note;
    await pendingCancel?.future;
  }

  @override
  Future<void> changeExpiration({
    required String membershipId,
    required DateTime newExpiration,
    required String reason,
    String? note,
    required bool cancelConflictingBookings,
  }) async {
    expirationCalls++;
    this.reason = reason;
    this.note = note;
    cancelConflicts = cancelConflictingBookings;
  }
}

MembershipOperationPreview preview({
  String status = 'active',
  int attended = 0,
  int noShow = 0,
  int future = 2,
  int conflicts = 0,
  bool chained = false,
}) => MembershipOperationPreview(
  membershipId: 'membership-1',
  planName: 'Pack 5',
  planType: 'class_pack',
  status: status,
  startsAt: DateTime(2026, 9, 1),
  expiresAt: DateTime(2026, 10, 1),
  creditsRemaining: 3,
  creditsTotal: 5,
  attendedCount: attended,
  noShowCount: noShow,
  futureBookedCount: future,
  conflictingBookingCount: conflicts,
  futureBookings: const [],
  hasChainedUnlimited: chained,
);

Future<void> _pumpForm(
  WidgetTester tester, {
  required MembershipAdminOperation operation,
  required _FakeOperations source,
  Future<void> Function()? onSuccess,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: MembershipOperationForm(
          operation: operation,
          initialPreview: source.value,
          dataSource: source,
          onSuccess: onSuccess ?? () async {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> chooseReason(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const ValueKey('membership-operation-reason')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('es');
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    await localeController.setLanguage('en');
  });

  test('actions are permissioned by membership state', () {
    expect(membershipOperationsForStatus('active'), hasLength(3));
    expect(membershipOperationsForStatus('scheduled'), hasLength(3));
    expect(membershipOperationsForStatus('expired'), [
      MembershipAdminOperation.changeExpiration,
      MembershipAdminOperation.voidMembership,
    ]);
    for (final status in ['cancelled', 'voided', 'replaced']) {
      expect(membershipOperationsForStatus(status), isEmpty);
    }
  });

  testWidgets('admin launcher loads one preview and exposes valid actions', (
    tester,
  ) async {
    final source = _FakeOperations(preview());
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: MembershipOperationsLauncher(
            membershipId: 'membership-1',
            status: 'active',
            dataSource: source,
            onChanged: () async {},
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('membership-actions')));
    await tester.pumpAndSettle();
    expect(source.previewCalls, 1);
    expect(find.text('CHANGE EXPIRATION'), findsOne);
    expect(find.text('VOID MEMBERSHIP'), findsOne);
    expect(find.text('CANCEL MEMBERSHIP'), findsOne);
  });

  testWidgets('impact preview blocks void after attendance or no-show', (
    tester,
  ) async {
    final source = _FakeOperations(preview(attended: 1, noShow: 1));
    await _pumpForm(
      tester,
      operation: MembershipAdminOperation.voidMembership,
      source: source,
    );
    expect(find.byKey(const ValueKey('membership-impact-preview')), findsOne);
    expect(find.text('Attendance: 1'), findsOne);
    expect(find.text('No-shows: 1'), findsOne);
    await chooseReason(tester, 'Assigned by mistake');
    await tester.tap(find.byKey(const ValueKey('membership-operation-submit')));
    await tester.pump();
    expect(find.textContaining('cannot be voided'), findsOne);
    expect(source.voidCalls, 0);
  });

  testWidgets('other reason requires an administrative note', (tester) async {
    final source = _FakeOperations(preview());
    await _pumpForm(
      tester,
      operation: MembershipAdminOperation.cancel,
      source: source,
    );
    await chooseReason(tester, 'Other');
    await tester.tap(find.byKey(const ValueKey('membership-operation-submit')));
    await tester.pump();
    expect(find.text('Add a note for Other.'), findsOne);
    expect(source.cancelCalls, 0);
  });

  testWidgets('cancel confirms impact, prevents double submit and refreshes', (
    tester,
  ) async {
    final source = _FakeOperations(preview())
      ..pendingCancel = Completer<void>();
    var refreshes = 0;
    await _pumpForm(
      tester,
      operation: MembershipAdminOperation.cancel,
      source: source,
      onSuccess: () async => refreshes++,
    );
    await chooseReason(tester, 'Member request');
    await tester.tap(find.byKey(const ValueKey('membership-operation-submit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 future booking'), findsOne);
    await tester.tap(find.text('CONFIRM'));
    await tester.pump();
    expect(source.cancelCalls, 1);
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('membership-operation-submit')),
    );
    expect(button.onPressed, isNull);
    source.pendingCancel!.complete();
    await tester.pumpAndSettle();
    expect(source.cancelCalls, 1);
    expect(refreshes, 1);
  });

  testWidgets('expired expiration flow shows picker and reactivation warning', (
    tester,
  ) async {
    final source = _FakeOperations(preview(status: 'expired'));
    await _pumpForm(
      tester,
      operation: MembershipAdminOperation.changeExpiration,
      source: source,
    );
    expect(
      find.byKey(const ValueKey('membership-expiration-picker')),
      findsOne,
    );
    expect(
      find.byKey(const ValueKey('membership-reactivation-warning')),
      findsOne,
    );
    expect(
      find.textContaining('explicit administrative reactivation'),
      findsOne,
    );
  });

  testWidgets(
    'expiration uses neutral borders and cyan focus and confirmation',
    (tester) async {
      final source = _FakeOperations(preview());
      await _pumpForm(
        tester,
        operation: MembershipAdminOperation.changeExpiration,
        source: source,
      );
      final reason = find.byKey(const ValueKey('membership-operation-reason'));
      final theme = Theme.of(tester.element(reason));
      expect(
        theme.inputDecorationTheme.enabledBorder!.borderSide.color,
        AppColors.border(tester.element(reason)),
      );
      expect(
        theme.inputDecorationTheme.focusedBorder!.borderSide.color,
        AppColors.primary,
      );
      expect(theme.colorScheme.primary, AppColors.primary);
      await chooseReason(tester, 'Injury');
      await tester.tap(
        find.byKey(const ValueKey('membership-expiration-picker')),
      );
      await tester.pumpAndSettle();
      final calendar = tester.widget<CalendarDatePicker>(
        find.byType(CalendarDatePicker),
      );
      calendar.onDateChanged(calendar.initialDate!);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('membership-operation-submit')),
      );
      await tester.tap(
        find.byKey(const ValueKey('membership-operation-submit')),
      );
      await tester.pumpAndSettle();
      final dialog = find.byType(AppConfirmationDialog);
      expect(dialog, findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.descendant(of: dialog, matching: find.byType(FilledButton)),
      );
      expect(button.style!.backgroundColor!.resolve({}), AppColors.primary);
      final icon = tester.widget<Icon>(
        find.descendant(
          of: dialog,
          matching: find.byIcon(Icons.event_repeat_rounded),
        ),
      );
      expect(icon.color, AppColors.primary);
      final container = tester.widget<Container>(
        find
            .ancestor(
              of: find.descendant(
                of: dialog,
                matching: find.byIcon(Icons.event_repeat_rounded),
              ),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(
        (container.decoration! as BoxDecoration).color,
        AppColors.primary.withValues(alpha: 0.12),
      );
      expect(source.expirationCalls, 0);
    },
  );

  test('human errors cover chained Unlimited and invalid expiration', () {
    expect(
      membershipOperationError(Exception('scheduled_unlimited_chain_conflict')),
      contains('linked to a later scheduled membership'),
    );
    expect(
      membershipOperationError(Exception('expiration_must_be_future')),
      contains('use Cancel membership'),
    );
  });

  testWidgets('Spanish operation copy is localized', (tester) async {
    await localeController.setLanguage('es');
    final source = _FakeOperations(preview(status: 'expired'));
    await _pumpForm(
      tester,
      operation: MembershipAdminOperation.changeExpiration,
      source: source,
    );
    expect(find.text('¿CAMBIAR VENCIMIENTO?'), findsOne);
    expect(find.textContaining('Vencimiento actual'), findsOne);
    expect(find.text('ELEGIR NUEVA FECHA'), findsOne);
    expect(find.text('Motivo'), findsOne);
  });
}
