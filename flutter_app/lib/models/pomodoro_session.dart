class PomodoroSession {
  const PomodoroSession({
    required this.id,
    required this.taskId,
    required this.taskTitle,
    required this.startedAt,
    required this.endedAt,
    required this.durationMin,
  });

  final int id;
  final int? taskId;
  final String? taskTitle;
  final int? startedAt;
  final int endedAt;
  final int durationMin;

  factory PomodoroSession.fromJson(Map<String, dynamic> json) {
    return PomodoroSession(
      id: _parseInt(json['id']) ?? 0,
      taskId: _parseInt(json['taskId'] ?? json['task_id']),
      taskTitle: (json['taskTitle'] ?? json['task_title'])?.toString(),
      startedAt: _parseInt(json['startedAt'] ?? json['started_at']),
      endedAt: _parseInt(json['endedAt'] ?? json['ended_at']) ?? 0,
      durationMin: _parseInt(json['durationMin'] ?? json['duration_min']) ?? 0,
    );
  }
}

int? _parseInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

