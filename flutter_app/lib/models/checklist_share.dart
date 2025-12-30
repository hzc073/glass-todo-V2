class ChecklistMember {
  const ChecklistMember({
    required this.user,
    required this.canEdit,
    required this.createdAt,
  });

  final String user;
  final bool canEdit;
  final int createdAt;

  factory ChecklistMember.fromJson(Map<String, dynamic> json) {
    return ChecklistMember(
      user: (json['user'] ?? '').toString(),
      canEdit: json['canEdit'] == true || json['canEdit'] == 1,
      createdAt: _parseInt(json['createdAt'] ?? json['created_at']) ?? 0,
    );
  }
}

class ChecklistShareInfo {
  const ChecklistShareInfo({
    required this.owner,
    required this.readonly,
    required this.shared,
  });

  final String owner;
  final bool readonly;
  final List<ChecklistMember> shared;

  factory ChecklistShareInfo.fromJson(Map<String, dynamic> json) {
    final list = json['shared'];
    return ChecklistShareInfo(
      owner: (json['owner'] ?? '').toString(),
      readonly: json['readonly'] == true,
      shared: list is List
          ? list
              .whereType<Map>()
              .map((row) => ChecklistMember.fromJson(row.cast<String, dynamic>()))
              .toList()
          : <ChecklistMember>[],
    );
  }
}

int? _parseInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

