class ChecklistList {
  const ChecklistList({
    required this.id,
    required this.name,
    required this.owner,
    required this.sharedCount,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String name;
  final String owner;
  final int sharedCount;
  final int createdAt;
  final int updatedAt;

  factory ChecklistList.fromJson(Map<String, dynamic> json) {
    return ChecklistList(
      id: _parseInt(json['id']) ?? 0,
      name: (json['name'] ?? '').toString(),
      owner: (json['owner'] ?? '').toString(),
      sharedCount: _parseInt(json['sharedCount'] ?? json['shared_count']) ?? 0,
      createdAt: _parseInt(json['createdAt'] ?? json['created_at']) ?? 0,
      updatedAt: _parseInt(json['updatedAt'] ?? json['updated_at']) ?? 0,
    );
  }
}

class ChecklistItem {
  const ChecklistItem({
    required this.id,
    required this.listId,
    required this.columnId,
    required this.title,
    required this.completed,
    required this.completedBy,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final int listId;
  final int? columnId;
  final String title;
  final bool completed;
  final String completedBy;
  final String notes;
  final int createdAt;
  final int updatedAt;

  factory ChecklistItem.fromJson(Map<String, dynamic> json) {
    return ChecklistItem(
      id: _parseInt(json['id']) ?? 0,
      listId: _parseInt(json['listId'] ?? json['list_id']) ?? 0,
      columnId: _parseInt(json['columnId'] ?? json['column_id']),
      title: (json['title'] ?? '').toString(),
      completed: json['completed'] == true || json['completed'] == 1,
      completedBy: (json['completedBy'] ?? json['completed_by'] ?? '').toString(),
      notes: (json['notes'] ?? '').toString(),
      createdAt: _parseInt(json['createdAt'] ?? json['created_at']) ?? 0,
      updatedAt: _parseInt(json['updatedAt'] ?? json['updated_at']) ?? 0,
    );
  }

  ChecklistItem copyWith({
    String? title,
    bool? completed,
    String? notes,
    int? updatedAt,
  }) {
    return ChecklistItem(
      id: id,
      listId: listId,
      columnId: columnId,
      title: title ?? this.title,
      completed: completed ?? this.completed,
      completedBy: completedBy,
      notes: notes ?? this.notes,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

int? _parseInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

