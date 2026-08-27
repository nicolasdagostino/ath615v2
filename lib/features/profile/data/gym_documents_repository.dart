import 'package:supabase_flutter/supabase_flutter.dart';

class GymDocument {
  GymDocument({required Map<String, dynamic> data}) : data = _normalize(data);

  final Map<String, dynamic> data;

  static Map<String, dynamic> _normalize(Map<String, dynamic> row) {
    final nested = Map<String, dynamic>.from(
      row['draftVersion'] as Map? ?? row['currentVersion'] as Map? ?? const {},
    );
    return {
      ...row,
      ...nested,
      'documentStatus': row['status'],
      'documentId': row['documentId'] ?? row['id'],
      'versionId': row['versionId'] ?? nested['id'],
      'versionNumber': row['versionNumber'] ?? nested['versionNumber'],
      'acceptanceMode': row['acceptanceMode'] ?? nested['acceptanceMode'],
      'accepted': row['accepted'] ?? row['acceptedAt'] != null,
      'outdated':
          row['outdated'] ??
          (row['acceptedAt'] == null && row['previousAcceptedAt'] != null),
    };
  }

  String get id => data['documentId']?.toString() ?? '';
  String? get versionId => data['versionId']?.toString();
  String get title => data['title']?.toString() ?? '';
  String get body => data['body']?.toString() ?? '';
  String get status => data['status']?.toString() ?? '';
  String get acceptanceMode => data['acceptanceMode']?.toString() ?? '';
  int get versionNumber => (data['versionNumber'] as num?)?.toInt() ?? 0;
  bool get required => acceptanceMode == 'required';
  bool get accepted => data['accepted'] == true;
  bool get outdated => data['outdated'] == true;
  String? get acceptedAt => data['acceptedAt']?.toString();
  String? get publishedAt => data['publishedAt']?.toString();
  String? get previousAcceptedAt => data['previousAcceptedAt']?.toString();
  int? get previousAcceptedVersionNumber =>
      (data['acceptedVersionNumber'] as num?)?.toInt();
  String get documentStatus => data['documentStatus']?.toString() ?? status;
}

abstract interface class GymDocumentsRepository {
  Future<List<GymDocument>> listPublished();
  Future<List<GymDocument>> listAdmin();
  Future<List<GymDocument>> memberStatus(String memberId);
  Future<void> accept(String versionId, {String source = 'profile'});
  Future<String> create({
    required String title,
    required String body,
    required String mode,
  });
  Future<void> updateDraft(
    String versionId, {
    required String title,
    required String body,
    required String mode,
  });
  Future<String> createVersion(String documentId);
  Future<void> publish(String versionId);
  Future<void> archive(String documentId);
  Future<void> deleteDraft(String versionId);
}

class SupabaseGymDocumentsRepository implements GymDocumentsRepository {
  const SupabaseGymDocumentsRepository(this.client);
  final SupabaseClient client;

  List<GymDocument> _rows(dynamic value) => List<Map<String, dynamic>>.from(
    value as List? ?? const [],
  ).map((row) => GymDocument(data: row)).toList();

  @override
  Future<List<GymDocument>> listPublished() async =>
      _rows(await client.rpc('list_effective_published_gym_documents'));

  @override
  Future<List<GymDocument>> listAdmin() async =>
      _rows(await client.rpc('list_effective_gym_documents_admin'));

  @override
  Future<List<GymDocument>> memberStatus(String memberId) async => _rows(
    await client.rpc(
      'get_effective_member_document_status',
      params: {'p_member_id': memberId},
    ),
  );

  @override
  Future<void> accept(String versionId, {String source = 'profile'}) =>
      client.rpc(
        'accept_effective_gym_document_version',
        params: {'p_version_id': versionId},
      );

  @override
  Future<String> create({
    required String title,
    required String body,
    required String mode,
  }) async => (await client.rpc(
    'create_effective_gym_document',
    params: {
      'p_title': title.trim(),
      'p_body': body.trim(),
      'p_acceptance_mode': mode,
    },
  )).toString();

  @override
  Future<void> updateDraft(
    String versionId, {
    required String title,
    required String body,
    required String mode,
  }) => client.rpc(
    'update_effective_gym_document_draft',
    params: {
      'p_version_id': versionId,
      'p_title': title.trim(),
      'p_body': body.trim(),
      'p_acceptance_mode': mode,
    },
  );

  @override
  Future<String> createVersion(String documentId) async => (await client.rpc(
    'create_effective_gym_document_version',
    params: {'p_document_id': documentId},
  )).toString();

  @override
  Future<void> publish(String versionId) => client.rpc(
    'publish_effective_gym_document_version',
    params: {'p_version_id': versionId},
  );

  @override
  Future<void> archive(String documentId) => client.rpc(
    'archive_effective_gym_document',
    params: {'p_document_id': documentId},
  );

  @override
  Future<void> deleteDraft(String versionId) => client.rpc(
    'delete_effective_gym_document_draft',
    params: {'p_version_id': versionId},
  );
}
