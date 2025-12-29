class TimeStats {
  TimeStats({
    required this.from,
    required this.to,
    required this.tzOffsetMinutes,
    required this.totalMs,
    required this.untrackedMs,
    required this.byDay,
    required this.byActivity,
    required this.byCategory,
  });

  final int from;
  final int to;
  final int tzOffsetMinutes;
  final int totalMs;
  final int untrackedMs;
  final Map<String, int> byDay;
  final Map<String, int> byActivity;
  final Map<String, int> byCategory;

  factory TimeStats.fromJson(Map<String, dynamic> json) {
    final range = json['range'] is Map<String, dynamic> ? json['range'] as Map<String, dynamic> : {};
    final totals = json['totals'] is Map<String, dynamic> ? json['totals'] as Map<String, dynamic> : {};
    return TimeStats(
      from: _parseInt(range['from']) ?? 0,
      to: _parseInt(range['to']) ?? 0,
      tzOffsetMinutes: _parseInt(json['tzOffsetMinutes'] ?? json['tz_offset_minutes']) ?? 0,
      totalMs: _parseInt(totals['totalMs']) ?? 0,
      untrackedMs: _parseInt(totals['untrackedMs'] ?? totals['untracked_ms']) ?? 0,
      byDay: _parseIntMap(json['byDay']),
      byActivity: _parseIntMap(json['byActivity']),
      byCategory: _parseIntMap(json['byCategory'] ?? json['by_category']),
    );
  }

  static Map<String, int> _parseIntMap(dynamic value) {
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), _parseInt(val) ?? 0));
    }
    return <String, int>{};
  }

  static int? _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}
