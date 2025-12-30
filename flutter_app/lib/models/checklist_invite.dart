class ChecklistInvite {
  const ChecklistInvite({
    required this.id,
    required this.listId,
    required this.listName,
    required this.listOwner,
    required this.inviter,
    required this.inviteeKey,
    required this.inviteeDisplay,
    required this.role,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.expiresAt,
    required this.respondedAt,
  });

  final int id;
  final int listId;
  final String listName;
  final String listOwner;
  final String inviter;
  final String inviteeKey;
  final String inviteeDisplay;
  final String role;
  final String status;
  final int createdAt;
  final int updatedAt;
  final int expiresAt;
  final int? respondedAt;

  factory ChecklistInvite.fromJson(Map<String, dynamic> json) {
    return ChecklistInvite(
      id: _parseInt(json['id']) ?? 0,
      listId: _parseInt(json['listId'] ?? json['list_id']) ?? 0,
      listName: (json['listName'] ?? json['list_name'] ?? '').toString(),
      listOwner: (json['listOwner'] ?? json['list_owner'] ?? '').toString(),
      inviter: (json['inviter'] ?? '').toString(),
      inviteeKey: (json['inviteeKey'] ?? json['invitee_key'] ?? '').toString(),
      inviteeDisplay: (json['inviteeDisplay'] ?? json['invitee_display'] ?? '').toString(),
      role: (json['role'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      createdAt: _parseInt(json['createdAt'] ?? json['created_at']) ?? 0,
      updatedAt: _parseInt(json['updatedAt'] ?? json['updated_at']) ?? 0,
      expiresAt: _parseInt(json['expiresAt'] ?? json['expires_at']) ?? 0,
      respondedAt: _parseInt(json['respondedAt'] ?? json['responded_at']),
    );
  }
}

int? _parseInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

