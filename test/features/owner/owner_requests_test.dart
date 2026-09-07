import 'package:ath615v2/features/owner/data/owner_requests_repository.dart';
import 'package:ath615v2/features/owner/presentation/screens/owner_requests_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeOwnerRequests implements OwnerRequestsDataSource {
  String? filter;
  String? updatedStatus;
  String? updatedNotes;
  @override
  Future<Map<String, dynamic>> list(String value) async {
    filter = value;
    return {
      'counts': {'new': 1, 'demo': 1, 'support': 1, 'other': 1},
      'items': [
        {
          'type': 'support',
          'id': '1',
          'full_name': 'Ada',
          'gym_name': 'A615 Box',
          'email': 'ada@example.com',
          'created_at': '2026-09-02',
          'status': 'new',
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> detail(String type, String id) async => {
    'type': type,
    'id': id,
    'full_name': 'Ada',
    'email': 'ada@example.com',
    'phone': '+34123456789',
    'issue_type': 'booking',
    'screen_name': 'Booking',
    'description': 'Failed booking',
    'app_version': '2.0.2',
    'build_number': '132',
    'platform': 'ios',
    'os_version': 'iOS',
    'locale': 'es',
    'status': 'new',
    'owner_notes': 'Private',
  };
  @override
  Future<void> update(
    String type,
    String id,
    String status,
    String notes,
  ) async {
    updatedStatus = status;
    updatedNotes = notes;
  }

  @override
  Future<String?> signedAttachment(String path) async => null;
}

void main() {
  testWidgets('Owner Requests shows KPIs filters and combined newest list', (
    t,
  ) async {
    final repo = FakeOwnerRequests();
    await t.pumpWidget(
      MaterialApp(home: OwnerRequestsScreen(repository: repo)),
    );
    await t.pumpAndSettle();
    for (final key in ['new', 'demo', 'support', 'other']) {
      expect(find.byKey(ValueKey('requests-kpi-$key')), findsOneWidget);
    }
    expect(
      find.byKey(const ValueKey('owner-request-support-1')),
      findsOneWidget,
    );
    await t.tap(find.byKey(const ValueKey('requests-filter-demo')));
    await t.pumpAndSettle();
    expect(repo.filter, 'demo');
  });
  testWidgets('Owner detail exposes support metadata and private workflow', (
    t,
  ) async {
    final repo = FakeOwnerRequests();
    await t.pumpWidget(
      MaterialApp(
        home: OwnerRequestDetailScreen(
          type: 'support',
          id: '1',
          repository: repo,
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Booking'), findsWidgets);
    expect(find.text('2.0.2'), findsOneWidget);
    await t.scrollUntilVisible(
      find.text('132'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('132'), findsOneWidget);
    await t.scrollUntilVisible(
      find.byKey(const ValueKey('owner-request-notes')),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.byKey(const ValueKey('owner-request-notes')), findsOneWidget);
    await t.enterText(
      find.byKey(const ValueKey('owner-request-notes')),
      'Resolved privately',
    );
    await t.ensureVisible(find.byKey(const ValueKey('owner-request-save')));
    t
        .widget<FilledButton>(find.byKey(const ValueKey('owner-request-save')))
        .onPressed!();
    await t.pump();
    expect(repo.updatedStatus, 'new');
    expect(repo.updatedNotes, 'Resolved privately');
  });
}
