import 'dart:convert';

import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/checklist.dart';
import '../models/holiday_cn.dart';
import '../models/pomodoro_session.dart';
import '../models/pomodoro_settings.dart';
import '../models/pomodoro_state.dart';
import '../models/pomodoro_summary.dart';
import '../models/task.dart';
import '../models/time_activity.dart';
import '../models/time_entry.dart';
import '../models/time_stats.dart';
import '../models/user_settings.dart';
import 'auth_store.dart';

class ApiException implements Exception {
  ApiException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'ApiException($statusCode): $body';
}

class UnauthorizedException extends ApiException {
  UnauthorizedException() : super(401, 'Unauthorized');
}

class ApiClient {
  ApiClient({required this.baseUrl, required this.authStore});

  final String baseUrl;
  final AuthStore authStore;

  Uri _uri(String path) {
    if (baseUrl.trim().isEmpty) {
      return Uri.base.resolve(path);
    }
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final normalized = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$normalized');
  }

  Map<String, String> _headers({bool json = true, Map<String, String>? extra}) {
    final headers = <String, String>{};
    if (authStore.token != null && authStore.token!.isNotEmpty) {
      headers['Authorization'] = authStore.token!;
    }
    if (json) headers['Content-Type'] = 'application/json';
    if (extra != null) headers.addAll(extra);
    return headers;
  }

