import 'package:ath615v2/core/theme/app_theme.dart';
import 'package:ath615v2/features/profile/data/gym_documents_repository.dart';
import 'package:ath615v2/features/profile/presentation/screens/gym_documents_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeDocumentsRepository implements GymDocumentsRepository {
  _FakeDocumentsRepository(this.rows);
  List<GymDocument> rows;
  int accepts = 0;
  int publishes = 0;
  int creates = 0;
  int updates = 0;

  @override
  Future<List<GymDocument>> listPublished() async => rows;
  @override
  Future<List<GymDocument>> listAdmin() async => rows;
  @override
  Future<List<GymDocument>> memberStatus(String memberId) async => rows;
  @override
  Future<void> accept(String versionId, {String source = 'profile'}) async {
    accepts++;
  }

  @override
  Future<void> archive(String documentId) async {}
  @override
  Future<void> deleteDraft(String versionId) async {}
  @override
  Future<String> create({
    required String title,
    required String body,
    required String mode,
  }) async {
    creates++;
    return 'version-new';
  }

  @override
  Future<String> createVersion(String documentId) async => 'version-new';
  @override
  Future<void> publish(String versionId) async {
    publishes++;
  }

  @override
  Future<void> updateDraft(
    String versionId, {
    required String title,
    required String body,
    required String mode,
  }) async {
    updates++;
  }
}

GymDocument _document({
  bool accepted = false,
  String mode = 'required',
  String status = 'published',
}) => GymDocument(
  data: {
    'documentId': 'document-1',
    'versionId': 'version-1',
    'title': 'Gym rules',
    'body': 'Be kind and arrive on time.',
    'versionNumber': 2,
    'acceptanceMode': mode,
    'status': status,
    'accepted': accepted,
  },
);

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(320, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: child));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('athlete sees pending and accepts current required version', (
    tester,
  ) async {
    final repository = _FakeDocumentsRepository([_document()]);
    await _pump(tester, GymDocumentsScreen(repository: repository));
    expect(find.text('Gym rules'), findsOneWidget);
    expect(find.textContaining('Pending'), findsOneWidget);
    await tester.tap(find.text('Gym rules'));
    await tester.pumpAndSettle();
    expect(find.text('Be kind and arrive on time.'), findsOneWidget);
    await tester.tap(find.text('ACCEPT'));
    await tester.pumpAndSettle();
    expect(repository.accepts, 1);
    expect(find.text('Document accepted.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('informational document has no acceptance CTA', (tester) async {
    final repository = _FakeDocumentsRepository([
      _document(mode: 'informational'),
    ]);
    await _pump(tester, GymDocumentsScreen(repository: repository));
    await tester.tap(find.text('Gym rules'));
    await tester.pumpAndSettle();
    expect(find.text('ACCEPT'), findsNothing);
  });

  testWidgets('admin sees create and immutable published actions at 320px', (
    tester,
  ) async {
    final repository = _FakeDocumentsRepository([_document()]);
    await _pump(
      tester,
      GymDocumentsScreen(admin: true, repository: repository),
    );
    expect(find.byKey(const ValueKey('add-gym-document')), findsOneWidget);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('New version'), findsOneWidget);
    expect(find.text('Edit document'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('admin creates and saves a non-empty draft', (tester) async {
    final repository = _FakeDocumentsRepository([]);
    await _pump(
      tester,
      GymDocumentsScreen(admin: true, repository: repository),
    );
    await tester.tap(find.byKey(const ValueKey('add-gym-document')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Code of conduct');
    await tester.enterText(find.byType(TextField).at(1), 'Respect everyone.');
    await tester.tap(find.text('SAVE DRAFT'));
    await tester.pumpAndSettle();
    expect(repository.creates, 1);
  });

  testWidgets('admin edits then publishes a draft with confirmation', (
    tester,
  ) async {
    final repository = _FakeDocumentsRepository([_document(status: 'draft')]);
    await _pump(
      tester,
      GymDocumentsScreen(admin: true, repository: repository),
    );
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit document'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('PUBLISH DOCUMENT'),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('PUBLISH DOCUMENT'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('cannot be modified'), findsOneWidget);
    await tester.tap(find.text('Publish'));
    await tester.pumpAndSettle();
    expect(repository.updates, 1);
    expect(repository.publishes, 1);
  });

  testWidgets('member detail reports accepted and outdated states', (
    tester,
  ) async {
    final outdated = GymDocument(
      data: {..._document().data, 'accepted': false, 'outdated': true},
    );
    await _pump(
      tester,
      Scaffold(
        body: MemberDocumentsSection(
          memberUserId: 'member-1',
          repository: _FakeDocumentsRepository([outdated]),
        ),
      ),
    );
    expect(find.text('New version pending'), findsOneWidget);
  });
}
