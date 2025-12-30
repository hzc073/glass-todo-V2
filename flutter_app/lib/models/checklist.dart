class ChecklistList {
  const ChecklistList({
    required this.id,
    required this.name,
    required this.owner,
    required this.role,
    required this.canEdit,
    required this.sharedCount,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String name;
  final String owner;
  final String role;
  final bool canEdit;
  final int sharedCount;
  final int createdAt;
  final int updatedAt;

  factory ChecklistList.fromJson(Map<String, dynamic> json) {
    return ChecklistList(
      id: _parseInt(json['id']) ?? 0,
      name: (json['name'] ?? '').toString(),
      owner: (json['owner'] ?? '').toString(),
      role: (json['role'] ?? '').toString(),
      canEdit: json['canEdit'] == true || json['canEdit'] == 1,
      sharedCount: _parseInt(json['sharedCount'] ?? json['shared_count']) ?? 0,
      createdAt: _parseInt(json['createdAt'] ?? json['created_at']) ?? 0,
      updatedAt: _parseInt(json['updatedAt'] ?? json['updated_at']) ?? 0,
    );
  }
}

class ChecklistItemAttachment {
  const ChecklistItemAttachment({
    required this.id,
    required this.name,
    required this.mime,
    required this.size,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String mime;
  final int size;
  final int createdAt;

  factory ChecklistItemAttachment.fromJson(Map<String, dynamic> json) {
    return ChecklistItemAttachment(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      mime: (json['mime'] ?? '').toString(),
      size: _parseInt(json['size']) ?? 0,
      createdAt: _parseInt(json['createdAt'] ?? json['created_at']) ?? 0,
    );
  }
}

class ChecklistSubtask {
  const ChecklistSubtask({
    required this.title,
    required this.completed,
    required this.note,
  });

  final String title;
  final bool completed;
  final String note;

  ChecklistSubtask copyWith({
    String? title,
    bool? completed,
    String? note,
  }) {
    return ChecklistSubtask(
      title: title ?? this.title,
      completed: completed ?? this.completed,
      note: note ?? this.note,
    );
  }

  factory ChecklistSubtask.fromJson(Map<String, dynamic> json) {
    return ChecklistSubtask(
      title: (json['title'] ?? json['text'] ?? '').toString(),
      completed: json['completed'] == true || json['completed'] == 1,
      note: (json['note'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'completed': completed,
      'note': note,
    };
  }
}

class ChecklistItem {
  const ChecklistItem({
    required this.id,
    required this.listId,
    required this.columnId,
    required this.title,
    required this.tags,
    required this.completed,
    required this.completedBy,
    required this.notes,
    required this.subtasks,
    required this.attachments,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final int listId;
  final int? columnId;
  final String title;
  final List<String> tags;
  final bool completed;
  final String completedBy;
  final String notes;
  final List<ChecklistSubtask> subtasks;
  final List<ChecklistItemAttachment> attachments;
  final int createdAt;
  final int updatedAt;

  factory ChecklistItem.fromJson(Map<String, dynamic> json) {
    final tagsRaw = json['tags'];
    final tags = tagsRaw is List
        ? tagsRaw.map((tag) => tag.toString()).where((tag) => tag.trim().isNotEmpty).toList()
        : <String>[];

    final subtasksRaw = json['subtasks'];
    final subtasks = subtasksRaw is List
        ? subtasksRaw.map((s) {
            if (s is Map<String, dynamic>) return ChecklistSubtask.fromJson(s);
            if (s is Map) return ChecklistSubtask.fromJson(s.cast<String, dynamic>());
            return ChecklistSubtask(title: s?.toString() ?? '', completed: false, note: '');
          }).where((s) => s.title.trim().isNotEmpty).toList()
        : <ChecklistSubtask>[];

    final attachmentsRaw = json['attachments'];
    final attachments = attachmentsRaw is List
        ? attachmentsRaw
            .where((row) => row is Map)
            .map((row) => ChecklistItemAttachment.fromJson(row.cast<String, dynamic>()))
            .toList()
        : <ChecklistItemAttachment>[];

    return ChecklistItem(
      id: _parseInt(json['id']) ?? 0,
      listId: _parseInt(json['listId'] ?? json['list_id']) ?? 0,
      columnId: _parseInt(json['columnId'] ?? json['column_id']),
      title: (json['title'] ?? '').toString(),
      tags: tags,
      completed: json['completed'] == true || json['completed'] == 1,
      completedBy: (json['completedBy'] ?? json['completed_by'] ?? '').toString(),
      notes: (json['notes'] ?? '').toString(),
      subtasks: subtasks,
      attachments: attachments,
      createdAt: _parseInt(json['createdAt'] ?? json['created_at']) ?? 0,
      updatedAt: _parseInt(json['updatedAt'] ?? json['updated_at']) ?? 0,
    );
  }

  ChecklistItem copyWith({
    int? columnId,
    String? title,
    List<String>? tags,
    bool? completed,
    String? completedBy,
    String? notes,
    List<ChecklistSubtask>? subtasks,
    List<ChecklistItemAttachment>? attachments,
    int? updatedAt,
  }) {
    return ChecklistItem(
      id: id,
      listId: listId,
      columnId: columnId ?? this.columnId,
      title: title ?? this.title,
      tags: tags ?? this.tags,
      completed: completed ?? this.completed,
      completedBy: completedBy ?? this.completedBy,
      notes: notes ?? this.notes,
      subtasks: subtasks ?? this.subtasks,
      attachments: attachments ?? this.attachments,
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