  Future<Map<String, dynamic>> login(
    String username,
    String password, {
    String? inviteCode,
  }) async {
    final token = base64Encode(utf8.encode('$username:$password'));
    final headers = <String, String>{'Authorization': token};
    if (inviteCode != null && inviteCode.trim().isNotEmpty) {
      headers['x-invite-code'] = inviteCode.trim();
    }

    final res = await http.post(_uri('/api/login'), headers: headers);
    final json = _decode(res);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      await authStore.setSession(username: username, token: token);
    }
    return json;
  }

  // Legacy endpoints (v1)
  Future<Map<String, dynamic>> loadData() async {
    final res = await http.get(_uri('/api/data'), headers: _headers());
    _throwIfError(res);
    return _decode(res);
  }

  Future<void> saveData(List<dynamic> data) async {
    final payload = {
      'data': data,
      'version': DateTime.now().millisecondsSinceEpoch,
      'force': true,
    };
    final res = await http.post(
      _uri('/api/data'),
      headers: _headers(),
      body: jsonEncode(payload),
    );
    _throwIfError(res);
  }

  Future<HolidayCnYear> getHolidayCnYear(int year) async {
    final res =
        await http.get(_uri('/api/holidays/$year'), headers: _headers());
    _throwIfError(res);
    final json = _decode(res);
    return HolidayCnYear.fromJson(json);
  }

  Future<List<Task>> getTasks({
    String view = 'all',
    bool includeDeleted = false,
    int? updatedSince,
    int limit = 200,
    int offset = 0,
  }) async {
    final params = <String, String>{
      'view': view,
      if (includeDeleted) 'include_deleted': 'true',
      'limit': limit.toString(),
      'offset': offset.toString(),
    };
    if (updatedSince != null) {
      params['updated_since'] = updatedSince.toString();
    }
    final uri = _uri('/api/v2/tasks').replace(queryParameters: params);
    final res = await http.get(uri, headers: _headers());
    _throwIfError(res);
    final json = _decode(res);
    final list = json['tasks'];
    if (list is List) {
      return list.whereType<Map<String, dynamic>>().map(Task.fromJson).toList();
    }
    return <Task>[];
  }

  Future<Task> createTask({
    required String title,
    String notes = '',
    String dueDate = '',
    String startTime = '',
    String endTime = '',
    List<String> tags = const [],
    List<TaskSubtask> subtasks = const [],
    bool inbox = false,
    int priority = 0,
    int? remindAt,
    String repeatRule = '',
    String status = 'todo',
  }) async {
    final payload = {
      'title': title,
      'notes': notes,
      'dueDate': dueDate,
      'startTime': startTime,
      'endTime': endTime,
      'tags': tags,
      'subtasks': subtasks.map((item) => item.toJson()).toList(),
      'inbox': inbox,
      'priority': priority,
      'remindAt': remindAt,
      'repeatRule': repeatRule,
      'status': status,
    };
    final res = await http.post(
      _uri('/api/v2/tasks'),
      headers: _headers(),
      body: jsonEncode(payload),
    );
    _throwIfError(res);
    final json = _decode(res);
    return Task.fromJson(json['task'] as Map<String, dynamic>);
  }

  Future<Task> updateTask(
    String id, {
    String? title,
    String? notes,
    String? status,
    String? dueDate,
    String? startTime,
    String? endTime,
    List<String>? tags,
    List<TaskSubtask>? subtasks,
    bool? inbox,
    int? priority,
    int? remindAt,
    bool clearRemindAt = false,
    String? repeatRule,
    int? deletedAt,
    bool clearDeletedAt = false,
  }) async {
    final payload = <String, dynamic>{};
    if (title != null) payload['title'] = title;
    if (notes != null) payload['notes'] = notes;
    if (status != null) payload['status'] = status;
    if (dueDate != null) payload['dueDate'] = dueDate;
    if (startTime != null) payload['startTime'] = startTime;
    if (endTime != null) payload['endTime'] = endTime;
    if (tags != null) payload['tags'] = tags;
    if (subtasks != null) {
      payload['subtasks'] = subtasks.map((item) => item.toJson()).toList();
    }
    if (inbox != null) payload['inbox'] = inbox;
    if (priority != null) payload['priority'] = priority;
    if (clearRemindAt) {
      payload['remindAt'] = null;
    } else if (remindAt != null) {
      payload['remindAt'] = remindAt;
    }
    if (repeatRule != null) payload['repeatRule'] = repeatRule;
    if (clearDeletedAt) {
      payload['deletedAt'] = null;
    } else if (deletedAt != null) {
      payload['deletedAt'] = deletedAt;
    }
    final res = await http.patch(
      _uri('/api/v2/tasks/$id'),
      headers: _headers(),
      body: jsonEncode(payload),
    );
    _throwIfError(res);
    final json = _decode(res);
    return Task.fromJson(json['task'] as Map<String, dynamic>);
  }

  Future<void> deleteTask(String id) async {
    final res =
        await http.delete(_uri('/api/v2/tasks/$id'), headers: _headers());
    _throwIfError(res);
  }

  Future<int> emptyTrash() async {
    final res = await http.delete(_uri('/api/v2/tasks/trash/empty'),
        headers: _headers());
    _throwIfError(res);
    final json = _decode(res);
    final purged = json['purged'];
    if (purged is int) return purged;
    if (purged is num) return purged.toInt();
    return int.tryParse(purged?.toString() ?? '') ?? 0;
  }

  Future<TaskAttachment> uploadAttachment({
    required String taskId,
    required String filename,
    required Uint8List bytes,
  }) async {
    final request = http.MultipartRequest(
        'POST', _uri('/api/v2/tasks/$taskId/attachments'));
    request.headers.addAll(_headers(json: false));
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: filename,
      ),
    );

    final res = await request.send();
    final body = await res.stream.bytesToString();
    if (res.statusCode == 401) {
      throw UnauthorizedException();
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(res.statusCode, body);
    }

    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw ApiException(res.statusCode, body);
    }
    final attachment = decoded['attachment'];
    if (attachment is! Map<String, dynamic>) {
      throw ApiException(res.statusCode, body);
    }
    return TaskAttachment.fromJson(attachment);
  }

  // Checklists
  Future<List<ChecklistList>> getChecklists() async {
    final res = await http.get(_uri('/api/checklists'), headers: _headers());
    _throwIfError(res);
    final json = _decode(res);
    final list = json['lists'];
    if (list is List) {
      return list
          .whereType<Map<String, dynamic>>()
          .map(ChecklistList.fromJson)
          .toList();
    }
    return <ChecklistList>[];
  }

  Future<ChecklistList> createChecklist({required String name}) async {
    final payload = {'name': name};
    final res = await http.post(
      _uri('/api/checklists'),
      headers: _headers(),
      body: jsonEncode(payload),
    );
    _throwIfError(res);
    final json = _decode(res);
    return ChecklistList.fromJson(json['list'] as Map<String, dynamic>);
  }

  Future<void> deleteChecklist(int id) async {
    final res =
        await http.delete(_uri('/api/checklists/$id'), headers: _headers());
    _throwIfError(res);
  }

  Future<List<ChecklistItem>> getChecklistItems(int listId) async {
    final res = await http.get(_uri('/api/checklists/$listId/items'),
        headers: _headers());
    _throwIfError(res);
    final json = _decode(res);
    final list = json['items'];
    if (list is List) {
      return list
          .whereType<Map<String, dynamic>>()
          .map(ChecklistItem.fromJson)
          .toList();
    }
    return <ChecklistItem>[];
  }

  Future<ChecklistItem> createChecklistItem({
    required int listId,
    required String title,
  }) async {
    final payload = {'title': title};
    final res = await http.post(
      _uri('/api/checklists/$listId/items'),
      headers: _headers(),
      body: jsonEncode(payload),
    );
    _throwIfError(res);
    final json = _decode(res);
    return ChecklistItem.fromJson(json['item'] as Map<String, dynamic>);
  }

  Future<ChecklistItem> updateChecklistItem({
    required int listId,
    required int itemId,
    String? title,
    bool? completed,
    String? notes,
  }) async {
    final payload = <String, dynamic>{};
    if (title != null) payload['title'] = title;
    if (completed != null) payload['completed'] = completed;
    if (notes != null) payload['notes'] = notes;
    final res = await http.patch(
      _uri('/api/checklists/$listId/items/$itemId'),
      headers: _headers(),
      body: jsonEncode(payload),
    );
    _throwIfError(res);
    final json = _decode(res);
    return ChecklistItem.fromJson(json['item'] as Map<String, dynamic>);
  }

  Future<void> deleteChecklistItem({
    required int listId,
    required int itemId,
  }) async {
    final res = await http.delete(_uri('/api/checklists/$listId/items/$itemId'),
        headers: _headers());
    _throwIfError(res);
  }

  Future<List<TimeActivity>> getActivities({
    int? updatedSince,
    int limit = 200,
    int offset = 0,
  }) async {
    final params = <String, String>{
      'limit': limit.toString(),
      'offset': offset.toString(),
    };
    if (updatedSince != null) {
      params['updated_since'] = updatedSince.toString();
    }
    final uri =
        _uri('/api/v2/time/activities').replace(queryParameters: params);
    final res = await http.get(uri, headers: _headers());
    _throwIfError(res);
    final json = _decode(res);
    final list = json['activities'];
    if (list is List) {
      return list
          .whereType<Map<String, dynamic>>()
          .map(TimeActivity.fromJson)
          .toList();
    }
    return <TimeActivity>[];
  }

  Future<TimeActivity> createActivity({
    required String name,
    String? taskId,
    String? icon,
    String? color,
    String? category,
    String? goal,
    String? note,
  }) async {
    final payload = {
      'name': name,
      if (taskId != null && taskId.isNotEmpty) 'taskId': taskId,
      if (icon != null && icon.isNotEmpty) 'icon': icon,
      if (color != null && color.isNotEmpty) 'color': color,
      if (category != null && category.isNotEmpty) 'category': category,
      if (goal != null && goal.isNotEmpty) 'goal': goal,
      if (note != null) 'note': note,
    };
    final res = await http.post(
      _uri('/api/v2/time/activities'),
      headers: _headers(),
      body: jsonEncode(payload),
    );
    _throwIfError(res);
    final json = _decode(res);
    return TimeActivity.fromJson(json['activity'] as Map<String, dynamic>);
  }

  Future<TimeActivity> updateActivity(
    String id, {
    String? name,
    String? taskId,
    String? icon,
    String? color,
    String? category,
    String? goal,
    String? note,
    int? deletedAt,
  }) async {
    final payload = <String, dynamic>{};
    if (name != null) payload['name'] = name;
    if (taskId != null) payload['taskId'] = taskId;
    if (icon != null) payload['icon'] = icon;
    if (color != null) payload['color'] = color;
    if (category != null) payload['category'] = category;
    if (goal != null) payload['goal'] = goal;
    if (note != null) payload['note'] = note;
    if (deletedAt != null) payload['deletedAt'] = deletedAt;
    final res = await http.patch(
      _uri('/api/v2/time/activities/$id'),
      headers: _headers(),
      body: jsonEncode(payload),
    );
    _throwIfError(res);
    final json = _decode(res);
    return TimeActivity.fromJson(json['activity'] as Map<String, dynamic>);
  }

  Future<void> deleteActivity(String id) async {
    final res = await http.delete(_uri('/api/v2/time/activities/$id'),
        headers: _headers());
    _throwIfError(res);
  }

  Future<List<TimeEntry>> getEntries({
    int? from,
    int? to,
    String? activityId,
    String? taskId,
    bool runningOnly = false,
    int limit = 200,
    int offset = 0,
  }) async {
    final params = <String, String>{
      'limit': limit.toString(),
      'offset': offset.toString(),
    };
    if (from != null) params['from'] = from.toString();
    if (to != null) params['to'] = to.toString();
    if (activityId != null && activityId.isNotEmpty)
      params['activity_id'] = activityId;
    if (taskId != null && taskId.isNotEmpty) params['task_id'] = taskId;
    if (runningOnly) params['running_only'] = 'true';
    final uri = _uri('/api/v2/time/entries').replace(queryParameters: params);
    final res = await http.get(uri, headers: _headers());
    _throwIfError(res);
    final json = _decode(res);
    final list = json['entries'];
    if (list is List) {
      return list
          .whereType<Map<String, dynamic>>()
          .map(TimeEntry.fromJson)
          .toList();
    }
    return <TimeEntry>[];
  }

  Future<List<TimeEntry>> getRunningEntries() async {
    final res = await http.get(_uri('/api/v2/time/entries/running'),
        headers: _headers());
    _throwIfError(res);
    final json = _decode(res);
    final list = json['entries'];
    if (list is List) {
      return list
          .whereType<Map<String, dynamic>>()
          .map(TimeEntry.fromJson)
          .toList();
    }
    return <TimeEntry>[];
  }

  Future<TimeEntry> startEntry({
    required String activityId,
    String? taskId,
    int? startedAt,
    String? note,
    List<String>? tags,
  }) async {
    final payload = {
      'activityId': activityId,
      if (taskId != null && taskId.isNotEmpty) 'taskId': taskId,
      if (startedAt != null) 'startedAt': startedAt,
      if (note != null) 'note': note,
      if (tags != null) 'tags': tags,
    };
    final res = await http.post(
      _uri('/api/v2/time/entries/start'),
      headers: _headers(),
      body: jsonEncode(payload),
    );
    _throwIfError(res);
    final json = _decode(res);
    return TimeEntry.fromJson(json['entry'] as Map<String, dynamic>);
  }

  Future<TimeEntry> stopEntry(String id, {int? endedAt}) async {
    final payload = <String, dynamic>{};
    if (endedAt != null) payload['endedAt'] = endedAt;
    final res = await http.post(
      _uri('/api/v2/time/entries/$id/stop'),
      headers: _headers(),
      body: jsonEncode(payload),
    );
    _throwIfError(res);
    final json = _decode(res);
    return TimeEntry.fromJson(json['entry'] as Map<String, dynamic>);
  }

  Future<TimeEntry> updateEntry(
    String id, {
    String? activityId,
    String? taskId,
    int? startedAt,
    int? endedAt,
    bool clearEndedAt = false,
    String? note,
    List<String>? tags,
    int? deletedAt,
  }) async {
    final payload = <String, dynamic>{};
    if (activityId != null) payload['activityId'] = activityId;
    if (taskId != null) payload['taskId'] = taskId;
    if (startedAt != null) payload['startedAt'] = startedAt;
    if (clearEndedAt) {
      payload['endedAt'] = null;
    } else if (endedAt != null) {
      payload['endedAt'] = endedAt;
    }
    if (note != null) payload['note'] = note;
    if (tags != null) payload['tags'] = tags;
    if (deletedAt != null) payload['deletedAt'] = deletedAt;
    final res = await http.patch(
      _uri('/api/v2/time/entries/$id'),
      headers: _headers(),
      body: jsonEncode(payload),
    );
    _throwIfError(res);
    final json = _decode(res);
    return TimeEntry.fromJson(json['entry'] as Map<String, dynamic>);
  }

  Future<void> deleteEntry(String id) async {
    final res = await http.delete(_uri('/api/v2/time/entries/$id'),
        headers: _headers());
    _throwIfError(res);
  }

  Future<TimeStats> getTimeStats({required int from, required int to}) async {
    final uri = _uri('/api/v2/time/stats').replace(queryParameters: {
      'from': from.toString(),
      'to': to.toString(),
    });
    final res = await http.get(uri, headers: _headers());
    _throwIfError(res);
    final json = _decode(res);
    return TimeStats.fromJson(json);
  }

  Future<PomodoroSettings> getPomodoroSettings() async {
    final res =
        await http.get(_uri('/api/pomodoro/settings'), headers: _headers());
    _throwIfError(res);
    final json = _decode(res);
    final raw = json['settings'];
    if (raw is Map<String, dynamic>) {
      return PomodoroSettings.fromJson(raw);
    }
    if (raw is Map) {
      return PomodoroSettings.fromJson(raw.cast<String, dynamic>());
    }
    return const PomodoroSettings(
      workMin: 25,
      shortBreakMin: 5,
      longBreakMin: 15,
      longBreakEvery: 4,
      autoStartNext: false,
      autoStartBreak: false,
      autoStartWork: false,
      autoFinishTask: false,
    );
  }

  Future<PomodoroSettings> savePomodoroSettings(
      PomodoroSettings settings) async {
    final res = await http.post(
      _uri('/api/pomodoro/settings'),
      headers: _headers(),
      body: jsonEncode(settings.toJson()),
    );
    _throwIfError(res);
    final json = _decode(res);
    final raw = json['settings'];
    if (raw is Map<String, dynamic>) {
      return PomodoroSettings.fromJson(raw);
    }
    if (raw is Map) {
      return PomodoroSettings.fromJson(raw.cast<String, dynamic>());
    }
    return settings;
  }

  Future<PomodoroState?> getPomodoroState() async {
    final res =
        await http.get(_uri('/api/pomodoro/state'), headers: _headers());
    _throwIfError(res);
    final json = _decode(res);
    final raw = json['state'];
    if (raw == null) return null;
    if (raw is Map<String, dynamic>) return PomodoroState.fromJson(raw);
    if (raw is Map) return PomodoroState.fromJson(raw.cast<String, dynamic>());
    return null;
  }

  Future<void> savePomodoroState(PomodoroState state) async {
    final res = await http.post(
      _uri('/api/pomodoro/state'),
      headers: _headers(),
      body: jsonEncode(state.toJson()),
    );
    _throwIfError(res);
  }

  Future<PomodoroSummary> getPomodoroSummary({int days = 7}) async {
    final uri = _uri('/api/pomodoro/summary').replace(queryParameters: {
      'days': days.toString(),
    });
    final res = await http.get(uri, headers: _headers());
    _throwIfError(res);
    final json = _decode(res);
    return PomodoroSummary.fromJson(json);
  }

  Future<List<PomodoroSession>> getPomodoroSessions({int limit = 50}) async {
    final uri = _uri('/api/pomodoro/sessions').replace(queryParameters: {
      'limit': limit.toString(),
    });
    final res = await http.get(uri, headers: _headers());
    _throwIfError(res);
    final json = _decode(res);
    final list = json['sessions'];
    if (list is List) {
      return list
          .whereType<Map<String, dynamic>>()
          .map(PomodoroSession.fromJson)
          .toList();
    }
    return <PomodoroSession>[];
  }

  Future<void> addPomodoroSession({
    int? taskId,
    String? taskTitle,
    int? startedAt,
    int? endedAt,
    required int durationMin,
    String? dateKey,
  }) async {
    final payload = {
      if (taskId != null) 'taskId': taskId,
      if (taskTitle != null) 'taskTitle': taskTitle,
      if (startedAt != null) 'startedAt': startedAt,
      if (endedAt != null) 'endedAt': endedAt,
      'durationMin': durationMin,
      if (dateKey != null) 'dateKey': dateKey,
    };
    final res = await http.post(
      _uri('/api/pomodoro/sessions'),
      headers: _headers(),
      body: jsonEncode(payload),
    );
    _throwIfError(res);
  }

  Future<UserSettings> getUserSettings() async {
    final res = await http.get(_uri('/api/user/settings'), headers: _headers());
    _throwIfError(res);
    final json = _decode(res);
    final raw = json['settings'];
    if (raw is Map<String, dynamic>) {
      return UserSettings.fromJson(raw);
    }
    if (raw is Map) {
      return UserSettings.fromJson(raw.cast<String, dynamic>());
    }
    return UserSettings.defaults();
  }

  Future<UserSettings> saveUserSettings(UserSettings settings) async {
    final res = await http.post(
      _uri('/api/user/settings'),
      headers: _headers(),
      body: jsonEncode({'settings': settings.toJson()}),
    );
    _throwIfError(res);
    final json = _decode(res);
    final raw = json['settings'];
    if (raw is Map<String, dynamic>) {
      return UserSettings.fromJson(raw);
    }
    if (raw is Map) {
      return UserSettings.fromJson(raw.cast<String, dynamic>());
    }
    return settings;
  }

  Future<void> registerFcmToken({
    required String token,
    required String platform,
  }) async {
    final res = await http.post(
      _uri('/api/fcm/register'),
      headers: _headers(),
      body: jsonEncode({
        'token': token,
        'platform': platform,
      }),
    );
    _throwIfError(res);
  }

  Future<void> unregisterFcmToken({String? token}) async {
    final payload = <String, dynamic>{};
    if (token != null && token.trim().isNotEmpty) {
      payload['token'] = token.trim();
    }
    final res = await http.post(
      _uri('/api/fcm/unregister'),
      headers: _headers(),
      body: jsonEncode(payload),
    );
    _throwIfError(res);
  }

  Future<void> sendFcmTest() async {
    final res = await http.post(
      _uri('/api/fcm/test'),
      headers: _headers(),
      body: jsonEncode({}),
    );
    _throwIfError(res);
  }

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    final res = await http.post(
      _uri('/api/change-pwd'),
      headers: _headers(),
      body: jsonEncode({
        'oldPassword': oldPassword,
        'newPassword': newPassword,
      }),
    );
    _throwIfError(res);
  }

  Future<String> getInviteCode() async {
    final res = await http.get(_uri('/api/admin/invite'), headers: _headers());
    _throwIfError(res);
    final json = _decode(res);
    return (json['code'] ?? '').toString();
  }

  Future<String> refreshInviteCode() async {
    final res = await http.post(_uri('/api/admin/invite/refresh'),
        headers: _headers(), body: jsonEncode({}));
    _throwIfError(res);
    final json = _decode(res);
    return (json['code'] ?? '').toString();
  }

  Future<Map<String, dynamic>> exportAllData() async {
    final res = await http.get(_uri('/api/v2/export'), headers: _headers());
    _throwIfError(res);
    return _decode(res);
  }

  Future<void> importAllData({
    required String mode, // merge | overwrite
    required Map<String, dynamic> data,
  }) async {
    final res = await http.post(
      _uri('/api/v2/import'),
      headers: _headers(),
      body: jsonEncode({'mode': mode, 'data': data}),
    );
    _throwIfError(res);
  }

  Future<int> cleanupCompletedTasks({required int retentionDays}) async {
    final res = await http.post(
      _uri('/api/v2/tasks/completed/cleanup'),
      headers: _headers(),
      body: jsonEncode({'retentionDays': retentionDays}),
    );
    _throwIfError(res);
    final json = _decode(res);
    final purged = json['purged'];
    if (purged is int) return purged;
    if (purged is num) return purged.toInt();
    return int.tryParse(purged?.toString() ?? '') ?? 0;
  }

  Future<void> deleteAccountAndData() async {
    final res = await http.post(
      _uri('/api/user/delete'),
      headers: _headers(),
      body: jsonEncode({'confirm': 'DELETE'}),
    );
    _throwIfError(res);
  }

  Map<String, dynamic> _decode(http.Response res) {
    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return {'data': decoded};
  }

  void _throwIfError(http.Response res) {
    if (res.statusCode == 401) {
      throw UnauthorizedException();
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(res.statusCode, res.body);
    }
  }
}
