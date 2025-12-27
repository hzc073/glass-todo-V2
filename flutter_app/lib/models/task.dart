class Task {
  Task({
    required this.id,
    required this.title,
    required this.notes,
    required this.status,
    required this.dueDate,
    required this.startTime,
    required this.endTime,
    required this.tags,
    required this.inbox,
    required this.priority,
    required this.remindAt,
    required this.repeatRule,
    required this.attachments,
    required this.subtasks,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
    required this.owner,
  });

  final String id;
  final String title;
  final String notes;
  final String status;
  final String dueDate;
  final String startTime;
  final String endTime;
  final List<String> tags;
  final bool inbox;
  final int priority;
  final int? remindAt;
  final String repeatRule;
  final List<TaskAttachment> attachments;
  final List<TaskSubtask> subtasks;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;
  final String owner;

  bool get isCompleted => status == 'completed';

  static const String systemChecklistTagPrefix = '__sys_checklist:';
  static const String systemColorTagPrefix = '__sys_color:';

  int? get checklistId => Task._parseChecklistId(tags);
  String? get colorHex => Task._parseSystemColor(tags);

  List<String> get displayTags => Task.stripSystemTags(tags);

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      notes: (json['notes'] ?? '').toString(),
      status: (json['status'] ?? 'todo').toString(),
      dueDate: (json['dueDate'] ?? json['due_date'] ?? '').toString(),
      startTime: (json['startTime'] ?? json['start_time'] ?? '').toString(),
      endTime: (json['endTime'] ?? json['end_time'] ?? '').toString(),
      tags: _parseStringList(json['tags']),
      inbox: json['inbox'] == true || json['inbox'] == 1,
      priority: _parseInt(json['priority']) ?? 0,
      remindAt: _parseInt(json['remindAt'] ?? json['remind_at']),
      repeatRule: (json['repeatRule'] ?? json['repeat_rule'] ?? '').toString(),
      attachments: _parseAttachments(json['attachments']),
      subtasks: _parseSubtasks(json['subtasks']),
      createdAt: _parseInt(json['createdAt'] ?? json['created_at']) ?? 0,
      updatedAt: _parseInt(json['updatedAt'] ?? json['updated_at']) ?? 0,
      deletedAt: _parseInt(json['deletedAt'] ?? json['deleted_at']),
      owner: (json['owner'] ?? json['username'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'notes': notes,
      'status': status,
      'dueDate': dueDate,
      'startTime': startTime,
      'endTime': endTime,
      'tags': tags,
      'inbox': inbox,
      'priority': priority,
      'remindAt': remindAt,
      'repeatRule': repeatRule,
      'attachments': attachments.map((item) => item.toJson()).toList(),
      'subtasks': subtasks.map((item) => item.toJson()).toList(),
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'deletedAt': deletedAt,
      'owner': owner,
    };
  }

  Task copyWith({
    String? title,
    String? notes,
    String? status,
    String? dueDate,
    String? startTime,
    String? endTime,
    List<String>? tags,
    bool? inbox,
    int? priority,
    int? remindAt,
    String? repeatRule,
    List<TaskAttachment>? attachments,
    List<TaskSubtask>? subtasks,
    int? updatedAt,
    int? deletedAt,
  }) {
    return Task(
      id: id,
      title: title ?? this.title,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      dueDate: dueDate ?? this.dueDate,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      tags: tags ?? List<String>.from(this.tags),
      inbox: inbox ?? this.inbox,
      priority: priority ?? this.priority,
      remindAt: remindAt ?? this.remindAt,
      repeatRule: repeatRule ?? this.repeatRule,
      attachments: attachments ?? List<TaskAttachment>.from(this.attachments),
      subtasks: subtasks ?? List<TaskSubtask>.from(this.subtasks),
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      owner: owner,
    );
  }

  static int? _parseChecklistId(List<String> tags) {
    for (final tag in tags) {
      if (!tag.startsWith(systemChecklistTagPrefix)) continue;
      final raw = tag.substring(systemChecklistTagPrefix.length).trim();
      final id = int.tryParse(raw);
      if (id != null) return id;
    }
    return null;
  }

  static List<String> stripSystemChecklistTags(List<String> tags) {
    return tags.where((tag) => !tag.startsWith(systemChecklistTagPrefix)).toList();
  }

  static List<String> stripSystemColorTags(List<String> tags) {
    return tags.where((tag) => !tag.startsWith(systemColorTagPrefix)).toList();
  }

  static List<String> stripSystemTags(List<String> tags) {
    return tags
        .where(
          (tag) =>
              !tag.startsWith(systemChecklistTagPrefix) &&
              !tag.startsWith(systemColorTagPrefix),
        )
        .toList();
  }

  static List<String> applyChecklistTag(List<String> tags, int checklistId) {
    final stripped = stripSystemChecklistTags(tags);
    return [...stripped, '$systemChecklistTagPrefix$checklistId'];
  }

  static String? _parseSystemColor(List<String> tags) {
    for (final tag in tags) {
      if (!tag.startsWith(systemColorTagPrefix)) continue;
      final raw = tag.substring(systemColorTagPrefix.length).trim();
      if (raw.isEmpty) continue;
      return raw;
    }
    return null;
  }

  static List<String> applyColorTag(List<String> tags, String colorHex) {
    final stripped = stripSystemColorTags(tags);
    final normalized = colorHex.trim();
    if (normalized.isEmpty) return stripped;
    final value = normalized.startsWith('#') ? normalized : '#$normalized';
    return [...stripped, '$systemColorTagPrefix$value'];
  }

  static int? _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static List<String> _parseStringList(dynamic value) {
    if (value is List) {
      return value.map((item) => item.toString()).where((item) => item.isNotEmpty).toList();
    }
    return <String>[];
  }

  static List<TaskAttachment> _parseAttachments(dynamic value) {
    if (value is List) {
      return value
          .whereType<Map<String, dynamic>>()
          .map(TaskAttachment.fromJson)
          .toList();
    }
    return <TaskAttachment>[];
  }

  static List<TaskSubtask> _parseSubtasks(dynamic value) {
    if (value is List) {
      return value
          .whereType<Map<String, dynamic>>()
          .map(TaskSubtask.fromJson)
          .toList();
    }
    return <TaskSubtask>[];
  }
}

class TaskAttachment {
  const TaskAttachment({
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

  factory TaskAttachment.fromJson(Map<String, dynamic> json) {
    return TaskAttachment(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      mime: (json['mime'] ?? '').toString(),
      size: Task._parseInt(json['size']) ?? 0,
      createdAt: Task._parseInt(json['createdAt'] ?? json['created_at']) ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'mime': mime,
      'size': size,
      'createdAt': createdAt,
    };
  }
}

class TaskSubtask {
  const TaskSubtask({
    required this.id,
    required this.title,
    required this.completed,
  });

  final String id;
  final String title;
  final bool completed;

  TaskSubtask copyWith({
    String? title,
    bool? completed,
  }) {
    return TaskSubtask(
      id: id,
      title: title ?? this.title,
      completed: completed ?? this.completed,
    );
  }

  factory TaskSubtask.fromJson(Map<String, dynamic> json) {
    return TaskSubtask(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      completed: json['completed'] == true || json['completed'] == 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'completed': completed,
    };
  }
}
