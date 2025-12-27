class PomodoroSettings {
  const PomodoroSettings({
    required this.workMin,
    required this.shortBreakMin,
    required this.longBreakMin,
    required this.longBreakEvery,
    required this.autoStartNext,
    required this.autoStartBreak,
    required this.autoStartWork,
    required this.autoFinishTask,
  });

  final int workMin;
  final int shortBreakMin;
  final int longBreakMin;
  final int longBreakEvery;
  final bool autoStartNext;
  final bool autoStartBreak;
  final bool autoStartWork;
  final bool autoFinishTask;

  factory PomodoroSettings.fromJson(Map<String, dynamic> json) {
    return PomodoroSettings(
      workMin: _parseInt(json['workMin'] ?? json['work_min']) ?? 25,
      shortBreakMin: _parseInt(json['shortBreakMin'] ?? json['short_break_min']) ?? 5,
      longBreakMin: _parseInt(json['longBreakMin'] ?? json['long_break_min']) ?? 15,
      longBreakEvery: _parseInt(json['longBreakEvery'] ?? json['long_break_every']) ?? 4,
      autoStartNext: json['autoStartNext'] == true || json['auto_start_next'] == 1,
      autoStartBreak: json['autoStartBreak'] == true || json['auto_start_break'] == 1,
      autoStartWork: json['autoStartWork'] == true || json['auto_start_work'] == 1,
      autoFinishTask: json['autoFinishTask'] == true || json['auto_finish_task'] == 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'workMin': workMin,
      'shortBreakMin': shortBreakMin,
      'longBreakMin': longBreakMin,
      'longBreakEvery': longBreakEvery,
      'autoStartNext': autoStartNext,
      'autoStartBreak': autoStartBreak,
      'autoStartWork': autoStartWork,
      'autoFinishTask': autoFinishTask,
    };
  }

  PomodoroSettings copyWith({
    int? workMin,
    int? shortBreakMin,
    int? longBreakMin,
    int? longBreakEvery,
    bool? autoStartNext,
    bool? autoStartBreak,
    bool? autoStartWork,
    bool? autoFinishTask,
  }) {
    return PomodoroSettings(
      workMin: workMin ?? this.workMin,
      shortBreakMin: shortBreakMin ?? this.shortBreakMin,
      longBreakMin: longBreakMin ?? this.longBreakMin,
      longBreakEvery: longBreakEvery ?? this.longBreakEvery,
      autoStartNext: autoStartNext ?? this.autoStartNext,
      autoStartBreak: autoStartBreak ?? this.autoStartBreak,
      autoStartWork: autoStartWork ?? this.autoStartWork,
      autoFinishTask: autoFinishTask ?? this.autoFinishTask,
    );
  }
}

int? _parseInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

