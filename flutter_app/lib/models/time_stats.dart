class TimeStats {
  TimeStats({
    required this.from,
    required this.to,
    required this.totalMs,
    required this.byDay,
    required this.byActivity,
  });

  final int from;
  final int to;
  final int totalMs;
  final Map<String, int> byDay;
  final Map<String, int> byActivity;

  factory TimeStats.fromJson(Map<String, dynamic> json) {
    final range = json['range'] is Map<String, dynamic> ? json['range'] as Map<String, dynamic> : {};
    final totals = json['totals'] is Map<String, dynamic> ? json['totals'] as Map<String, dynamic> : {};
    return TimeStats(
      from: _parseInt(range['from']) ?? 0,
      to: _parseInt(range['to']) ?? 0,
      totalMs: _parseInt(totals['totalMs']) ?? 0,
      byDay: _parseIntMap(json['byDay']),
      byActivity: _parseIntMap(json['byActivity']),
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
