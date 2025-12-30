class ChecklistLogEntry {
  const ChecklistLogEntry({
    required this.id,
    required this.listId,
    required this.actor,
    required this.type,
    required this.targetType,
    required this.targetId,
    required this.data,
    required this.createdAt,
  });

  final int id;
  final int listId;
  final String actor;
  final String type;
  final String? targetType;
  final String? targetId;
  final Map<String, dynamic>? data;
  final int createdAt;

  factory ChecklistLogEntry.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];
    return ChecklistLogEntry(
      id: _parseInt(json['id']) ?? 0,
      listId: _parseInt(json['listId'] ?? json['list_id']) ?? 0,
      actor: (json['actor'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
      targetType: (json['targetType'] ?? json['target_type'])?.toString(),
      targetId: (json['targetId'] ?? json['target_id'])?.toString(),
      data: rawData is Map<String, dynamic>
          ? rawData
          : (rawData is Map ? rawData.cast<String, dynamic>() : null),
      createdAt: _parseInt(json['createdAt'] ?? json['created_at']) ?? 0,
    );
  }
}

int? _parseInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

