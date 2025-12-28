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
    final taskId = _parseInt(json['taskId'] ?? json['task_id']);
    final startedAt = _parseInt(json['startedAt'] ?? json['started_at']);
    return PomodoroSession(
      id: _parseInt(json['id']) ?? 0,
      taskId: taskId == null || taskId <= 0 ? null : taskId,
      taskTitle: (json['taskTitle'] ?? json['task_title'])?.toString(),
      startedAt: startedAt == null || startedAt <= 0 ? null : startedAt,
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
