class TimeEntry {
  TimeEntry({
    required this.id,
    required this.activityId,
    required this.taskId,
    required this.startedAt,
    required this.endedAt,
    required this.durationMs,
    required this.note,
    required this.tags,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
  });

  final String id;
  final String activityId;
  final String? taskId;
  final int startedAt;
  final int? endedAt;
  final int? durationMs;
  final String note;
  final List<String> tags;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;

  bool get isRunning => endedAt == null;

  factory TimeEntry.fromJson(Map<String, dynamic> json) {
    final endedAt = _parseInt(json['endedAt'] ?? json['ended_at']);
    final deletedAt = _parseInt(json['deletedAt'] ?? json['deleted_at']);
    return TimeEntry(
      id: (json['id'] ?? '').toString(),
      activityId: (json['activityId'] ?? json['activity_id'] ?? '').toString(),
      taskId: (json['taskId'] ?? json['task_id'])?.toString(),
      startedAt: _parseInt(json['startedAt'] ?? json['started_at']) ?? 0,
      endedAt: endedAt == null || endedAt <= 0 ? null : endedAt,
      durationMs: _parseInt(json['durationMs'] ?? json['duration_ms']),
      note: (json['note'] ?? '').toString(),
      tags: _parseStringList(json['tags']),
      createdAt: _parseInt(json['createdAt'] ?? json['created_at']) ?? 0,
      updatedAt: _parseInt(json['updatedAt'] ?? json['updated_at']) ?? 0,
      deletedAt: deletedAt == null || deletedAt <= 0 ? null : deletedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'activityId': activityId,
      'taskId': taskId,
      'startedAt': startedAt,
      'endedAt': endedAt,
      'durationMs': durationMs,
      'note': note,
      'tags': tags,
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

  static List<String> _parseStringList(dynamic value) {
    if (value is List) {
      return value.map((item) => item.toString()).where((item) => item.isNotEmpty).toList();
    }
    return <String>[];
  }
}
