class HolidayCnDay {
  const HolidayCnDay({
    required this.name,
    required this.date,
    required this.isOffDay,
  });

  final String name;
  /// yyyy-MM-dd
  final String date;
  /// true = 休，false = 班（调休上班）
  final bool isOffDay;

  factory HolidayCnDay.fromJson(Map<String, dynamic> json) {
    return HolidayCnDay(
      name: (json['name'] ?? '').toString(),
      date: (json['date'] ?? '').toString(),
      isOffDay: json['isOffDay'] == true,
    );
  }
}

class HolidayCnYear {
  const HolidayCnYear({
    required this.year,
    required this.days,
  });

  final int year;
  final List<HolidayCnDay> days;

  factory HolidayCnYear.fromJson(Map<String, dynamic> json) {
    final rawYear = json['year'];
    final year = rawYear is int ? rawYear : int.tryParse(rawYear?.toString() ?? '') ?? 0;
    final list = json['days'];
    final days = list is List
        ? list.whereType<Map<String, dynamic>>().map(HolidayCnDay.fromJson).toList()
        : <HolidayCnDay>[];
    return HolidayCnYear(year: year, days: days);
  }

  Map<String, HolidayCnDay> get byDate {
    final map = <String, HolidayCnDay>{};
    for (final day in days) {
      if (day.date.isEmpty) continue;
      map[day.date] = day;
    }
    return map;
  }
}

