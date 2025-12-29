class TimeStatsDetailBucket {
  TimeStatsDetailBucket({
    required this.totalMs,
    required this.count,
  });

  final int totalMs;
  final int count;

  factory TimeStatsDetailBucket.fromJson(Map<String, dynamic> json) {
    return TimeStatsDetailBucket(
      totalMs: _parseInt(json['totalMs'] ?? json['total_ms']) ?? 0,
      count: _parseInt(json['count']) ?? 0,
    );
  }

  static int? _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}

class TimeStatsDetail {
  TimeStatsDetail({
    required this.from,
    required this.to,
    required this.tzOffsetMinutes,
    required this.type,
    required this.id,
    required this.totalMs,
    required this.count,
    required this.byDay,
    required this.hourly,
    required this.weekday,
  });

  final int from;
  final int to;
  final int tzOffsetMinutes;
  final String type;
  final String id;
  final int totalMs;
  final int count;
  final Map<String, TimeStatsDetailBucket> byDay;
  final List<int> hourly;
  final List<int> weekday;

  factory TimeStatsDetail.fromJson(Map<String, dynamic> json) {
    final range =
        json['range'] is Map<String, dynamic> ? json['range'] as Map<String, dynamic> : {};
    final totals =
        json['totals'] is Map<String, dynamic> ? json['totals'] as Map<String, dynamic> : {};
    final filter =
        json['filter'] is Map<String, dynamic> ? json['filter'] as Map<String, dynamic> : {};

    return TimeStatsDetail(
      from: _parseInt(range['from']) ?? 0,
      to: _parseInt(range['to']) ?? 0,
      tzOffsetMinutes: _parseInt(json['tzOffsetMinutes'] ?? json['tz_offset_minutes']) ?? 0,
      type: (filter['type'] ?? '').toString(),
      id: (filter['id'] ?? '').toString(),
      totalMs: _parseInt(totals['totalMs'] ?? totals['total_ms']) ?? 0,
      count: _parseInt(totals['count']) ?? 0,
      byDay: _parseBucketMap(json['byDay'] ?? json['by_day']),
      hourly: _parseIntList(json['hourly']),
      weekday: _parseIntList(json['weekday']),
    );
  }

  static Map<String, TimeStatsDetailBucket> _parseBucketMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value.map((key, val) {
        final map = val is Map<String, dynamic>
            ? val
            : (val is Map ? val.cast<String, dynamic>() : <String, dynamic>{});
        return MapEntry(key, TimeStatsDetailBucket.fromJson(map));
      });
    }
    if (value is Map) {
      return value.cast<String, dynamic>().map((key, val) {
        final map = val is Map<String, dynamic>
            ? val
            : (val is Map ? val.cast<String, dynamic>() : <String, dynamic>{});
        return MapEntry(key, TimeStatsDetailBucket.fromJson(map));
      });
    }
    return <String, TimeStatsDetailBucket>{};
  }

  static List<int> _parseIntList(dynamic value) {
    if (value is List) {
      return value.map((item) => _parseInt(item) ?? 0).toList();
    }
    return <int>[];
  }

  static int? _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}
