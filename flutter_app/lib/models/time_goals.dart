class TimeGoalPeriod {
  const TimeGoalPeriod({
    required this.durationMs,
    required this.count,
  });

  final int durationMs;
  final int count;

  factory TimeGoalPeriod.fromJson(Map<String, dynamic> json) {
    return TimeGoalPeriod(
      durationMs: _parseInt(json['durationMs'] ?? json['duration_ms']) ?? 0,
      count: _parseInt(json['count']) ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'durationMs': durationMs,
        'count': count,
      };

  TimeGoalPeriod copyWith({int? durationMs, int? count}) {
    return TimeGoalPeriod(
      durationMs: durationMs ?? this.durationMs,
      count: count ?? this.count,
    );
  }
}

class TimeGoalPeriods {
  const TimeGoalPeriods({
    required this.daily,
    required this.weekly,
    required this.total,
  });

  final TimeGoalPeriod daily;
  final TimeGoalPeriod weekly;
  final TimeGoalPeriod total;

  factory TimeGoalPeriods.fromJson(Map<String, dynamic> json) {
    return TimeGoalPeriods(
      daily: TimeGoalPeriod.fromJson(_map(json['daily'])),
      weekly: TimeGoalPeriod.fromJson(_map(json['weekly'])),
      total: TimeGoalPeriod.fromJson(_map(json['total'])),
    );
  }

  Map<String, dynamic> toJson() => {
        'daily': daily.toJson(),
        'weekly': weekly.toJson(),
        'total': total.toJson(),
      };

  TimeGoalPeriods copyWith({
    TimeGoalPeriod? daily,
    TimeGoalPeriod? weekly,
    TimeGoalPeriod? total,
  }) {
    return TimeGoalPeriods(
      daily: daily ?? this.daily,
      weekly: weekly ?? this.weekly,
      total: total ?? this.total,
    );
  }
}

class TimeGoalItem {
  const TimeGoalItem({
    required this.activityId,
    required this.targets,
    required this.progress,
    required this.createdAt,
    required this.updatedAt,
  });

  final String activityId;
  final TimeGoalPeriods targets;
  final TimeGoalPeriods progress;
  final int createdAt;
  final int updatedAt;

  factory TimeGoalItem.fromJson(Map<String, dynamic> json) {
    return TimeGoalItem(
      activityId: (json['activityId'] ?? json['activity_id'] ?? '').toString(),
      targets: TimeGoalPeriods.fromJson(_map(json['targets'])),
      progress: TimeGoalPeriods.fromJson(_map(json['progress'])),
      createdAt: _parseInt(json['createdAt'] ?? json['created_at']) ?? 0,
      updatedAt: _parseInt(json['updatedAt'] ?? json['updated_at']) ?? 0,
    );
  }
}

class TimeGoalsSnapshot {
  const TimeGoalsSnapshot({
    required this.now,
    required this.tzOffsetMinutes,
    required this.weekStart,
    required this.dayFrom,
    required this.weekFrom,
    required this.goals,
  });

  final int now;
  final int tzOffsetMinutes;
  final String weekStart;
  final int dayFrom;
  final int weekFrom;
  final List<TimeGoalItem> goals;

  factory TimeGoalsSnapshot.fromJson(Map<String, dynamic> json) {
    final ranges = _map(json['ranges']);
    final day = _map(ranges['day']);
    final week = _map(ranges['week']);
    final goalsRaw = json['goals'];
    final parsedGoals = <TimeGoalItem>[];
    if (goalsRaw is List) {
      for (final item in goalsRaw) {
        if (item is Map<String, dynamic>) {
          parsedGoals.add(TimeGoalItem.fromJson(item));
        } else if (item is Map) {
          parsedGoals.add(TimeGoalItem.fromJson(item.cast<String, dynamic>()));
        }
      }
    }
    return TimeGoalsSnapshot(
      now: _parseInt(json['now']) ?? 0,
      tzOffsetMinutes:
          _parseInt(json['tzOffsetMinutes'] ?? json['tz_offset_minutes']) ?? 0,
      weekStart: (json['weekStart'] ?? json['week_start'] ?? 'monday').toString(),
      dayFrom: _parseInt(day['from']) ?? 0,
      weekFrom: _parseInt(week['from']) ?? 0,
      goals: parsedGoals,
    );
  }
}

Map<String, dynamic> _map(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  return <String, dynamic>{};
}

int? _parseInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

