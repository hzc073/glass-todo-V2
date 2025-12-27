import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/time_activity.dart';
import 'api_client.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  throw UnimplementedError('apiClientProvider must be overridden');
});

final timeRepositoryProvider = Provider<TimeRepository>((ref) {
  return TimeRepository(apiClient: ref.watch(apiClientProvider));
});

final timeActivitiesProvider = FutureProvider<List<TimeActivity>>((ref) async {
  final repo = ref.watch(timeRepositoryProvider);
  return repo.fetchActivities();
});

@immutable
class ActivityTotalQuery {
  const ActivityTotalQuery({
    required this.activityId,
    required this.fromMs,
    required this.toMs,
  });

  final String activityId;
  final int fromMs;
  final int toMs;

  @override
  bool operator ==(Object other) {
    return other is ActivityTotalQuery &&
        other.activityId == activityId &&
        other.fromMs == fromMs &&
        other.toMs == toMs;
  }

  @override
  int get hashCode => Object.hash(activityId, fromMs, toMs);
}

final activityTotalDurationMsProvider =
    FutureProvider.family<int, ActivityTotalQuery>((ref, query) async {
  final repo = ref.watch(timeRepositoryProvider);
  return repo.fetchActivityTotalDurationMs(query);
});

class TimeRepository {
  const TimeRepository({required this.apiClient});

  final ApiClient apiClient;

  Future<List<TimeActivity>> fetchActivities() async {
    final activities = await apiClient.getActivities();
    final active = activities.where((item) => item.deletedAt == null).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return active;
  }

  Future<int> fetchActivityTotalDurationMs(ActivityTotalQuery query) async {
    final fromMs = query.fromMs;
    final toMs = query.toMs;
    if (query.activityId.trim().isEmpty) return 0;
    if (toMs <= fromMs) return 0;

    const pageSize = 200;
    var offset = 0;
    var totalMs = 0;
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    while (true) {
      final page = await apiClient.getEntries(
        from: fromMs,
        to: toMs,
        activityId: query.activityId,
        limit: pageSize,
        offset: offset,
      );
      if (page.isEmpty) break;

      for (final entry in page) {
        if (entry.deletedAt != null) continue;

        final startedAt = entry.startedAt;
        final endedAt = entry.endedAt ??
            nowMs; // If still running, count until now for a real-time preview.

        final segStart = math.max(startedAt, fromMs);
        final segEnd = math.min(endedAt, toMs);
        if (segEnd <= segStart) continue;
        totalMs += segEnd - segStart;
      }

      if (page.length < pageSize) break;
      offset += page.length;

      // Safety guard for unexpected huge data sets.
      if (offset > 20000) break;
    }

    return totalMs;
  }
}
