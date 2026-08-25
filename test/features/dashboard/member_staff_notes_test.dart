import 'package:ath615v2/core/theme/app_theme.dart';
import 'package:ath615v2/core/widgets/app_form_visuals.dart';
import 'package:ath615v2/features/dashboard/data/member_staff_notes_repository.dart';
import 'package:ath615v2/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:ath615v2/features/dashboard/presentation/widgets/member_staff_notes_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('member notes empty state creates, edits, pins and deletes', (
    tester,
  ) async {
    final repository = _FakeNotesRepository();
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(repository: repository));
    await tester.pumpAndSettle();
    expect(find.text('No internal notes'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('add-member-staff-note')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('member-staff-note-body')),
      'Preparing HYROX in October',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('member-staff-note-pinned')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('save-member-staff-note')),
    );
    expect(
      tester
          .widget<AppFormSubmitButton>(
            find.byKey(const ValueKey('save-member-staff-note')),
          )
          .enabled,
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey('save-member-staff-note')));
    await tester.pumpAndSettle();

    expect(find.text('Preparing HYROX in October'), findsOneWidget);
    expect(repository.notes.single.isPinned, isTrue);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit note'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('member-staff-note-body')),
      'HYROX race in October',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('save-member-staff-note')),
    );
    await tester.tap(find.byKey(const ValueKey('save-member-staff-note')));
    await tester.pumpAndSettle();
    expect(find.text('HYROX race in October'), findsOneWidget);

    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete note'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('No internal notes'), findsOneWidget);
  });

  testWidgets('read-only staff sees notes without write actions', (
    tester,
  ) async {
    final repository = _FakeNotesRepository()
      ..notes.add(_note(body: 'Operational context', pinned: true));
    await tester.pumpWidget(_app(repository: repository, canManage: false));
    await tester.pumpAndSettle();

    expect(find.text('Operational context'), findsOneWidget);
    expect(find.byKey(const ValueKey('add-member-staff-note')), findsNothing);
    expect(find.byTooltip('Actions'), findsNothing);
  });

  testWidgets('briefing combines automatic insight with only pinned note', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: buildTodayClassBriefingForTest(
            klass: const {
              'programs': {'name': 'CrossFit'},
            },
            bookings: const [
              {'user_id': 'member-1'},
            ],
            waitlist: const [],
            membersById: const {
              'member-1': {
                'id': 'member-1',
                'full_name': 'Juan Pérez',
                'membership_type': 'pack',
                'credits_remaining': 10,
              },
            },
            attendedCounts: const {'member-1': 0},
            pinnedNotesByMember: const {
              'member-1': 'Preparing HYROX in October',
            },
          ),
        ),
      ),
    );

    expect(find.text('FIRST CLASS'), findsOneWidget);
    expect(find.text('Preparing HYROX in October'), findsOneWidget);
    expect(find.text('A normal note must stay hidden'), findsNothing);
  });

  test(
    'briefing pinned notes are resolved in one deduplicated batch',
    () async {
      final repository = _FakeNotesRepository();
      await loadBriefingPinnedNotes(repository, const [
        'member-1',
        'member-2',
        'member-1',
      ]);
      expect(repository.batchCalls, 1);
      expect(repository.lastBatch, unorderedEquals(['member-1', 'member-2']));
    },
  );
}

Widget _app({
  required _FakeNotesRepository repository,
  bool canManage = true,
}) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: MemberStaffNotesSection(
        memberUserId: 'member-1',
        repository: repository,
        canManage: canManage,
      ),
    ),
  ),
);

MemberStaffNote _note({
  String id = 'note-1',
  required String body,
  bool pinned = false,
}) => MemberStaffNote(
  id: id,
  memberUserId: 'member-1',
  body: body,
  isPinned: pinned,
  authorName: 'Admin User',
  createdAt: DateTime(2026, 8, 25),
  updatedAt: DateTime(2026, 8, 25),
);

class _FakeNotesRepository implements MemberStaffNotesRepository {
  final notes = <MemberStaffNote>[];
  int batchCalls = 0;
  List<String> lastBatch = const [];

  @override
  Future<void> delete(String noteId) async {
    notes.removeWhere((note) => note.id == noteId);
  }

  @override
  Future<List<MemberStaffNote>> listForMember(String memberUserId) async =>
      List.of(notes);

  @override
  Future<Map<String, String>> listPinnedForMembers(
    List<String> memberUserIds,
  ) async {
    batchCalls++;
    lastBatch = List.of(memberUserIds);
    return {
      for (final note in notes.where((note) => note.isPinned))
        note.memberUserId: note.body,
    };
  }

  @override
  Future<void> save({
    required String memberUserId,
    required String body,
    required bool isPinned,
    String? noteId,
  }) async {
    if (isPinned) {
      for (var index = 0; index < notes.length; index++) {
        final note = notes[index];
        notes[index] = _note(id: note.id, body: note.body);
      }
    }
    notes.removeWhere((note) => note.id == noteId);
    notes.add(
      _note(
        id: noteId ?? 'note-${notes.length + 1}',
        body: body,
        pinned: isPinned,
      ),
    );
  }
}
