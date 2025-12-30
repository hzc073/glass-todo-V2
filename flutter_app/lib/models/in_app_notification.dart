class InAppNotification {
  const InAppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.data,
    required this.createdAt,
    required this.readAt,
  });

  final int id;
  final String type;
  final String title;
  final String body;
  final Map<String, dynamic>? data;
  final int createdAt;
  final int? readAt;

  factory InAppNotification.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];
    return InAppNotification(
      id: _parseInt(json['id']) ?? 0,
      type: (json['type'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      body: (json['body'] ?? '').toString(),
      data: rawData is Map<String, dynamic>
          ? rawData
          : (rawData is Map ? rawData.cast<String, dynamic>() : null),
      createdAt: _parseInt(json['createdAt'] ?? json['created_at']) ?? 0,
      readAt: _parseInt(json['readAt'] ?? json['read_at']),
    );
  }
}

int? _parseInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

