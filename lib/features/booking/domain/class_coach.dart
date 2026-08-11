class ClassCoachOption {
  const ClassCoachOption({required this.id, required this.name});

  final String id;
  final String name;

  static ClassCoachOption? fromRpcRow(Map<String, dynamic> row) {
    final id = row['coach_id']?.toString().trim() ?? '';
    final name = row['coach_name']?.toString().trim() ?? '';
    if (id.isEmpty || name.isEmpty) return null;
    return ClassCoachOption(id: id, name: name);
  }
}

Map<String, dynamic> withClassCoach(
  Map<String, dynamic> payload,
  String? coachId,
) {
  return {...payload, 'coach_id': coachId};
}

Map<String, dynamic> withRecurringClassCoach(
  Map<String, dynamic> params,
  String? coachId,
) {
  return {...params, 'p_coach_id': coachId};
}
