import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:glass_todo_flutter/core/api_client.dart';
import 'package:glass_todo_flutter/core/auth_store.dart';
import 'package:glass_todo_flutter/models/checklist.dart';
import 'package:glass_todo_flutter/models/task.dart';
import 'package:glass_todo_flutter/models/time_activity.dart';
import 'package:glass_todo_flutter/models/time_entry.dart';
import 'package:glass_todo_flutter/models/user_settings.dart';
import 'package:glass_todo_flutter/ui/task_page.dart';
import 'package:glass_todo_flutter/ui/workspace_view.dart';

class _FakeApiClient extends ApiClient {
  _FakeApiClient({required AuthStore authStore})
      : super(baseUrl: '', authStore: authStore);

  int _nextChecklistId = 1;
  int _nextChecklistItemId = 1;
  final List<ChecklistList> _lists = <ChecklistList>[];
  final Map<int, List<ChecklistItem>> _items = <int, List<ChecklistItem>>{};

  @override
  Future<List<Task>> getTasks({
    String view = 'all',
    bool includeDeleted = false,
    int? updatedSince,
    int limit = 200,
    int offset = 0,
  }) async {
    return <Task>[];
  }

  @override
  Future<List<ChecklistList>> getChecklists() async {
    return List<ChecklistList>.unmodifiable(_lists);
  }

  @override
  Future<ChecklistList> createChecklist({required String name}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final created = ChecklistList(
      id: _nextChecklistId++,
      name: name,
      owner: 'tester',
      sharedCount: 0,
      createdAt: now,
      updatedAt: now,
    );
    _lists.add(created);
    return created;
  }

  @override
  Future<List<ChecklistItem>> getChecklistItems(int listId) async {
    return List<ChecklistItem>.unmodifiable(_items[listId] ?? <ChecklistItem>[]);
  }

  @override
  Future<ChecklistItem> createChecklistItem({
    required int listId,
    required String title,
    String? notes,
    int? columnId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final created = ChecklistItem(
      id: _nextChecklistItemId++,
      listId: listId,
      columnId: null,
      title: title,
      completed: false,
      completedBy: '',
      notes: '',
      createdAt: now,
      updatedAt: now,
    );
    _items.putIfAbsent(listId, () => <ChecklistItem>[]).add(created);
    return created;
  }

  @override
  Future<List<TimeActivity>> getActivities({
    int? updatedSince,
    int limit = 200,
    int offset = 0,
  }) async {
    return <TimeActivity>[];
  }

  @override
  Future<List<TimeEntry>> getEntries({
    int? from,
    int? to,
    String? activityId,
    String? taskId,
    bool runningOnly = false,
    int limit = 200,
    int offset = 0,
  }) async {
    return <TimeEntry>[];
  }

  @override
  Future<List<TimeEntry>> getRunningEntries() async {
    return <TimeEntry>[];
  }
}

void main() {
  testWidgets('Create checklist and item without framework assertion', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SharedPreferences.setMockInitialValues({});
    final authStore = await AuthStore.load();
    final apiClient = _FakeApiClient(authStore: authStore);
    final defaults = UserSettings.defaults();
    final userSettings = defaults.copyWith(
      preferences: defaults.preferences.copyWith(defaultView: 'checklists'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskPage(
            appTitle: 'Test',
            username: 'tester',
            apiClient: apiClient,
            userSettings: userSettings,
            timeTrackingOngoingNotificationEnabled: false,
            onLogout: () {},
            onOpenSettings: () {},
            workspace: WorkspaceView.tasks,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final createButtons = find.byTooltip('新建清单');
    expect(createButtons, findsWidgets);
    await tester.ensureVisible(createButtons.first);
    await tester.pumpAndSettle();
    await tester.tap(createButtons.first);
    await tester.pumpAndSettle();

    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);

    final dialogField = find.descendant(of: dialog, matching: find.byType(TextField));
    expect(dialogField, findsOneWidget);
    await tester.enterText(dialogField, '测试清单');

    await tester.tap(find.descendant(of: dialog, matching: find.text('创建')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    expect(find.text('测试清单'), findsWidgets);
  });
}
