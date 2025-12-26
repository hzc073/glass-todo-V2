class PomodoroDaySummary {
  const PomodoroDaySummary({
    required this.workSessions,
    required this.workMinutes,
    required this.breakMinutes,
  });

  final int workSessions;
  final int workMinutes;
  final int breakMinutes;

  factory PomodoroDaySummary.fromJson(Map<String, dynamic> json) {
    return PomodoroDaySummary(
      workSessions: _parseInt(json['workSessions'] ?? json['work_sessions']) ?? 0,
      workMinutes: _parseInt(json['workMinutes'] ?? json['work_minutes']) ?? 0,
      breakMinutes: _parseInt(json['breakMinutes'] ?? json['break_minutes']) ?? 0,
    );
  }
}

class PomodoroSummary {
  const PomodoroSummary({
    required this.totalWorkSessions,
    required this.totalWorkMinutes,
    required this.totalBreakMinutes,
    required this.days,
  });

  final int totalWorkSessions;
  final int totalWorkMinutes;
  final int totalBreakMinutes;
  final Map<String, PomodoroDaySummary> days;

  factory PomodoroSummary.fromJson(Map<String, dynamic> json) {
    final totals = json['totals'];
    final totalsMap = totals is Map<String, dynamic> ? totals : <String, dynamic>{};

    final daysRaw = json['days'];
    final daysMap = <String, PomodoroDaySummary>{};
    if (daysRaw is Map) {
      for (final entry in daysRaw.entries) {
        final key = entry.key?.toString();
        final value = entry.value;
        if (key == null || key.isEmpty) continue;
        if (value is Map<String, dynamic>) {
          daysMap[key] = PomodoroDaySummary.fromJson(value);
        } else if (value is Map) {
          daysMap[key] = PomodoroDaySummary.fromJson(value.cast<String, dynamic>());
        }
      }
    }

    return PomodoroSummary(
      totalWorkSessions: _parseInt(totalsMap['totalWorkSessions']) ?? 0,
      totalWorkMinutes: _parseInt(totalsMap['totalWorkMinutes']) ?? 0,
      totalBreakMinutes: _parseInt(totalsMap['totalBreakMinutes']) ?? 0,
      days: daysMap,
    );
  }
}

int? _parseInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

