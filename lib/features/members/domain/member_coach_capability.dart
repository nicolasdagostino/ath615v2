bool memberHasCoachCapability(Map<String, dynamic> member) {
  return member['is_coach'] == true || member['role']?.toString() == 'coach';
}

Map<String, dynamic> memberWithCoachCapability(
  Map<String, dynamic> member,
  bool isCoach,
) {
  return {...member, 'is_coach': isCoach};
}

Map<String, dynamic> memberWithRole(Map<String, dynamic> member, String role) {
  return {...member, 'role': role};
}
