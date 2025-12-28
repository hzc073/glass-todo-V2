enum PomodoroMode {
  work,
  shortBreak,
  longBreak,
}

extension PomodoroModeMeta on PomodoroMode {
  String get key {
    switch (this) {
      case PomodoroMode.work:
        return 'work';
      case PomodoroMode.shortBreak:
        return 'short';
      case PomodoroMode.longBreak:
        return 'long';
    }
  }

  String get label {
    switch (this) {
      case PomodoroMode.work:
        return '专注';
      case PomodoroMode.shortBreak:
        return '短休';
      case PomodoroMode.longBreak:
        return '长休';
    }
  }

  static PomodoroMode parse(String? value) {
    switch ((value ?? '').trim()) {
      case 'short':
        return PomodoroMode.shortBreak;
      case 'long':
        return PomodoroMode.longBreak;
      case 'work':
      default:
        return PomodoroMode.work;
    }
  }
}

class PomodoroState {
  const PomodoroState({
    required this.mode,
    required this.remainingMs,
    required this.isRunning,
    required this.targetEnd,
    required this.cycleCount,
    required this.currentTaskId,
  });

  final PomodoroMode mode;
  final int remainingMs;
  final bool isRunning;
  final int? targetEnd;
  final int cycleCount;
  final int? currentTaskId;

  factory PomodoroState.fromJson(Map<String, dynamic> json) {
    final targetEnd = _parseInt(json['targetEnd'] ?? json['target_end']);
    final currentTaskId = _parseInt(json['currentTaskId'] ?? json['current_task_id']);
    return PomodoroState(
      mode: PomodoroModeMeta.parse(json['mode']?.toString()),
      remainingMs: _parseInt(json['remainingMs'] ?? json['remaining_ms']) ?? 0,
      isRunning: json['isRunning'] == true || json['is_running'] == 1,
      targetEnd: targetEnd == null || targetEnd <= 0 ? null : targetEnd,
      cycleCount: _parseInt(json['cycleCount'] ?? json['cycle_count']) ?? 0,
      currentTaskId: currentTaskId == null || currentTaskId <= 0 ? null : currentTaskId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'mode': mode.key,
      'remainingMs': remainingMs,
      'isRunning': isRunning,
      'targetEnd': targetEnd,
      'cycleCount': cycleCount,
      'currentTaskId': currentTaskId,
    };
  }

  PomodoroState copyWith({
    PomodoroMode? mode,
    int? remainingMs,
    bool? isRunning,
    int? targetEnd,
    bool clearTargetEnd = false,
    int? cycleCount,
    int? currentTaskId,
  }) {
    return PomodoroState(
      mode: mode ?? this.mode,
      remainingMs: remainingMs ?? this.remainingMs,
      isRunning: isRunning ?? this.isRunning,
      targetEnd: clearTargetEnd ? null : (targetEnd ?? this.targetEnd),
      cycleCount: cycleCount ?? this.cycleCount,
      currentTaskId: currentTaskId ?? this.currentTaskId,
    );
  }

  static PomodoroState initial() {
    return const PomodoroState(
      mode: PomodoroMode.work,
      remainingMs: 25 * 60 * 1000,
      isRunning: false,
      targetEnd: null,
      cycleCount: 0,
      currentTaskId: null,
    );
  }
}

int? _parseInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}
