class TimeActivity {
  TimeActivity({
    required this.id,
    required this.name,
    required this.taskId,
    required this.icon,
    required this.color,
    required this.category,
    required this.goal,
    required this.note,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
  });

  final String id;
  final String name;
  final String? taskId;
  final String icon;
  final String color;
  final String category;
  final String goal;
  final String note;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;

  factory TimeActivity.fromJson(Map<String, dynamic> json) {
    return TimeActivity(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      taskId: (json['taskId'] ?? json['task_id'])?.toString(),
      icon: (json['icon'] ?? '').toString(),
      color: (json['color'] ?? '').toString(),
      category: (json['category'] ?? '').toString(),
      goal: (json['goal'] ?? '').toString(),
      note: (json['note'] ?? '').toString(),
      createdAt: _parseInt(json['createdAt'] ?? json['created_at']) ?? 0,
      updatedAt: _parseInt(json['updatedAt'] ?? json['updated_at']) ?? 0,
      deletedAt: _parseInt(json['deletedAt'] ?? json['deleted_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'taskId': taskId,
      'icon': icon,
      'color': color,
      'category': category,
      'goal': goal,
      'note': note,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'deletedAt': deletedAt,
    };
  }

  static int? _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}
