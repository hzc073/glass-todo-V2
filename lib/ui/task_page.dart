import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../core/api_client.dart';
import '../models/checklist.dart';
import '../models/holiday_cn.dart';
import '../models/pomodoro_session.dart';
import '../models/pomodoro_summary.dart';
import '../models/task.dart';
import '../models/time_activity.dart';
import '../models/time_entry.dart';
import '../models/time_stats.dart';
import '../models/user_settings.dart';
import 'app_theme.dart';
import 'calendar_view.dart';
import 'pomodoro_view.dart';
import 'stats_dashboard_view.dart';
import 'task_filters.dart';
import 'task_colors.dart';
import 'time_tracking_view.dart';
import 'workspace_view.dart';
import 'widgets/decorative_background.dart';
import 'widgets/empty_state.dart';
import 'widgets/sidebar.dart';
import 'widgets/staggered_fade_slide.dart';
import 'widgets/task_card.dart';
import 'widgets/time_activity_editor.dart';
import 'widgets/time_entry_editor.dart';

class TaskPage extends StatefulWidget {
  const TaskPage({
    super.key,
    required this.appTitle,
    required this.username,
    required this.apiClient,
    required this.userSettings,
    required this.onLogout,
    required this.onOpenSettings,
  });

  final String appTitle;
  final String username;
  final ApiClient apiClient;
  final UserSettings userSettings;
  final VoidCallback onLogout;
  final VoidCallback onOpenSettings;

  @override
  State<TaskPage> createState() => _TaskPageState();
}

class _TaskPageState extends State<TaskPage> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _searchController = TextEditingController();
  final _quickAddController = TextEditingController();
  final _checklistAddController = TextEditingController();
  final _scrollController = ScrollController();
  final _dateFormatter = DateFormat('yyyy-MM-dd');

  static const int _attachmentTotalLimit = 50 * 1024 * 1024;
  static const List<String> _allowedAttachmentExts = [
    'pdf',
    'doc',
    'docx',
    'xls',
    'xlsx',
    'ppt',
    'pptx',
    'txt',
    'md',
    'csv',
    'rtf',
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'bmp',
    'tif',
    'tiff',
    'svg',
    'psd',
    'psb',
    'ai',
    'sketch',
    'fig',
    'xd',
    'indd',
    'dwg',
    'dxf',
    'dwf',
    'stp',
    'step',
    'igs',
    'iges',
    'skp',
  ];

  bool _quickAddExpanded = false;
  DateTime? _quickAddDate;
  TimeOfDay? _quickAddStartTime;
  TimeOfDay? _quickAddEndTime;
  bool _quickAddRepeat = false;
  RepeatFrequency _quickAddRepeatFrequency = RepeatFrequency.daily;
  int _quickAddRepeatCount = 1;
  Set<int> _quickAddRepeatWeekdays = {};
  int _quickAddRepeatMonthDay = 1;
  int _quickAddRepeatYearMonth = 1;
  int _quickAddRepeatYearDay = 1;
  DateTime? _quickAddRemindAt;
  String _quickAddColorHex = '';
  static const String _quickAddDefaultColorLabel = '默认';
  final List<PlatformFile> _quickAddAttachments = [];
  int _quickAddAttachmentBytes = 0;
  final List<_SubtaskDraft> _quickAddSubtasks = [];
  bool _quickAddSubtasksExpanded = false;

  List<Task> _tasks = [];
  List<ChecklistList> _checklists = [];
  final Map<int, List<ChecklistItem>> _checklistItems = {};
  int? _activeChecklistId;
  bool _loadingChecklists = false;
  int? _loadingChecklistId;
  List<TimeActivity> _activities = [];
  List<TimeEntry> _runningEntries = [];
  List<TimeEntry> _timeEntries = [];
  TaskFilter _filter = TaskFilter.inbox;
  bool _showTrash = false;
  WorkspaceView _workspace = WorkspaceView.tasks;
  String _searchQuery = '';
  String? _selectedTaskId;
  bool _loading = true;
  bool _saving = false;
  bool _loadingTime = false;
  bool _savingTime = false;
  bool _loadingStats = false;
  DateTime? _lastSync;
  DateTime? _lastTimeSync;
  TimeStats? _timeStats;
  PomodoroSummary? _pomodoroSummary;
  List<PomodoroSession> _pomodoroSessions = [];
  int _statsFrom = 0;
  int _statsTo = 0;

  @override
  void initState() {
    super.initState();
    _applyDefaultView(widget.userSettings.preferences.defaultView,
        initial: true);
    _loadTasks();
    _loadChecklists();
    _setDefaultStatsRange();
    _loadTimeTracking();
  }

  @override
  void didUpdateWidget(covariant TaskPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userSettings.preferences.defaultView !=
        widget.userSettings.preferences.defaultView) {
      _applyDefaultView(widget.userSettings.preferences.defaultView);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _quickAddController.dispose();
    _checklistAddController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final counts = _buildCounts();
    final workspaceCounts = _buildWorkspaceCounts();
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth >= 960;
    final isTasks = _workspace == WorkspaceView.tasks;
    final isTimeTracking = _workspace == WorkspaceView.timeTracking;
    final isCalendar = _workspace == WorkspaceView.calendar;
    final isPomodoro = _workspace == WorkspaceView.pomodoro;
    final isStats = _workspace == WorkspaceView.stats;
    final isTrash = isTasks && _showTrash;
    final isChecklistView = isTasks && !isTrash && _activeChecklistId != null;
    final showTaskNav = isTasks && screenWidth >= 900;
    final baseFiltered = isTasks
        ? (isTrash
            ? _applyTrash(_tasks)
            : isChecklistView
                ? _applyChecklistTasks(_tasks, _activeChecklistId!)
                : _applyFilter(_tasks, _filter))
        : <Task>[];
    final filtered = isTasks ? _applySearch(baseFiltered) : <Task>[];
    final selectedTask = isTrash ? null : _findTaskById(_selectedTaskId);
    final showDetailPanel = isTasks && !isTrash && screenWidth >= 1200;
    final showInlineFilters = isTasks && !showTaskNav && !isTrash;
    final headerTitle = isTasks
        ? (isTrash
            ? '回收站'
            : isChecklistView
                ? (_findChecklistById(_activeChecklistId)?.name ?? '清单')
                : _filter.label)
        : _workspace.label;
    final headerSubtitle = isTasks
        ? (isTrash
            ? '已删除的任务，可还原或清空。'
            : isChecklistView
                ? '清单分类任务。'
                : _filter.description)
        : (isTimeTracking ? '' : _workspace.description);
    String headerMetaTitle;
    String headerMetaSubtitle;
    if (isTasks) {
      headerMetaTitle =
          isTrash ? '${filtered.length} 个已删除' : '${filtered.length} 个任务';
      headerMetaSubtitle = _saving
          ? '同步中...'
          : _lastSync == null
              ? '尚未同步'
              : '更新于 ${DateFormat('HH:mm').format(_lastSync!)}';
    } else if (isTimeTracking) {
      final runningCount = _runningEntries.length;
      headerMetaTitle = runningCount > 0
          ? '进行中 $runningCount 项'
          : '${_activities.length} 个事件';
      headerMetaSubtitle = _loadingTime || _savingTime
          ? '同步中...'
          : _lastTimeSync == null
              ? '尚未同步'
              : '更新于 ${DateFormat('HH:mm').format(_lastTimeSync!)}';
    } else if (isStats) {
      headerMetaTitle = _loadingStats
          ? '统计加载中'
          : _timeStats == null
              ? '尚无统计'
              : '总计 ${_formatDuration(_timeStats!.totalMs)}';
      headerMetaSubtitle = _statsRangeLabel();
    } else if (isCalendar) {
      headerMetaTitle = '日历';
      headerMetaSubtitle = '日/周/月 · 15分钟时间轴';
    } else {
      headerMetaTitle = '敬请期待';
      headerMetaSubtitle = '功能开发中';
    }

    final headerBlock = _HeaderBlock(
      title: headerTitle,
      subtitle: headerSubtitle,
      metaTitle: headerMetaTitle,
      metaSubtitle: headerMetaSubtitle,
    );

    return Stack(
      children: [
        const DecorativeBackground(),
        SafeArea(
          child: Scaffold(
            key: _scaffoldKey,
            backgroundColor: Colors.transparent,
            drawer: isWide
                ? null
                : Drawer(
                    shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.zero),
                    child: Sidebar(
                      appTitle: widget.appTitle,
                      selectedWorkspace: _workspace,
                      workspaceCounts: workspaceCounts,
                      onWorkspaceSelect: (view) {
                        _selectWorkspace(view);
                        Navigator.of(context).pop();
                      },
                    ),
                  ),
            body: Row(
              children: [
                if (isWide)
                  SizedBox(
                    width: 260,
                    child: Sidebar(
                      appTitle: widget.appTitle,
                      selectedWorkspace: _workspace,
                      workspaceCounts: workspaceCounts,
                      onWorkspaceSelect: _selectWorkspace,
                    ),
                  ),
                Expanded(
                  child: Column(
                    key: const ValueKey('task_detail_scroll_column'),
                    children: [
                      _buildToolbar(
                        context,
                        isWide: isWide,
                        isTasks: isTasks,
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                          child: _buildWorkspaceBody(
                            isTasks: isTasks,
                            isTimeTracking: isTimeTracking,
                            isCalendar: isCalendar,
                            isPomodoro: isPomodoro,
                            isStats: isStats,
                            filtered: filtered,
                            counts: counts,
                            showTaskNav: showTaskNav,
                            showInlineFilters: showInlineFilters,
                            showDetailPanel: showDetailPanel,
                            selectedTask: selectedTask,
                            header: headerBlock,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar(
    BuildContext context, {
    required bool isWide,
    required bool isTasks,
  }) {
    final dateLabel = DateFormat('M月d日 EEEE').format(DateTime.now());
    final hasQuery = _searchQuery.trim().isNotEmpty;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width;
        final isCompact = availableWidth < 720;
        final searchMaxWidth = isCompact ? double.infinity : 320.0;

        final searchBox = Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.85),
            borderRadius: BorderRadius.zero,
            border: Border.all(color: AppColors.outline),
          ),
          child: Row(
            children: [
              const Icon(Icons.search, size: 18, color: AppColors.inkSoft),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: const ValueKey('quick_add_input'),
                  controller: _searchController,
                  enabled: isTasks,
                  decoration: InputDecoration(
                    hintText: isTasks ? '搜索任务...' : '搜索',
                    border: InputBorder.none,
                    isDense: true,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                    hintStyle: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.inkSoft),
                  ),
                  onChanged: isTasks ? _updateSearchQuery : null,
                ),
              ),
              if (isTasks && hasQuery)
                InkWell(
                  onTap: _clearSearch,
                  borderRadius: BorderRadius.zero,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child:
                        Icon(Icons.close, size: 16, color: AppColors.inkSoft),
                  ),
                ),
            ],
          ),
        );

        return Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withOpacity(0.92),
            border: Border(
              bottom: BorderSide(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          child: Row(
            children: [
              if (!isWide) ...[
                IconButton(
                  onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                  icon: const Icon(Icons.menu),
                  tooltip: '打开导航',
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: searchMaxWidth),
                    child: searchBox,
                  ),
                ),
              ),
              if (!isCompact) ...[
                const SizedBox(width: 16),
                Text(
                  dateLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.inkSoft,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(width: 12),
                Tooltip(
                  message: widget.username,
                  child: const CircleAvatar(
                    radius: 14,
                    backgroundColor: AppColors.accentCool,
                    child: Icon(Icons.person, size: 16, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: widget.onOpenSettings,
                  icon: const Icon(Icons.settings),
                  tooltip: '设置',
                ),
                IconButton(
                  onPressed: widget.onLogout,
                  icon: const Icon(Icons.logout),
                  tooltip: '退出登录',
                ),
              ] else ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: widget.onOpenSettings,
                  icon: const Icon(Icons.settings),
                  tooltip: '设置',
                ),
                PopupMenuButton<String>(
                  tooltip: '更多',
                  onSelected: (value) {
                    if (value == 'logout') {
                      widget.onLogout();
                      return;
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem<String>(
                      enabled: false,
                      child: Text(
                        widget.username,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem<String>(
                      value: 'logout',
                      child: Row(
                        children: [
                          Icon(Icons.logout, size: 18),
                          SizedBox(width: 10),
                          Text('退出登录'),
                        ],
                      ),
                    ),
                  ],
                  child: const CircleAvatar(
                    radius: 14,
                    backgroundColor: AppColors.accentCool,
                    child: Icon(Icons.person, size: 16, color: Colors.white),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildWorkspaceBody({
    required bool isTasks,
    required bool isTimeTracking,
    required bool isCalendar,
    required bool isPomodoro,
    required bool isStats,
    required List<Task> filtered,
    required Map<TaskFilter, int> counts,
    required bool showTaskNav,
    required bool showInlineFilters,
    required bool showDetailPanel,
    required Task? selectedTask,
    required Widget header,
  }) {
    if (isTasks) {
      final isTrashView = _showTrash;
      final isChecklistView = false;
      final hasSearch = _searchQuery.trim().isNotEmpty;
      final emptySubtitle = hasSearch ? '没有找到匹配的任务。' : '';
      final trashCount = _tasks.where((task) => task.deletedAt != null).length;

      final ChecklistList? activeChecklist =
          isChecklistView ? _findChecklistById(_activeChecklistId) : null;
      final checklistRaw = isChecklistView
          ? (_checklistItems[_activeChecklistId] ?? <ChecklistItem>[])
          : <ChecklistItem>[];
      final checklistItems = isChecklistView
          ? _applyChecklistSearch(checklistRaw)
          : <ChecklistItem>[];
      final sortedChecklistItems = List<ChecklistItem>.from(checklistItems)
        ..sort((a, b) {
          if (a.completed != b.completed) return a.completed ? 1 : -1;
          return a.createdAt.compareTo(b.createdAt);
        });

      late final Widget listBody;
      if (isChecklistView) {
        final loadingChecklist = _loadingChecklistId == _activeChecklistId;
        if (loadingChecklist && sortedChecklistItems.isEmpty) {
          listBody = const Center(child: CircularProgressIndicator());
        } else if (sortedChecklistItems.isEmpty) {
          listBody = Center(
            child: EmptyState(
              title: hasSearch ? '没有找到事项' : '清单为空',
              subtitle: emptySubtitle,
              flat: true,
            ),
          );
        } else {
          listBody = ListView.builder(
            controller: _scrollController,
            itemCount: sortedChecklistItems.length,
            itemBuilder: (context, index) {
              final item = sortedChecklistItems[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ChecklistItemCard(
                  item: item,
                  saving: _saving,
                  onToggle: () => _toggleChecklistItem(item),
                  onDelete: () => _confirmDeleteChecklistItem(item),
                ),
              );
            },
          );
        }
      } else if (_loading) {
        listBody = const Center(child: CircularProgressIndicator());
      } else if (filtered.isEmpty) {
        listBody = Center(
          child: EmptyState(
            title: isTrashView ? '回收站为空' : '这里还没有内容',
            subtitle: emptySubtitle,
            flat: true,
          ),
        );
      } else if (isTrashView) {
        listBody = ListView.builder(
          controller: _scrollController,
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final task = filtered[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _TrashTaskCard(
                task: task,
                restoring: _saving,
                onRestore: () => _restoreTask(task),
              ),
            );
          },
        );
      } else {
        listBody = ListView.builder(
          controller: _scrollController,
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final task = filtered[index];
            final isSelected = selectedTask?.id == task.id;
            final card = TaskCard(
              task: task,
              isSelected: isSelected,
              onTap: () => _selectTask(task.id),
              onToggle: () => _toggleTask(task),
              onEditTitle: _saving ? null : () => _promptEditTaskTitle(task),
            );
            return StaggeredFadeSlide(
              index: index,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Draggable<Task>(
                  data: task,
                  feedback: Material(
                    color: Colors.transparent,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Opacity(opacity: 0.95, child: card),
                    ),
                  ),
                  childWhenDragging: Opacity(opacity: 0.35, child: card),
                  child: card,
                ),
              ),
            );
          },
        );
      }
      final content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isChecklistView) ...[
            Row(
              children: [
                Text(
                  activeChecklist?.name ?? '清单',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _saving ? null : _closeChecklistView,
                  child: const Text('返回任务'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildChecklistQuickAddField(context),
          ] else if (!isTrashView) ...[
            _buildQuickAddField(context),
          ],
          if (showInlineFilters && !isTrashView && !isChecklistView) ...[
            const SizedBox(height: 12),
            _TaskFilterChips(
              selected: _filter,
              counts: counts,
              activeChecklistId: _activeChecklistId,
              saving: _saving,
              onSelect: _setFilter,
              onDropTask: _applyDropToFilter,
            ),
            const SizedBox(height: 12),
            _ChecklistChips(
              checklists: _checklists,
              activeChecklistId: _activeChecklistId,
              loading: _loadingChecklists,
              saving: _saving,
              username: widget.username,
              onSelect: _selectChecklist,
              onCreate: _promptCreateChecklist,
              onDelete: _confirmDeleteChecklist,
              onDropTask: _applyDropToChecklist,
            ),
          ],
          if (isTrashView) ...[
            Row(
              children: [
                Text(
                  '回收站',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _saving ? null : _closeTrash,
                  child: const Text('返回任务'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed:
                      trashCount == 0 || _saving ? null : _confirmEmptyTrash,
                  icon: const Icon(Icons.delete_forever),
                  label: const Text('清空回收站'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Expanded(child: listBody),
          if (!isTrashView && !isChecklistView) ...[
            const SizedBox(height: 12),
            _TrashDropZone(
              count: trashCount,
              deleting: _saving,
              onTap: _openTrash,
              onDrop: _moveTaskToTrash,
            ),
          ],
        ],
      );

      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showTaskNav) ...[
            SizedBox(
              width: 230,
              child: _TaskFilterPanel(
                selected: _filter,
                counts: counts,
                checklists: _checklists,
                activeChecklistId: _activeChecklistId,
                loadingChecklists: _loadingChecklists,
                saving: _saving,
                username: widget.username,
                onSelect: _setFilter,
                onSelectChecklist: _selectChecklist,
                onCreateChecklist: _promptCreateChecklist,
                onDeleteChecklist: _confirmDeleteChecklist,
                onDropTask: _applyDropToFilter,
                onDropChecklistTask: _applyDropToChecklist,
              ),
            ),
            const SizedBox(width: 14),
          ],
          Expanded(child: content),
          if (showDetailPanel && !isChecklistView) ...[
            const SizedBox(width: 14),
            SizedBox(
              width: 300,
              child: _TaskDetailPanel(
                task: selectedTask,
                saving: _saving,
                onClose: _clearSelectedTask,
                onToggleSubtask: _toggleSubtask,
                generateSubtaskId: _generateSubtaskId,
                onUpdateTask: _updateTaskFromDetail,
                onDeleteTask: _moveTaskToTrash,
              ),
            ),
          ],
        ],
      );
    }

    if (isTimeTracking) {
      final availableTasks =
          _tasks.where((task) => task.deletedAt == null).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TimeTrackingView(
              activities: _activities,
              entries: _timeEntries,
              runningEntries: _runningEntries,
              tasks: availableTasks,
              loading: _loadingTime,
              saving: _savingTime,
              lastSync: _lastTimeSync,
              onRefresh: () => _loadTimeTracking(),
              onAddActivity: () => _openActivityEditor(),
              onToggleActivity: _toggleActivity,
              onEditActivity: (activity) =>
                  _openActivityEditor(activity: activity),
              onDeleteActivity: _confirmDeleteActivity,
              onEditEntry: _openEntryEditor,
            ),
          ),
        ],
      );
    }

    if (isPomodoro) {
      final availableTasks =
          _tasks.where((task) => task.deletedAt == null).toList();
      return PomodoroView(
        apiClient: widget.apiClient,
        tasks: availableTasks,
        onLogout: widget.onLogout,
        onTaskUpdated: (updated) {
          setState(() {
            _tasks =
                _tasks.map((t) => t.id == updated.id ? updated : t).toList();
            _lastSync = DateTime.now();
          });
        },
      );
    }

    if (isCalendar) {
      final initialMode = switch (
          widget.userSettings.calendarDefaultMode.trim().toLowerCase()) {
        'day' => CalendarMode.day,
        'week' => CalendarMode.week,
        'month' => CalendarMode.month,
        _ => CalendarMode.week,
      };
      return CalendarView(
        tasks: _tasks,
        loading: _loading,
        saving: _saving,
        settings: widget.userSettings.calendarSettings,
        initialMode: initialMode,
        loadHolidayCnYear: _loadHolidayCnYear,
        onCreateTask: _createTaskFromCalendar,
        onRescheduleTask: _rescheduleTaskFromCalendar,
        onToggleTask: _toggleTask,
        onOpenTask: _openTaskDetailFromCalendar,
      );
    }

    if (isStats) {
      return StatsDashboardView(
        tasks: _tasks,
        timeStats: _timeStats,
        pomodoroSummary: _pomodoroSummary,
        pomodoroSessions: _pomodoroSessions,
        loading: _loadingStats,
        onRefresh: _loadTimeStats,
      );
    }

    return Column(
      key: const ValueKey('task_detail_column'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        const SizedBox(height: 12),
        Expanded(
          key: const ValueKey('task_detail_expanded'),
          child: Center(
            child: EmptyState(
              title: '${_workspace.label} 开发中',
              subtitle: '当前版本先体验任务列表，其他模块即将上线。',
            ),
          ),
        ),
      ],
    );
  }

  void _updateSearchQuery(String value) {
    if (_searchQuery == value) return;
    setState(() {
      _searchQuery = value;
      _selectedTaskId = null;
    });
  }

  Widget _buildQuickAddField(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.zero,
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.add_circle_outline, color: AppColors.accentCool),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _quickAddController,
                  enabled: !_saving,
                  decoration: InputDecoration(
                    hintText: _saving ? '正在保存...' : '输入任务名称，回车添加',
                    border: InputBorder.none,
                    isDense: true,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: _handleQuickAdd,
                ),
              ),
              IconButton(
                onPressed: _toggleQuickAddExpanded,
                icon: Icon(
                  _quickAddExpanded ? Icons.expand_less : Icons.expand_more,
                ),
                tooltip: _quickAddExpanded ? '收起' : '展开',
              ),
            ],
          ),
          if (_quickAddExpanded) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: SingleChildScrollView(
                key: const ValueKey('task_detail_scroll'),
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildQuickAddPicker(
                      context,
                      label: '开始日期',
                      value: _formatQuickAddDate(_quickAddDate),
                      width: 140,
                      onTap: _pickQuickAddDate,
                    ),
                    const SizedBox(width: 8),
                    _buildQuickAddPicker(
                      context,
                      label: '开始时间',
                      value: _formatQuickAddTime(context, _quickAddStartTime),
                      width: 120,
                      onTap: _pickQuickAddStartTime,
                    ),
                    const SizedBox(width: 8),
                    _buildQuickAddPicker(
                      context,
                      label: '截止时间',
                      value: _formatQuickAddTime(context, _quickAddEndTime),
                      width: 120,
                      onTap: _pickQuickAddEndTime,
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 1,
                      height: 18,
                      color: AppColors.outline,
                    ),
                    const SizedBox(width: 12),
                    _buildQuickAddAction(
                      icon: Icons.repeat,
                      label: _repeatSummary(),
                      active: _quickAddRepeat,
                      onTap: _openRepeatConfig,
                    ),
                    _buildQuickAddAction(
                      icon: Icons.notifications_none,
                      label: _remindSummary(),
                      active: _quickAddRemindAt != null,
                      onTap: _handleQuickAddRemindTap,
                    ),
                    _buildQuickAddAction(
                      icon: Icons.attach_file,
                      label: _attachmentSummary(),
                      active: _quickAddAttachments.isNotEmpty,
                      onTap: _pickQuickAddAttachments,
                    ),
                    _buildQuickAddAction(
                      icon: Icons.color_lens_outlined,
                      label: _quickAddColorHex.isEmpty
                          ? '颜色 $_quickAddDefaultColorLabel'
                          : '颜色 #${_quickAddColorHex.toUpperCase()}',
                      active: _quickAddColorHex.isNotEmpty,
                      onTap: _pickQuickAddColor,
                    ),
                    _buildQuickAddAction(
                      icon: Icons.playlist_add,
                      label: _subtaskSummary(),
                      active: _quickAddSubtasksExpanded ||
                          _quickAddSubtasks.isNotEmpty,
                      onTap: _toggleQuickAddSubtasks,
                    ),
                  ],
                ),
              ),
            ),
            if (_quickAddSubtasksExpanded) ...[
              const SizedBox(height: 10),
              _buildQuickAddSubtasks(context),
            ],
            if (_quickAddAttachments.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildQuickAddAttachments(context),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildChecklistQuickAddField(BuildContext context) {
    final disabled = _saving || _activeChecklistId == null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.zero,
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        children: [
          const Icon(Icons.playlist_add, color: AppColors.accentCool),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _checklistAddController,
              enabled: !disabled,
              decoration: InputDecoration(
                hintText: disabled ? '选择一个清单后添加事项' : '输入清单事项，回车添加',
                border: InputBorder.none,
                isDense: true,
                filled: false,
                contentPadding: EdgeInsets.zero,
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: _handleChecklistQuickAdd,
            ),
          ),
        ],
      ),
    );
  }

  _ParsedQuickAddInput _parseQuickAddInput(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return const _ParsedQuickAddInput(
          title: '', tags: [], dateOverride: null);
    }

    final tokens = trimmed
        .replaceAll('明天', ' 明天 ')
        .replaceAll('今天', ' 今天 ')
        .trim()
        .split(RegExp(r'\s+'));
    final titleParts = <String>[];
    final tags = <String>{};
    DateTime? dateOverride;

    for (final token in tokens) {
      final part = token.trim();
      if (part.isEmpty) continue;

      if (part == '今天') {
        dateOverride = DateTime.now();
        continue;
      }
      if (part == '明天') {
        dateOverride = DateTime.now().add(const Duration(days: 1));
        continue;
      }

      if (part.startsWith('#') && part.length > 1) {
        final cleaned = _sanitizeTag(part.substring(1));
        if (cleaned.isNotEmpty) tags.add(cleaned);
        continue;
      }

      titleParts.add(part);
    }

    return _ParsedQuickAddInput(
      title: titleParts.join(' ').trim(),
      tags: tags.toList(),
      dateOverride: dateOverride,
    );
  }

  String _sanitizeTag(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.replaceAll(RegExp(r'^[#]+'), '').replaceAll(
          RegExp(r'[，,。.!！？?]+$'),
          '',
        );
  }

  List<String> _buildTagsForNewTask(List<String> userTags) {
    final cleaned = userTags
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList();
    final deduped = <String>{...cleaned}.toList();

    List<String> tags = deduped;
    final checklistId = _activeChecklistId;
    if (checklistId != null) {
      tags = Task.applyChecklistTag(tags, checklistId);
    }
    if (_quickAddColorHex.trim().isNotEmpty) {
      tags = Task.applyColorTag(tags, _quickAddColorHex);
    }
    return tags;
  }

  Future<void> _handleQuickAdd(String value) async {
    final parsed = _parseQuickAddInput(value);
    final title = parsed.title.trim();
    if (title.isEmpty || _saving) return;
    _quickAddController.clear();
    FocusScope.of(context).unfocus();
    final subtasks = _buildSubtasksFromDrafts();
    final startTime = _timeToString(_quickAddStartTime);
    final endTime = _timeToString(_quickAddEndTime);
    final repeatRule = _quickAddRepeat ? _buildRepeatRule() : '';

    final tasksToCreate = <_QuickAddTaskDraft>[];
    if (_quickAddRepeat && _quickAddRepeatCount > 1) {
      final baseDate = parsed.dateOverride ?? _resolveBaseDateForRepeat();
      final dates = _buildRepeatDates(
        baseDate,
        _quickAddRepeatFrequency,
        _quickAddRepeatCount,
      );
      for (final date in dates) {
        tasksToCreate.add(
          _QuickAddTaskDraft(
            title: title,
            tags: _buildTagsForNewTask(parsed.tags),
            date: date,
            startTime: startTime,
            endTime: endTime,
            repeatRule: repeatRule,
            remindAt: _buildRemindAtForDate(date, baseDate),
            subtasks: subtasks,
          ),
        );
      }
    } else {
      tasksToCreate.add(
        _QuickAddTaskDraft(
          title: title,
          tags: _buildTagsForNewTask(parsed.tags),
          date: parsed.dateOverride ?? _quickAddDate,
          startTime: startTime,
          endTime: endTime,
          repeatRule: repeatRule,
          remindAt: _buildSingleRemindAt(),
          subtasks: subtasks,
        ),
      );
    }

    final created = await _addTasks(tasksToCreate);
    if (created.isNotEmpty && _quickAddAttachments.isNotEmpty) {
      await _uploadQuickAddAttachments(created.first);
    }
    _resetQuickAddForm();
  }

  void _toggleQuickAddExpanded() {
    setState(() => _quickAddExpanded = !_quickAddExpanded);
  }

  Future<void> _pickQuickAddDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _quickAddDate ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() => _quickAddDate = picked);
  }

  Future<void> _pickQuickAddStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _quickAddStartTime ?? TimeOfDay.now(),
    );
    if (picked == null) return;
    setState(() => _quickAddStartTime = picked);
  }

  Future<void> _pickQuickAddEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _quickAddEndTime ?? TimeOfDay.now(),
    );
    if (picked == null) return;
    setState(() => _quickAddEndTime = picked);
  }

  String _formatQuickAddDate(DateTime? date) {
    if (date == null) return '未设置';
    return DateFormat('M月d日').format(date);
  }

  String _formatQuickAddTime(BuildContext context, TimeOfDay? time) {
    if (time == null) return '未设置';
    return time.format(context);
  }

  String _timeToString(TimeOfDay? time) {
    if (time == null) return '';
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _repeatSummary() {
    if (!_quickAddRepeat) return '重复';
    final count = _quickAddRepeatCount.clamp(1, 99);
    switch (_quickAddRepeatFrequency) {
      case RepeatFrequency.daily:
        return '重复 每天×$count';
      case RepeatFrequency.weekly:
        final weekdays = _quickAddRepeatWeekdays.isNotEmpty
            ? _quickAddRepeatWeekdays
            : {_resolveBaseDateForRepeat().weekday};
        final labels = const ['一', '二', '三', '四', '五', '六', '日'];
        final sorted = weekdays.toList()..sort();
        final text = sorted.map((day) => labels[(day - 1).clamp(0, 6)]).join();
        return '重复 每周($text)×$count';
      case RepeatFrequency.monthly:
        final day = _quickAddRepeatMonthDay.clamp(1, 31);
        return '重复 每月${day}号×$count';
      case RepeatFrequency.yearly:
        final month = _quickAddRepeatYearMonth.clamp(1, 12);
        final day = _quickAddRepeatYearDay.clamp(1, 31);
        return '重复 每年${month}月${day}日×$count';
    }
  }

  String _remindSummary() {
    if (_quickAddRemindAt == null) return '提醒';
    final fmt = DateFormat('M/d HH:mm');
    return '提醒 ${fmt.format(_quickAddRemindAt!)}';
  }

  String _attachmentSummary() {
    if (_quickAddAttachments.isEmpty) return '附件';
    return '附件 ${_quickAddAttachments.length}';
  }

  String _subtaskSummary() {
    if (_quickAddSubtasks.isEmpty) return '子任务';
    return '子任务 ${_quickAddSubtasks.length}';
  }

  Future<void> _openRepeatConfig() async {
    final baseDate = _resolveBaseDateForRepeat();
    final countController = TextEditingController(
        text: _quickAddRepeatCount.clamp(1, 99).toString());
    RepeatFrequency tempFrequency = _quickAddRepeatFrequency;
    Set<int> tempWeekdays = _quickAddRepeatWeekdays.isNotEmpty
        ? Set<int>.from(_quickAddRepeatWeekdays)
        : {baseDate.weekday};
    int tempMonthDay = _quickAddRepeatMonthDay == 1 && !_quickAddRepeat
        ? baseDate.day
        : _quickAddRepeatMonthDay;
    tempMonthDay = tempMonthDay.clamp(1, 31);
    int tempYearMonth = _quickAddRepeatYearMonth;
    int tempYearDay = _quickAddRepeatYearDay;
    if (!_quickAddRepeat) {
      tempYearMonth = baseDate.month;
      tempYearDay = baseDate.day;
    }
    tempYearMonth = tempYearMonth.clamp(1, 12);
    tempYearDay = tempYearDay.clamp(1, 31);
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重复设置'),
        content: StatefulBuilder(
          builder: (context, setInnerState) {
            final weekdayLabels = const ['一', '二', '三', '四', '五', '六', '日'];
            final weekdayChips = Wrap(
              spacing: 6,
              runSpacing: 6,
              children: List.generate(7, (index) {
                final weekday = index + 1;
                final selected = tempWeekdays.contains(weekday);
                return FilterChip(
                  label: Text('周${weekdayLabels[index]}'),
                  selected: selected,
                  onSelected: (value) {
                    setInnerState(() {
                      if (value) {
                        tempWeekdays.add(weekday);
                        return;
                      }
                      if (tempWeekdays.length <= 1) return;
                      tempWeekdays.remove(weekday);
                    });
                  },
                );
              }),
            );

            final monthDayPicker = DropdownButtonFormField<int>(
              value: tempMonthDay,
              items: List.generate(
                31,
                (index) => DropdownMenuItem(
                  value: index + 1,
                  child: Text('${index + 1}号'),
                ),
              ),
              onChanged: (value) {
                if (value == null) return;
                setInnerState(() => tempMonthDay = value);
              },
              decoration: const InputDecoration(labelText: '每月几号'),
            );

            final yearMonthPicker = DropdownButtonFormField<int>(
              value: tempYearMonth,
              items: List.generate(
                12,
                (index) => DropdownMenuItem(
                  value: index + 1,
                  child: Text('${index + 1}月'),
                ),
              ),
              onChanged: (value) {
                if (value == null) return;
                setInnerState(() => tempYearMonth = value);
              },
              decoration: const InputDecoration(labelText: '月份'),
            );
            final yearDayPicker = DropdownButtonFormField<int>(
              value: tempYearDay,
              items: List.generate(
                31,
                (index) => DropdownMenuItem(
                  value: index + 1,
                  child: Text('${index + 1}号'),
                ),
              ),
              onChanged: (value) {
                if (value == null) return;
                setInnerState(() => tempYearDay = value);
              },
              decoration: const InputDecoration(labelText: '日期'),
            );

            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<RepeatFrequency>(
                    value: tempFrequency,
                    items: RepeatFrequency.values
                        .map(
                          (freq) => DropdownMenuItem(
                            value: freq,
                            child: Text(freq.label),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setInnerState(() {
                        tempFrequency = value;
                        if (tempFrequency == RepeatFrequency.weekly &&
                            tempWeekdays.isEmpty) {
                          tempWeekdays = {baseDate.weekday};
                        }
                      });
                    },
                    decoration: const InputDecoration(labelText: '频率'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: countController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '重复次数'),
                  ),
                  if (tempFrequency == RepeatFrequency.weekly) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '星期几',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                    const SizedBox(height: 6),
                    weekdayChips,
                  ],
                  if (tempFrequency == RepeatFrequency.monthly) ...[
                    const SizedBox(height: 12),
                    monthDayPicker,
                  ],
                  if (tempFrequency == RepeatFrequency.yearly) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: yearMonthPicker),
                        const SizedBox(width: 12),
                        Expanded(child: yearDayPicker),
                      ],
                    ),
                  ],
                ],
              ),
            );
          },
        ),
        actions: [
          if (_quickAddRepeat)
            TextButton(
              onPressed: () => Navigator.of(context).pop('clear'),
              child: const Text('关闭重复'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop('ok'),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (action == null) return;
    if (action == 'clear') {
      setState(() {
        _quickAddRepeat = false;
        _quickAddRepeatFrequency = RepeatFrequency.daily;
        _quickAddRepeatCount = 1;
        _quickAddRepeatWeekdays = {};
        _quickAddRepeatMonthDay = 1;
        _quickAddRepeatYearMonth = 1;
        _quickAddRepeatYearDay = 1;
      });
      return;
    }

    final parsedCount = int.tryParse(countController.text.trim()) ?? 1;
    setState(() {
      _quickAddRepeat = true;
      _quickAddRepeatFrequency = tempFrequency;
      _quickAddRepeatCount = parsedCount.clamp(1, 99);
      _quickAddRepeatWeekdays = tempWeekdays.isEmpty
          ? {baseDate.weekday}
          : Set<int>.from(tempWeekdays);
      _quickAddRepeatMonthDay = tempMonthDay.clamp(1, 31);
      _quickAddRepeatYearMonth = tempYearMonth.clamp(1, 12);
      _quickAddRepeatYearDay = tempYearDay.clamp(1, 31);
    });
  }

  Future<void> _handleQuickAddRemindTap() async {
    if (_quickAddRemindAt != null) {
      final action = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('提醒时间'),
          content: Text('当前提醒：${_remindSummary().replaceFirst('提醒 ', '')}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop('clear'),
              child: const Text('清除'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop('edit'),
              child: const Text('修改'),
            ),
          ],
        ),
      );
      if (action == 'clear') {
        setState(() => _quickAddRemindAt = null);
        return;
      }
      if (action != 'edit') return;
    }
    await _pickQuickAddReminder();
  }

  Future<void> _pickQuickAddReminder() async {
    final baseDate = _quickAddDate ?? DateTime.now();
    final initialDate = _quickAddRemindAt ?? baseDate;
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (pickedDate == null) return;
    final initialTime = _quickAddRemindAt != null
        ? TimeOfDay.fromDateTime(_quickAddRemindAt!)
        : TimeOfDay.now();
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );
    if (pickedTime == null) return;
    setState(() {
      _quickAddRemindAt = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }

  Future<void> _pickQuickAddAttachments() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: _allowedAttachmentExts,
    );
    if (result == null) return;

    final nextFiles = <PlatformFile>[];
    var totalBytes = _quickAddAttachmentBytes;
    for (final file in result.files) {
      final ext = (file.extension ?? '').toLowerCase();
      if (ext.isEmpty || !_allowedAttachmentExts.contains(ext)) {
        _showQuickAddHint('文件格式不支持：${file.name}');
        continue;
      }
      if (file.bytes == null) {
        _showQuickAddHint('无法读取文件：${file.name}');
        continue;
      }
      if (totalBytes + file.size > _attachmentTotalLimit) {
        _showQuickAddHint('附件总大小不能超过50MB');
        break;
      }
      totalBytes += file.size;
      nextFiles.add(file);
    }

    if (nextFiles.isEmpty) return;
    setState(() {
      _quickAddAttachments.addAll(nextFiles);
      _quickAddAttachmentBytes = totalBytes;
    });
  }

  void _toggleQuickAddSubtasks() {
    setState(() {
      _quickAddSubtasksExpanded = !_quickAddSubtasksExpanded;
      if (_quickAddSubtasksExpanded && _quickAddSubtasks.isEmpty) {
        _quickAddSubtasks
            .add(_SubtaskDraft(id: _generateSubtaskId(), title: ''));
      }
    });
  }

  Future<void> _pickQuickAddColor() async {
    final picked =
        await showTaskColorPicker(context, selectedHex: _quickAddColorHex);
    if (picked == null) return;
    if (!mounted) return;
    setState(() => _quickAddColorHex = picked);
  }

  Widget _buildQuickAddSubtasks(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ..._quickAddSubtasks.map(
          (draft) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    key: ValueKey(draft.id),
                    initialValue: draft.title,
                    onChanged: (value) => draft.title = value,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) =>
                        _handleQuickAdd(_quickAddController.text),
                    decoration: InputDecoration(
                      hintText: '子任务内容',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(
                          borderSide: BorderSide(color: AppColors.outline)),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  onPressed: () => _removeSubtaskDraft(draft.id),
                  icon: const Icon(Icons.close, size: 16),
                  tooltip: '删除子任务',
                ),
              ],
            ),
          ),
        ),
        TextButton.icon(
          onPressed: _addSubtaskDraft,
          icon: const Icon(Icons.add, size: 16),
          label: const Text('添加子任务'),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape:
                const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickAddAttachments(BuildContext context) {
    final sizeLabel = _formatAttachmentSize(_quickAddAttachmentBytes);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '附件 ${_quickAddAttachments.length} · $sizeLabel',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.inkSoft,
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _quickAddAttachments
              .map(
                (file) => Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: AppColors.outline),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        file.name,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () => _removeQuickAddAttachment(file),
                        child: const Icon(Icons.close,
                            size: 12, color: AppColors.inkSoft),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  List<TaskSubtask> _buildSubtasksFromDrafts() {
    return _quickAddSubtasks
        .map(
          (draft) => TaskSubtask(
            id: draft.id,
            title: draft.title.trim(),
            completed: false,
          ),
        )
        .where((item) => item.title.isNotEmpty)
        .toList();
  }

  String _buildRepeatRule() {
    if (!_quickAddRepeat) return '';
    final count = _quickAddRepeatCount.clamp(1, 99);
    final baseDate = _resolveBaseDateForRepeat();
    switch (_quickAddRepeatFrequency) {
      case RepeatFrequency.daily:
        return jsonEncode(
            {'freq': _quickAddRepeatFrequency.name, 'count': count});
      case RepeatFrequency.weekly:
        final weekdays = (_quickAddRepeatWeekdays.isNotEmpty
                ? _quickAddRepeatWeekdays
                : {baseDate.weekday})
            .toList()
          ..sort();
        return jsonEncode({
          'freq': _quickAddRepeatFrequency.name,
          'count': count,
          'weekdays': weekdays,
        });
      case RepeatFrequency.monthly:
        return jsonEncode({
          'freq': _quickAddRepeatFrequency.name,
          'count': count,
          'day': _quickAddRepeatMonthDay.clamp(1, 31),
        });
      case RepeatFrequency.yearly:
        return jsonEncode({
          'freq': _quickAddRepeatFrequency.name,
          'count': count,
          'month': _quickAddRepeatYearMonth.clamp(1, 12),
          'day': _quickAddRepeatYearDay.clamp(1, 31),
        });
    }
  }

  DateTime _resolveBaseDateForRepeat() {
    if (_quickAddDate != null) return _quickAddDate!;
    final defaults = _resolveTaskDefaults(null);
    if (defaults.dueDate.isNotEmpty) {
      try {
        return _dateFormatter.parse(defaults.dueDate);
      } catch (_) {}
    }
    return DateTime.now();
  }

  List<DateTime> _buildRepeatDates(
    DateTime baseDate,
    RepeatFrequency frequency,
    int count,
  ) {
    final dates = <DateTime>[];
    final total = count.clamp(1, 99);
    final start = DateTime(baseDate.year, baseDate.month, baseDate.day);

    DateTime clampedDate(int year, int month, int day) {
      final safeMonth = month.clamp(1, 12);
      final maxDay = DateTime(year, safeMonth + 1, 0).day;
      final safeDay = day.clamp(1, maxDay);
      return DateTime(year, safeMonth, safeDay);
    }

    switch (frequency) {
      case RepeatFrequency.daily:
        var current = start;
        for (var i = 0; i < total; i++) {
          dates.add(current);
          current = current.add(const Duration(days: 1));
        }
        return dates;
      case RepeatFrequency.weekly:
        final weekdays = _quickAddRepeatWeekdays.isNotEmpty
            ? _quickAddRepeatWeekdays
            : {start.weekday};
        var current = start;
        while (dates.length < total) {
          if (weekdays.contains(current.weekday)) dates.add(current);
          current = current.add(const Duration(days: 1));
        }
        return dates;
      case RepeatFrequency.monthly:
        final targetDay = _quickAddRepeatMonthDay.clamp(1, 31);
        var year = start.year;
        var month = start.month;
        while (dates.length < total) {
          final candidate = clampedDate(year, month, targetDay);
          if (dates.isNotEmpty || !candidate.isBefore(start)) {
            dates.add(candidate);
          }
          month += 1;
          if (month > 12) {
            month = 1;
            year += 1;
          }
        }
        return dates;
      case RepeatFrequency.yearly:
        final targetMonth = _quickAddRepeatYearMonth.clamp(1, 12);
        final targetDay = _quickAddRepeatYearDay.clamp(1, 31);
        var year = start.year;
        while (dates.length < total) {
          final candidate = clampedDate(year, targetMonth, targetDay);
          if (dates.isNotEmpty || !candidate.isBefore(start)) {
            dates.add(candidate);
          }
          year += 1;
        }
        return dates;
    }
  }

  int? _buildSingleRemindAt() {
    if (_quickAddRemindAt == null) return null;
    return _quickAddRemindAt!.toUtc().millisecondsSinceEpoch;
  }

  int? _buildRemindAtForDate(DateTime date, DateTime baseDate) {
    if (_quickAddRemindAt == null) return null;
    final baseStart = DateTime(baseDate.year, baseDate.month, baseDate.day);
    final offset = _quickAddRemindAt!.difference(baseStart);
    final target = DateTime(date.year, date.month, date.day).add(offset);
    return target.toUtc().millisecondsSinceEpoch;
  }

  void _resetQuickAddForm() {
    setState(() {
      _quickAddDate = null;
      _quickAddStartTime = null;
      _quickAddEndTime = null;
      _quickAddRepeat = false;
      _quickAddRepeatFrequency = RepeatFrequency.daily;
      _quickAddRepeatCount = 1;
      _quickAddRepeatWeekdays = {};
      _quickAddRepeatMonthDay = 1;
      _quickAddRepeatYearMonth = 1;
      _quickAddRepeatYearDay = 1;
      _quickAddRemindAt = null;
      _quickAddColorHex = '';
      _quickAddAttachments.clear();
      _quickAddAttachmentBytes = 0;
      _quickAddSubtasks.clear();
      _quickAddSubtasksExpanded = false;
    });
  }

  Future<void> _uploadQuickAddAttachments(Task task) async {
    for (final file in _quickAddAttachments) {
      final bytes = file.bytes;
      if (bytes == null) continue;
      try {
        final attachment = await widget.apiClient.uploadAttachment(
          taskId: task.id,
          filename: file.name,
          bytes: bytes,
        );
        _appendAttachment(task.id, attachment);
      } catch (_) {
        _showQuickAddHint('附件上传失败：${file.name}');
      }
    }
  }

  void _appendAttachment(String taskId, TaskAttachment attachment) {
    final index = _tasks.indexWhere((item) => item.id == taskId);
    if (index == -1) return;
    final task = _tasks[index];
    final updated = task.copyWith(
      attachments: [...task.attachments, attachment],
    );
    setState(() {
      _tasks = [
        ..._tasks.sublist(0, index),
        updated,
        ..._tasks.sublist(index + 1),
      ];
    });
  }

  void _addSubtaskDraft() {
    setState(() {
      _quickAddSubtasksExpanded = true;
      _quickAddSubtasks.add(_SubtaskDraft(id: _generateSubtaskId(), title: ''));
    });
  }

  void _removeSubtaskDraft(String id) {
    setState(() {
      _quickAddSubtasks.removeWhere((draft) => draft.id == id);
      if (_quickAddSubtasks.isEmpty) _quickAddSubtasksExpanded = false;
    });
  }

  void _removeQuickAddAttachment(PlatformFile file) {
    setState(() {
      _quickAddAttachments.remove(file);
      _quickAddAttachmentBytes =
          _quickAddAttachments.fold<int>(0, (sum, item) => sum + item.size);
    });
  }

  String _generateSubtaskId() =>
      DateTime.now().microsecondsSinceEpoch.toString();

  String _formatAttachmentSize(int bytes) {
    if (bytes <= 0) return '0B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)}KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)}MB';
  }

  Widget _buildQuickAddPicker(
    BuildContext context, {
    required String label,
    required String value,
    required double width,
    required VoidCallback onTap,
  }) {
    final hasValue = value.isNotEmpty && value != '未设置';
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.outline),
          ),
          child: Row(
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.inkSoft,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: hasValue ? AppColors.ink : AppColors.inkSoft,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickAddAction({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    final color = active ? AppColors.accentDeep : AppColors.inkSoft;
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label, overflow: TextOverflow.ellipsis),
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        textStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  void _showQuickAddHint(String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _clearSearch() {
    _searchController.clear();
    _updateSearchQuery('');
  }

  void _selectTask(String id) {
    setState(() {
      _selectedTaskId = _selectedTaskId == id ? null : id;
    });
  }

  void _clearSelectedTask() {
    if (_selectedTaskId == null) return;
    setState(() => _selectedTaskId = null);
  }

  void _setFilter(TaskFilter filter) {
    if (_filter == filter) return;
    setState(() {
      _filter = filter;
      _activeChecklistId = null;
      _showTrash = false;
      _selectedTaskId = null;
    });
  }

  void _openTrash() {
    if (_showTrash) return;
    setState(() {
      _showTrash = true;
      _activeChecklistId = null;
      _selectedTaskId = null;
    });
  }

  void _closeTrash() {
    if (!_showTrash) return;
    setState(() {
      _showTrash = false;
      _selectedTaskId = null;
    });
  }

  ChecklistList? _findChecklistById(int? id) {
    if (id == null) return null;
    for (final list in _checklists) {
      if (list.id == id) return list;
    }
    return null;
  }

  void _selectChecklist(int listId) {
    if (_activeChecklistId == listId && !_showTrash) return;
    setState(() {
      _activeChecklistId = listId;
      _showTrash = false;
      _selectedTaskId = null;
    });
    if (!_checklistItems.containsKey(listId) && _loadingChecklistId != listId) {
      _loadChecklistItems(listId);
    }
  }

  void _closeChecklistView() {
    if (_activeChecklistId == null) return;
    setState(() {
      _activeChecklistId = null;
      _selectedTaskId = null;
    });
  }

  Future<void> _promptCreateChecklist() async {
    if (_saving) return;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建清单'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '清单名称',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    controller.dispose();
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) return;

    setState(() => _saving = true);
    try {
      final created = await widget.apiClient.createChecklist(name: trimmed);
      setState(() {
        _checklists = [..._checklists, created];
        _activeChecklistId = created.id;
        _showTrash = false;
        _selectedTaskId = null;
      });
      await _loadChecklistItems(created.id);
    } on UnauthorizedException {
      widget.onLogout();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('创建清单失败。')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDeleteChecklist(ChecklistList list) async {
    if (_saving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除清单'),
        content: Text('确定要删除清单「${list.name}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      await widget.apiClient.deleteChecklist(list.id);
      if (!context.mounted) return;
      setState(() {
        _checklists = _checklists.where((item) => item.id != list.id).toList();
        _checklistItems.remove(list.id);
        if (_activeChecklistId == list.id) _activeChecklistId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已删除清单。')),
      );
    } on UnauthorizedException {
      widget.onLogout();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('删除清单失败。')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _handleChecklistQuickAdd(String value) async {
    final title = value.trim();
    final listId = _activeChecklistId;
    if (title.isEmpty || listId == null || _saving) return;

    _checklistAddController.clear();
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      final created = await widget.apiClient
          .createChecklistItem(listId: listId, title: title);
      if (!context.mounted) return;
      setState(() {
        final existing = _checklistItems[listId] ?? <ChecklistItem>[];
        _checklistItems[listId] = [...existing, created];
      });
    } on UnauthorizedException {
      widget.onLogout();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('创建清单事项失败。')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleChecklistItem(ChecklistItem item) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final updated = await widget.apiClient.updateChecklistItem(
        listId: item.listId,
        itemId: item.id,
        completed: !item.completed,
      );
      if (!context.mounted) return;
      setState(() {
        final items = _checklistItems[item.listId] ?? <ChecklistItem>[];
        _checklistItems[item.listId] =
            items.map((it) => it.id == item.id ? updated : it).toList();
      });
    } on UnauthorizedException {
      widget.onLogout();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('更新清单事项失败。')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDeleteChecklistItem(ChecklistItem item) async {
    if (_saving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除事项'),
        content: Text('确定要删除「${item.title}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      await widget.apiClient
          .deleteChecklistItem(listId: item.listId, itemId: item.id);
      if (!context.mounted) return;
      setState(() {
        final items = _checklistItems[item.listId] ?? <ChecklistItem>[];
        _checklistItems[item.listId] =
            items.where((it) => it.id != item.id).toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已删除事项。')),
      );
    } on UnauthorizedException {
      widget.onLogout();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('删除事项失败。')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _moveTaskToTrash(Task task) async {
    if (_saving) return false;
    setState(() => _saving = true);
    try {
      await widget.apiClient.deleteTask(task.id);
      if (!context.mounted) return false;
      if (_selectedTaskId == task.id) {
        setState(() => _selectedTaskId = null);
      }
      await _loadTasks();
      if (!context.mounted) return false;
      final controller = ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('已移入回收站。'),
          duration: const Duration(seconds: 1),
          action: SnackBarAction(
            label: '查看',
            onPressed: _openTrash,
          ),
        ),
      );
      Future.delayed(const Duration(seconds: 1), () {
        if (!context.mounted) return;
        controller.close();
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      });
      return true;
    } on UnauthorizedException {
      widget.onLogout();
      return false;
    } catch (_) {
      if (!context.mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('删除任务失败。')),
      );
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _restoreTask(Task task) async {
    await _updateTaskFromDetail(task, clearDeletedAt: true);
  }

  Future<void> _confirmEmptyTrash() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空回收站'),
        content: const Text('确定要永久删除回收站中的所有任务吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _emptyTrash();
  }

  Future<void> _emptyTrash() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final purged = await widget.apiClient.emptyTrash();
      await _loadTasks();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已清空回收站（$purged 个任务）。')),
      );
    } on UnauthorizedException {
      widget.onLogout();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('清空回收站失败。')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Task? _findTaskById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final task in _tasks) {
      if (task.id == id) return task;
    }
    return null;
  }

  List<Task> _applySearch(List<Task> tasks) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return tasks;
    return tasks.where((task) {
      final haystack = [
        task.title,
        task.notes,
        task.dueDate,
        task.displayTags.join(' '),
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  List<ChecklistItem> _applyChecklistSearch(List<ChecklistItem> items) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return items;
    return items.where((item) {
      final haystack = [
        item.title,
        item.notes,
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  void _selectWorkspace(WorkspaceView view) {
    if (_workspace == view) return;
    setState(() {
      _workspace = view;
      if (view != WorkspaceView.tasks) {
        _showTrash = false;
        _searchQuery = '';
        _selectedTaskId = null;
        _searchController.clear();
      }
    });
    if (view == WorkspaceView.timeTracking &&
        _activities.isEmpty &&
        !_loadingTime) {
      _loadTimeTracking();
    }
    if (view == WorkspaceView.stats &&
        (_timeStats == null || _pomodoroSummary == null) &&
        !_loadingStats) {
      _loadTimeStats();
    }
  }

  void _applyDefaultView(String raw, {bool initial = false}) {
    final view = raw.trim();
    if (view == 'checklists') {
      if (initial) {
        _workspace = WorkspaceView.tasks;
        if (_checklists.isNotEmpty) {
          _activeChecklistId = _checklists.first.id;
        }
      } else {
        _selectWorkspace(WorkspaceView.tasks);
        if (_checklists.isNotEmpty) {
          _selectChecklist(_checklists.first.id);
        }
      }
      return;
    }

    if (initial) {
      _workspace = WorkspaceView.tasks;
    } else {
      _selectWorkspace(WorkspaceView.tasks);
    }

    TaskFilter nextFilter;
    switch (view) {
      case 'today':
        nextFilter = TaskFilter.today;
        break;
      case 'inbox':
      default:
        nextFilter = TaskFilter.inbox;
        break;
    }
    if (initial) {
      _filter = nextFilter;
    } else {
      _setFilter(nextFilter);
    }
  }

  void _setDefaultStatsRange() {
    final now = DateTime.now().toUtc();
    final start = now.subtract(const Duration(days: 6));
    _statsFrom =
        DateTime.utc(start.year, start.month, start.day).millisecondsSinceEpoch;
    _statsTo = now.millisecondsSinceEpoch;
  }

  String _statsRangeLabel() {
    if (_statsFrom == 0 || _statsTo == 0) return '近7天 · UTC';
    final from = DateTime.fromMillisecondsSinceEpoch(_statsFrom, isUtc: true);
    final to = DateTime.fromMillisecondsSinceEpoch(_statsTo, isUtc: true);
    final fmt = DateFormat('M月d日');
    return '${fmt.format(from)} - ${fmt.format(to)} · UTC';
  }

  String _formatDuration(int ms) {
    if (ms <= 0) return '0分钟';
    final totalSeconds = (ms / 1000).floor();
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    if (hours > 0) return '$hours小时${minutes}分钟';
    if (minutes > 0) return '$minutes分钟';
    return '${totalSeconds}秒';
  }

  Future<void> _loadTimeTracking() async {
    setState(() => _loadingTime = true);
    try {
      final activities = await widget.apiClient.getActivities();
      final entries = await widget.apiClient.getEntries(limit: 200);
      final running = await widget.apiClient.getRunningEntries();
      activities.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      running.sort((a, b) => b.startedAt.compareTo(a.startedAt));
      setState(() {
        _activities = activities;
        _timeEntries = entries
            .where((entry) => entry.deletedAt == null)
            .toList()
          ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
        _runningEntries = running.where((entry) => entry.isRunning).toList();
        _lastTimeSync = DateTime.now();
      });
    } on UnauthorizedException {
      widget.onLogout();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('加载时间记录失败。')),
      );
    } finally {
      if (mounted) setState(() => _loadingTime = false);
    }
  }

  Future<void> _loadTimeStats() async {
    setState(() => _loadingStats = true);
    try {
      if (_statsFrom == 0 || _statsTo == 0) {
        _setDefaultStatsRange();
      }
      final statsFuture =
          widget.apiClient.getTimeStats(from: _statsFrom, to: _statsTo);
      final summaryFuture = widget.apiClient.getPomodoroSummary(days: 14);
      final sessionsFuture = widget.apiClient.getPomodoroSessions(limit: 200);
      final stats = await statsFuture;
      final summary = await summaryFuture;
      final sessions = await sessionsFuture
        ..sort((a, b) => b.endedAt.compareTo(a.endedAt));
      setState(() {
        _timeStats = stats;
        _pomodoroSummary = summary;
        _pomodoroSessions = sessions;
      });
    } on UnauthorizedException {
      widget.onLogout();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('加载统计失败。')),
      );
    } finally {
      if (mounted) setState(() => _loadingStats = false);
    }
  }

  Future<void> _openActivityEditor({TimeActivity? activity}) async {
    final availableTasks =
        _tasks.where((task) => task.deletedAt == null).toList();
    final draft = await showModalBottomSheet<TimeActivityDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => TimeActivityEditorSheet(
        tasks: availableTasks,
        activity: activity,
      ),
    );
    if (draft == null) return;

    setState(() => _savingTime = true);
    try {
      final updated = activity == null
          ? await widget.apiClient.createActivity(
              name: draft.name,
              taskId: draft.taskId,
              icon: draft.icon,
              color: draft.color,
              category: draft.category,
              goal: draft.goal,
              note: draft.note,
            )
          : await widget.apiClient.updateActivity(
              activity.id,
              name: draft.name,
              taskId: draft.taskId,
              icon: draft.icon,
              color: draft.color,
              category: draft.category,
              goal: draft.goal,
              note: draft.note,
            );
      final next = [..._activities];
      final index = next.indexWhere((item) => item.id == updated.id);
      if (index == -1) {
        next.add(updated);
      } else {
        next[index] = updated;
      }
      next.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      setState(() {
        _activities = next;
        _lastTimeSync = DateTime.now();
      });
    } on UnauthorizedException {
      widget.onLogout();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('保存事件失败。')),
      );
    } finally {
      if (mounted) setState(() => _savingTime = false);
    }
  }

  Future<void> _toggleActivity(TimeActivity activity) async {
    setState(() => _savingTime = true);
    try {
      final running = _runningEntries.where((entry) => entry.isRunning).toList()
        ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
      final wasRunning =
          running.any((entry) => entry.activityId == activity.id);

      if (running.isNotEmpty) {
        final stopped = await Future.wait(
            running.map((entry) => widget.apiClient.stopEntry(entry.id)));
        setState(() {
          _runningEntries = <TimeEntry>[];
          _timeEntries = _mergeTimeEntries(_timeEntries, stopped);
          _lastTimeSync = DateTime.now();
        });
      }

      if (wasRunning) return;
      final entry = await widget.apiClient.startEntry(
        activityId: activity.id,
        taskId: activity.taskId,
      );
      setState(() {
        _runningEntries = [entry];
        _timeEntries = _mergeTimeEntries(_timeEntries, [entry]);
        _lastTimeSync = DateTime.now();
      });
    } on UnauthorizedException {
      widget.onLogout();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('计时操作失败。')),
      );
    } finally {
      if (mounted) setState(() => _savingTime = false);
    }
  }

  Future<void> _openEntryEditor(TimeEntry entry) async {
    final result = await showModalBottomSheet<TimeEntryEditResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => TimeEntryEditorSheet(
        entry: entry,
        activities: _activities
            .where((activity) => activity.deletedAt == null)
            .toList(),
      ),
    );
    if (result == null) return;

    setState(() => _savingTime = true);
    try {
      if (result.deleteEntry) {
        await widget.apiClient.deleteEntry(entry.id);
        setState(() {
          _timeEntries = _timeEntries
              .where((candidate) => candidate.id != entry.id)
              .toList();
          _runningEntries = _runningEntries
              .where((candidate) => candidate.id != entry.id)
              .toList();
          _lastTimeSync = DateTime.now();
        });
        return;
      }

      if (result.activityIcon != null || result.activityName != null) {
        TimeActivity? activity;
        for (final candidate in _activities) {
          if (candidate.id == result.activityId) {
            activity = candidate;
            break;
          }
        }
        if (activity != null) {
          final updated = await widget.apiClient.updateActivity(
            activity.id,
            name: result.activityName,
            icon: result.activityIcon,
          );
          setState(() {
            final next = [..._activities];
            final index = next.indexWhere((item) => item.id == updated.id);
            if (index == -1) {
              next.add(updated);
            } else {
              next[index] = updated;
            }
            next.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
            _activities = next;
          });
        }
      }

      final updatedEntry = await widget.apiClient.updateEntry(
        entry.id,
        activityId: result.activityId,
        startedAt: result.startedAt,
        endedAt: result.endedAt,
        clearEndedAt: result.endedAt == null && entry.endedAt != null,
        note: result.note.trim(),
        tags: result.tags,
      );

      setState(() {
        _timeEntries = _mergeTimeEntries(_timeEntries, [updatedEntry]);
        if (updatedEntry.isRunning) {
          _runningEntries = [updatedEntry];
        } else {
          _runningEntries = _runningEntries
              .where((candidate) => candidate.id != updatedEntry.id)
              .toList();
        }
        _lastTimeSync = DateTime.now();
      });
    } on UnauthorizedException {
      widget.onLogout();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('保存记录失败。')),
      );
    } finally {
      if (mounted) setState(() => _savingTime = false);
    }
  }

  List<TimeEntry> _mergeTimeEntries(
      List<TimeEntry> existing, List<TimeEntry> updates) {
    if (updates.isEmpty) return existing;
    final byId = <String, TimeEntry>{
      for (final entry in existing) entry.id: entry
    };
    for (final entry in updates) {
      byId[entry.id] = entry;
    }
    final next = byId.values.toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return next;
  }

  Future<void> _confirmDeleteActivity(TimeActivity activity) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除事件'),
        content: Text('确定要删除“${activity.name}”吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _deleteActivity(activity);
  }

  Future<void> _deleteActivity(TimeActivity activity) async {
    setState(() => _savingTime = true);
    try {
      await widget.apiClient.deleteActivity(activity.id);
      setState(() {
        _activities =
            _activities.where((item) => item.id != activity.id).toList();
        _runningEntries = _runningEntries
            .where((entry) => entry.activityId != activity.id)
            .toList();
        _lastTimeSync = DateTime.now();
      });
    } on UnauthorizedException {
      widget.onLogout();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('删除事件失败。')),
      );
    } finally {
      if (mounted) setState(() => _savingTime = false);
    }
  }

  Future<List<Task>> _addTasks(List<_QuickAddTaskDraft> drafts) async {
    if (drafts.isEmpty) return [];
    final created = <Task>[];
    setState(() => _saving = true);
    try {
      for (final draft in drafts) {
        final defaults = _resolveTaskDefaults(draft.date);
        final task = await widget.apiClient.createTask(
          title: draft.title,
          notes: draft.notes,
          dueDate: defaults.dueDate,
          startTime: draft.startTime,
          endTime: draft.endTime,
          tags: draft.tags,
          repeatRule: draft.repeatRule,
          remindAt: draft.remindAt,
          subtasks: draft.subtasks,
          inbox: defaults.inbox,
          status: defaults.status,
        );
        created.add(task);
      }
      setState(() {
        _tasks = [..._tasks, ...created];
        _lastSync = DateTime.now();
        if (created.isNotEmpty) _selectedTaskId = created.last.id;
      });
    } on UnauthorizedException {
      widget.onLogout();
    } catch (_) {
      if (!mounted) return created;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('创建任务失败。')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    return created;
  }

  _TaskDefaults _resolveTaskDefaults(DateTime? date) {
    if (_activeChecklistId != null) {
      final dueDate = date != null ? _dateFormatter.format(date) : '';
      return _TaskDefaults(
        dueDate: dueDate,
        inbox: false,
        status: 'todo',
      );
    }

    final now = DateTime.now();
    final today = _dateFormatter.format(now);
    final tomorrow = _dateFormatter.format(now.add(const Duration(days: 1)));

    String dueDate = date != null ? _dateFormatter.format(date) : '';
    bool inbox = false;
    String status = 'todo';

    if (dueDate.isEmpty) {
      switch (_filter) {
        case TaskFilter.today:
          dueDate = today;
          break;
        case TaskFilter.tomorrow:
          dueDate = tomorrow;
          break;
        case TaskFilter.next7:
          dueDate = today;
          break;
        case TaskFilter.done:
          status = 'completed';
          break;
        case TaskFilter.all:
          break;
        case TaskFilter.inbox:
          inbox = true;
          break;
      }
    }
    if (dueDate.isEmpty && status != 'completed') {
      inbox = true;
    }

    return _TaskDefaults(
      dueDate: dueDate,
      inbox: inbox,
      status: status,
    );
  }

  Future<void> _toggleTask(Task task) async {
    setState(() => _saving = true);
    try {
      final updated = await widget.apiClient.updateTask(
        task.id,
        status: task.isCompleted ? 'todo' : 'completed',
      );
      setState(() {
        _tasks = _tasks.map((t) => t.id == task.id ? updated : t).toList();
        _lastSync = DateTime.now();
      });
    } on UnauthorizedException {
      widget.onLogout();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('更新任务失败。')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleSubtask(Task task, TaskSubtask subtask) async {
    final updatedSubtasks = task.subtasks
        .map(
          (item) => item.id == subtask.id
              ? item.copyWith(completed: !item.completed)
              : item,
        )
        .toList();
    final allDone = updatedSubtasks.isNotEmpty &&
        updatedSubtasks.every((item) => item.completed);
    final status = allDone ? 'completed' : 'todo';
    setState(() => _saving = true);
    try {
      final updated = await widget.apiClient.updateTask(
        task.id,
        status: status,
        subtasks: updatedSubtasks,
      );
      setState(() {
        _tasks = _tasks.map((t) => t.id == task.id ? updated : t).toList();
        _lastSync = DateTime.now();
      });
    } on UnauthorizedException {
      widget.onLogout();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('更新子任务失败。')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _applyDropToFilter(Task task, TaskFilter target) async {
    if (_saving) return;

    final now = DateTime.now();
    final todayStr = _dateFormatter.format(now);
    final tomorrowStr = _dateFormatter.format(now.add(const Duration(days: 1)));
    final next7Str = _dateFormatter.format(now.add(const Duration(days: 7)));

    switch (target) {
      case TaskFilter.all:
        return;
      case TaskFilter.today:
        await _updateTaskFromDetail(
          task,
          dueDate: todayStr,
          inbox: false,
          status: 'todo',
        );
        break;
      case TaskFilter.tomorrow:
        await _updateTaskFromDetail(
          task,
          dueDate: tomorrowStr,
          inbox: false,
          status: 'todo',
        );
        break;
      case TaskFilter.next7:
        await _updateTaskFromDetail(
          task,
          dueDate: next7Str,
          inbox: false,
          status: 'todo',
        );
        break;
      case TaskFilter.inbox:
        await _updateTaskFromDetail(
          task,
          dueDate: '',
          tags: Task.stripSystemChecklistTags(task.tags),
          inbox: true,
          status: 'todo',
        );
        break;
      case TaskFilter.done:
        await _updateTaskFromDetail(
          task,
          status: 'completed',
          inbox: false,
        );
        break;
    }

    if (!context.mounted) return;
    setState(() {
      _filter = target;
      _showTrash = false;
      _activeChecklistId = null;
      _selectedTaskId = task.id;
    });
  }

  Future<void> _applyDropToChecklist(Task task, ChecklistList list) async {
    if (_saving) return;
    await _updateTaskFromDetail(
      task,
      tags: Task.applyChecklistTag(task.tags, list.id),
      inbox: false,
    );
    if (!context.mounted) return;
    setState(() {
      _activeChecklistId = list.id;
      _showTrash = false;
      _selectedTaskId = task.id;
    });
  }

  Future<void> _updateTaskFromDetail(
    Task task, {
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
    bool clearDeletedAt = false,
  }) async {
    setState(() => _saving = true);
    try {
      final updated = await widget.apiClient.updateTask(
        task.id,
        title: title,
        notes: notes,
        status: status,
        dueDate: dueDate,
        startTime: startTime,
        endTime: endTime,
        tags: tags,
        subtasks: subtasks,
        inbox: inbox,
        priority: priority,
        remindAt: remindAt,
        clearRemindAt: clearRemindAt,
        repeatRule: repeatRule,
        clearDeletedAt: clearDeletedAt,
      );
      setState(() {
        _tasks = _tasks.map((t) => t.id == task.id ? updated : t).toList();
        _lastSync = DateTime.now();
      });
    } on UnauthorizedException {
      widget.onLogout();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('更新任务失败。')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _promptEditTaskTitle(Task task) async {
    if (_saving) return;
    final controller = TextEditingController(text: task.title);
    final next = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('修改标题'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入任务标题'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!context.mounted) return;
    if (next == null) return;
    final trimmed = next.trim();
    if (trimmed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('标题不能为空。')),
      );
      return;
    }
    if (trimmed == task.title.trim()) return;
    await _updateTaskFromDetail(task, title: trimmed);
  }

  Future<void> _loadTasks() async {
    setState(() => _loading = true);
    try {
      final tasks =
          await widget.apiClient.getTasks(view: 'all', includeDeleted: true);
      tasks.sort(_sortTask);
      final selectedId = _selectedTaskId;
      final hasSelected =
          selectedId != null && tasks.any((task) => task.id == selectedId);
      setState(() {
        _tasks = tasks;
        _lastSync = DateTime.now();
        if (!hasSelected) _selectedTaskId = null;
      });
    } on UnauthorizedException {
      widget.onLogout();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('加载任务失败。')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<HolidayCnYear> _loadHolidayCnYear(int year) async {
    try {
      return await widget.apiClient.getHolidayCnYear(year);
    } on UnauthorizedException {
      widget.onLogout();
      rethrow;
    }
  }

  Future<Task?> _createTaskFromCalendar({
    required String title,
    required DateTime date,
    TimeOfDay? startTime,
  }) async {
    if (_saving) return null;
    setState(() => _saving = true);
    try {
      final dueDate = _dateFormatter.format(date);
      final start = _timeToString(startTime);
      String end = '';
      if (startTime != null) {
        final startMinutes = startTime.hour * 60 + startTime.minute;
        final endMinutes = startMinutes + 15;
        if (endMinutes <= 24 * 60) {
          final hour = (endMinutes ~/ 60).toString().padLeft(2, '0');
          final minute = (endMinutes % 60).toString().padLeft(2, '0');
          end = '$hour:$minute';
        }
      }
      final created = await widget.apiClient.createTask(
        title: title,
        dueDate: dueDate,
        startTime: start,
        endTime: end,
        inbox: false,
        status: 'todo',
      );
      final next = [..._tasks, created]..sort(_sortTask);
      setState(() {
        _tasks = next;
        _lastSync = DateTime.now();
        _selectedTaskId = created.id;
      });
      return created;
    } on UnauthorizedException {
      widget.onLogout();
    } catch (_) {
      if (!context.mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('创建任务失败。')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    return null;
  }

  Future<void> _rescheduleTaskFromCalendar(
    Task task, {
    required DateTime date,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
  }) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final dueDate = _dateFormatter.format(date);
      final start = startTime == null ? '' : _timeToString(startTime);
      var end = '';
      if (startTime != null) {
        final startMinutes = startTime.hour * 60 + startTime.minute;
        int endMinutes;
        if (endTime != null) {
          endMinutes = endTime.hour * 60 + endTime.minute;
          if (endMinutes == 0 && startMinutes > 0) endMinutes = 24 * 60;
        } else {
          final oldStart = _parseTimeMinutes(task.startTime);
          final oldEnd = _parseTimeMinutes(task.endTime);
          final duration =
              (oldStart != null && oldEnd != null && oldEnd > oldStart)
                  ? (oldEnd - oldStart)
                  : 15;
          endMinutes = startMinutes + duration;
        }
        endMinutes = endMinutes.clamp(startMinutes + 15, 24 * 60);
        end = _minutesToTimeString(endMinutes);
      }

      final updated = await widget.apiClient.updateTask(
        task.id,
        dueDate: dueDate,
        startTime: start,
        endTime: end,
        inbox: false,
      );
      final next = _tasks.map((t) => t.id == task.id ? updated : t).toList()
        ..sort(_sortTask);
      setState(() {
        _tasks = next;
        _lastSync = DateTime.now();
      });
    } on UnauthorizedException {
      widget.onLogout();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('更新任务失败。')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _minutesToTimeString(int minutes) {
    final clamped = minutes.clamp(0, 24 * 60);
    final hour = (clamped ~/ 60).toString().padLeft(2, '0');
    final minute = (clamped % 60).toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  int? _parseTimeMinutes(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final parts = trimmed.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 24) return null;
    if (minute < 0 || minute > 59) return null;
    if (hour == 24 && minute != 0) return null;
    return hour * 60 + minute;
  }

  void _openTaskDetailFromCalendar(Task task) {
    Task sheetTask = _findTaskById(task.id) ?? task;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final maxHeight = MediaQuery.of(sheetContext).size.height * 0.85;
        return SafeArea(
          child: StatefulBuilder(
            builder: (sheetContext, setSheetState) {
              Future<void> handleUpdate(
                Task task, {
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
                bool clearDeletedAt = false,
              }) async {
                await _updateTaskFromDetail(
                  task,
                  title: title,
                  notes: notes,
                  status: status,
                  dueDate: dueDate,
                  startTime: startTime,
                  endTime: endTime,
                  tags: tags,
                  subtasks: subtasks,
                  inbox: inbox,
                  priority: priority,
                  remindAt: remindAt,
                  clearRemindAt: clearRemindAt,
                  repeatRule: repeatRule,
                  clearDeletedAt: clearDeletedAt,
                );
                final updated = _findTaskById(task.id);
                if (updated == null) return;
                setSheetState(() => sheetTask = updated);
              }

              return Container(
                margin: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                constraints: BoxConstraints(maxHeight: maxHeight),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.outline),
                ),
                child: _TaskDetailPanel(
                  task: sheetTask,
                  saving: _saving,
                  onClose: () => Navigator.of(sheetContext).pop(),
                  onToggleSubtask: _toggleSubtask,
                  generateSubtaskId: _generateSubtaskId,
                  onUpdateTask: handleUpdate,
                  onDeleteTask: _moveTaskToTrash,
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _loadChecklists() async {
    setState(() => _loadingChecklists = true);
    try {
      final lists = await widget.apiClient.getChecklists();
      final activeId = _activeChecklistId;
      final stillActive =
          activeId != null && lists.any((list) => list.id == activeId);
      final wantsChecklists =
          widget.userSettings.preferences.defaultView.trim() == 'checklists';
      final defaultChecklistId =
          wantsChecklists && !stillActive && lists.isNotEmpty
              ? lists.first.id
              : null;
      if (!context.mounted) return;
      setState(() {
        _checklists = lists;
        if (stillActive) {
          _activeChecklistId = activeId;
        } else {
          _activeChecklistId = defaultChecklistId;
        }
      });
      if (defaultChecklistId != null) {
        await _loadChecklistItems(defaultChecklistId);
      }
      // Checklist definitions loaded; task membership is managed client-side.
    } on UnauthorizedException {
      widget.onLogout();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('加载清单失败。')),
      );
    } finally {
      if (mounted) setState(() => _loadingChecklists = false);
    }
  }

  Future<void> _loadChecklistItems(int listId) async {
    setState(() => _loadingChecklistId = listId);
    try {
      final items = await widget.apiClient.getChecklistItems(listId);
      if (!context.mounted) return;
      setState(() {
        _checklistItems[listId] = items;
      });
    } on UnauthorizedException {
      widget.onLogout();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('加载清单事项失败。')),
      );
    } finally {
      if (mounted) setState(() => _loadingChecklistId = null);
    }
  }

  Map<TaskFilter, int> _buildCounts() {
    final counts = <TaskFilter, int>{};
    for (final filter in TaskFilter.values) {
      counts[filter] = _applyFilter(_tasks, filter).length;
    }
    return counts;
  }

  Map<WorkspaceView, int> _buildWorkspaceCounts() {
    final visible = _tasks.where((task) => task.deletedAt == null).length;
    final visibleActivities =
        _activities.where((activity) => activity.deletedAt == null).length;
    return {
      WorkspaceView.tasks: visible,
      WorkspaceView.timeTracking: visibleActivities,
      WorkspaceView.calendar: 0,
      WorkspaceView.checklists: 0,
      WorkspaceView.pomodoro: 0,
      WorkspaceView.stats: 0,
    };
  }

  List<Task> _applyFilter(List<Task> tasks, TaskFilter filter) {
    final today = DateTime.now();
    final todayStr = _dateFormatter.format(today);
    final tomorrowStr =
        _dateFormatter.format(today.add(const Duration(days: 1)));
    final weekEnd = today.add(const Duration(days: 7));

    bool isWithinWeek(Task task) {
      if (task.dueDate.trim().isEmpty) return false;
      try {
        final date = _dateFormatter.parse(task.dueDate);
        return !date.isBefore(today) && !date.isAfter(weekEnd);
      } catch (_) {
        return false;
      }
    }

    final visible = tasks.where((task) => task.deletedAt == null).toList();
    List<Task> result;
    switch (filter) {
      case TaskFilter.inbox:
        result =
            visible.where((task) => task.inbox && !task.isCompleted).toList();
        break;
      case TaskFilter.today:
        result = visible
            .where((task) => task.dueDate == todayStr && !task.isCompleted)
            .toList();
        break;
      case TaskFilter.tomorrow:
        result = visible
            .where((task) => task.dueDate == tomorrowStr && !task.isCompleted)
            .toList();
        break;
      case TaskFilter.next7:
        result = visible
            .where((task) => !task.isCompleted && isWithinWeek(task))
            .toList();
        break;
      case TaskFilter.done:
        result = visible.where((task) => task.isCompleted).toList();
        break;
      case TaskFilter.all:
        result = visible;
        break;
    }
    result.sort(_sortTask);
    return result;
  }

  List<Task> _applyChecklistTasks(List<Task> tasks, int checklistId) {
    final visible = tasks.where((task) => task.deletedAt == null).toList();
    final result =
        visible.where((task) => task.checklistId == checklistId).toList();
    result.sort(_sortTask);
    return result;
  }

  List<Task> _applyTrash(List<Task> tasks) {
    final trashed = tasks.where((task) => task.deletedAt != null).toList();
    trashed.sort((a, b) {
      final aDeleted = a.deletedAt ?? 0;
      final bDeleted = b.deletedAt ?? 0;
      final deletedCompare = bDeleted.compareTo(aDeleted);
      if (deletedCompare != 0) return deletedCompare;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return trashed;
  }

  int _sortTask(Task a, Task b) {
    if (a.isCompleted != b.isCompleted) {
      return a.isCompleted ? 1 : -1;
    }
    if (a.dueDate.isEmpty && b.dueDate.isNotEmpty) return 1;
    if (a.dueDate.isNotEmpty && b.dueDate.isEmpty) return -1;
    if (a.dueDate.isNotEmpty && b.dueDate.isNotEmpty) {
      final dateCompare = a.dueDate.compareTo(b.dueDate);
      if (dateCompare != 0) return dateCompare;
    }
    return b.updatedAt.compareTo(a.updatedAt);
  }
}

class _HeaderBlock extends StatelessWidget {
  const _HeaderBlock({
    required this.title,
    required this.subtitle,
    required this.metaTitle,
    required this.metaSubtitle,
  });

  final String title;
  final String subtitle;
  final String metaTitle;
  final String metaSubtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.9),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.outline),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 520;
          final title = Text(
            this.title,
            style: GoogleFonts.fraunces(
              textStyle: Theme.of(context).textTheme.headlineSmall,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          );
          final body = Text(
            this.subtitle,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.inkSoft),
          );
          final stats = Column(
            crossAxisAlignment:
                isNarrow ? CrossAxisAlignment.start : CrossAxisAlignment.end,
            children: [
              Text(
                metaTitle,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                metaSubtitle,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.inkSoft),
              ),
            ],
          );

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title,
                const SizedBox(height: 6),
                body,
                const SizedBox(height: 12),
                stats,
              ],
            );
          }

          return Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title,
                    const SizedBox(height: 6),
                    body,
                  ],
                ),
              ),
              const SizedBox(width: 16),
              stats,
            ],
          );
        },
      ),
    );
  }
}

class _TaskFilterPanel extends StatelessWidget {
  const _TaskFilterPanel({
    required this.selected,
    required this.counts,
    required this.checklists,
    required this.activeChecklistId,
    required this.loadingChecklists,
    required this.saving,
    required this.username,
    required this.onSelect,
    required this.onSelectChecklist,
    required this.onCreateChecklist,
    required this.onDeleteChecklist,
    required this.onDropTask,
    required this.onDropChecklistTask,
  });

  final TaskFilter selected;
  final Map<TaskFilter, int> counts;
  final List<ChecklistList> checklists;
  final int? activeChecklistId;
  final bool loadingChecklists;
  final bool saving;
  final String username;
  final ValueChanged<TaskFilter> onSelect;
  final ValueChanged<int> onSelectChecklist;
  final VoidCallback onCreateChecklist;
  final ValueChanged<ChecklistList> onDeleteChecklist;
  final void Function(Task task, TaskFilter target) onDropTask;
  final void Function(Task task, ChecklistList list) onDropChecklistTask;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.95),
        borderRadius: BorderRadius.zero,
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '任务视图',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppColors.inkSoft,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                ),
          ),
          const SizedBox(height: 12),
          ...TaskFilter.values.map(
            (filter) => _TaskFilterTile(
              filter: filter,
              selected: activeChecklistId == null && selected == filter,
              count: counts[filter] ?? 0,
              canDrop: !saving,
              onTap: () => onSelect(filter),
              onDrop: (task) => onDropTask(task, filter),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                '清单',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppColors.inkSoft,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.6,
                    ),
              ),
              const Spacer(),
              IconButton(
                onPressed: saving ? null : onCreateChecklist,
                icon: const Icon(Icons.add),
                tooltip: '新建清单',
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (loadingChecklists)
            Text(
              '加载中...',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.inkSoft),
            )
          else if (checklists.isEmpty)
            Text(
              '暂无清单',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.inkSoft),
            )
          else ...[
            ...checklists.map(
              (list) => _ChecklistNavTile(
                list: list,
                selected: activeChecklistId == list.id,
                canDelete: list.owner == username,
                canDrop: !saving,
                onTap: () => onSelectChecklist(list.id),
                onDelete: saving || list.owner != username
                    ? null
                    : () => onDeleteChecklist(list),
                onDrop: (task) => onDropChecklistTask(task, list),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TaskFilterTile extends StatelessWidget {
  const _TaskFilterTile({
    required this.filter,
    required this.selected,
    required this.count,
    required this.canDrop,
    required this.onTap,
    required this.onDrop,
  });

  final TaskFilter filter;
  final bool selected;
  final int count;
  final bool canDrop;
  final VoidCallback onTap;
  final ValueChanged<Task> onDrop;

  @override
  Widget build(BuildContext context) {
    return DragTarget<Task>(
      onWillAcceptWithDetails: (_) => canDrop && filter != TaskFilter.all,
      onAcceptWithDetails: (details) => onDrop(details.data),
      builder: (context, candidate, rejected) {
        final hovering = candidate.isNotEmpty;
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.zero,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: hovering ? AppColors.accent.withOpacity(0.10) : null,
                border: selected
                    ? Border(
                        left: BorderSide(
                        color: AppColors.accent,
                        width: 3,
                      ))
                    : hovering
                        ? Border(
                            left: BorderSide(
                              color: AppColors.accent.withOpacity(0.6),
                              width: 3,
                            ),
                          )
                        : null,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          filter.label,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: selected
                                        ? AppColors.accentDeep
                                        : AppColors.ink,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    count.toString(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: selected
                              ? AppColors.accentDeep
                              : AppColors.inkSoft,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ChecklistNavTile extends StatelessWidget {
  const _ChecklistNavTile({
    required this.list,
    required this.selected,
    required this.canDelete,
    required this.canDrop,
    required this.onTap,
    required this.onDelete,
    required this.onDrop,
  });

  final ChecklistList list;
  final bool selected;
  final bool canDelete;
  final bool canDrop;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final ValueChanged<Task> onDrop;

  @override
  Widget build(BuildContext context) {
    return DragTarget<Task>(
      onWillAcceptWithDetails: (_) => canDrop,
      onAcceptWithDetails: (details) => onDrop(details.data),
      builder: (context, candidate, rejected) {
        final hovering = candidate.isNotEmpty;
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.zero,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: hovering ? AppColors.accent.withOpacity(0.10) : null,
                border: selected
                    ? const Border(
                        left: BorderSide(
                          color: AppColors.accent,
                          width: 3,
                        ),
                      )
                    : hovering
                        ? Border(
                            left: BorderSide(
                              color: AppColors.accent.withOpacity(0.6),
                              width: 3,
                            ),
                          )
                        : null,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      list.name.isEmpty ? '未命名清单' : list.name,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color:
                                selected ? AppColors.accentDeep : AppColors.ink,
                          ),
                    ),
                  ),
                  if (canDelete)
                    IconButton(
                      onPressed: onDelete,
                      icon: const Icon(Icons.close, size: 16),
                      tooltip: '删除清单',
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TaskFilterChips extends StatelessWidget {
  const _TaskFilterChips({
    required this.selected,
    required this.counts,
    required this.activeChecklistId,
    required this.saving,
    required this.onSelect,
    required this.onDropTask,
  });

  final TaskFilter selected;
  final Map<TaskFilter, int> counts;
  final int? activeChecklistId;
  final bool saving;
  final ValueChanged<TaskFilter> onSelect;
  final void Function(Task task, TaskFilter target) onDropTask;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: TaskFilter.values.map((filter) {
        final count = counts[filter] ?? 0;
        final label = count > 0 ? '${filter.label} · $count' : filter.label;
        return DragTarget<Task>(
          onWillAcceptWithDetails: (_) => !saving && filter != TaskFilter.all,
          onAcceptWithDetails: (details) => onDropTask(details.data, filter),
          builder: (context, candidate, rejected) {
            final hovering = candidate.isNotEmpty;
            final active = activeChecklistId == null && selected == filter;
            return ChoiceChip(
              label: Text(label),
              selected: active || hovering,
              onSelected: (_) => onSelect(filter),
            );
          },
        );
      }).toList(),
    );
  }
}

class _ChecklistChips extends StatelessWidget {
  const _ChecklistChips({
    required this.checklists,
    required this.activeChecklistId,
    required this.loading,
    required this.saving,
    required this.username,
    required this.onSelect,
    required this.onCreate,
    required this.onDelete,
    required this.onDropTask,
  });

  final List<ChecklistList> checklists;
  final int? activeChecklistId;
  final bool loading;
  final bool saving;
  final String username;
  final ValueChanged<int> onSelect;
  final VoidCallback onCreate;
  final ValueChanged<ChecklistList> onDelete;
  final void Function(Task task, ChecklistList list) onDropTask;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '清单',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const Spacer(),
            IconButton(
              onPressed: saving ? null : onCreate,
              icon: const Icon(Icons.add),
              tooltip: '新建清单',
            ),
          ],
        ),
        if (loading)
          Text(
            '加载中...',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.inkSoft),
          )
        else if (checklists.isEmpty)
          Text(
            '暂无清单',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.inkSoft),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: checklists
                .map(
                  (list) => DragTarget<Task>(
                    onWillAcceptWithDetails: (_) => !saving,
                    onAcceptWithDetails: (details) =>
                        onDropTask(details.data, list),
                    builder: (context, candidate, rejected) {
                      final hovering = candidate.isNotEmpty;
                      return InputChip(
                        label: Text(list.name.isEmpty ? '未命名清单' : list.name),
                        selected: activeChecklistId == list.id || hovering,
                        onPressed: saving ? null : () => onSelect(list.id),
                        onDeleted: saving || list.owner != username
                            ? null
                            : () => onDelete(list),
                      );
                    },
                  ),
                )
                .toList(),
          ),
      ],
    );
  }
}

class _TrashDropZone extends StatelessWidget {
  const _TrashDropZone({
    required this.count,
    required this.deleting,
    required this.onTap,
    required this.onDrop,
  });

  final int count;
  final bool deleting;
  final VoidCallback onTap;
  final ValueChanged<Task> onDrop;

  @override
  Widget build(BuildContext context) {
    return DragTarget<Task>(
      onWillAcceptWithDetails: (_) => !deleting,
      onAcceptWithDetails: (details) => onDrop(details.data),
      builder: (context, candidate, rejected) {
        final hovering = candidate.isNotEmpty;
        final label = count > 0 ? '回收站 · $count' : '回收站';
        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.zero,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: hovering
                  ? AppColors.accent.withOpacity(0.12)
                  : Colors.white.withOpacity(0.85),
              borderRadius: BorderRadius.zero,
              border: Border.all(
                  color: hovering ? AppColors.accent : AppColors.outline),
            ),
            child: Row(
              children: [
                Icon(
                  hovering ? Icons.delete : Icons.delete_outline,
                  size: 18,
                  color: hovering ? AppColors.accentDeep : AppColors.inkSoft,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    hovering ? '松开删除任务' : '拖拽到此删除 · $label',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.inkSoft,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppColors.inkSoft,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TrashTaskCard extends StatelessWidget {
  const _TrashTaskCard({
    required this.task,
    required this.restoring,
    required this.onRestore,
  });

  final Task task;
  final bool restoring;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final deletedAt = task.deletedAt;
    String? deletedLabel;
    if (deletedAt != null && deletedAt > 0) {
      try {
        deletedLabel = DateFormat('M/d HH:mm').format(
          DateTime.fromMillisecondsSinceEpoch(deletedAt),
        );
      } catch (_) {}
    }

    return Card(
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.inventory_2_outlined,
                size: 18, color: AppColors.inkSoft),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title.isEmpty ? '未命名任务' : task.title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                  ),
                  if (deletedLabel != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '删除于 $deletedLabel',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.inkSoft,
                          ),
                    ),
                  ],
                  if (task.notes.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      task.notes,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.inkSoft,
                          ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: restoring ? null : onRestore,
              style: OutlinedButton.styleFrom(
                shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              child: const Text('还原'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChecklistItemCard extends StatelessWidget {
  const _ChecklistItemCard({
    required this.item,
    required this.saving,
    required this.onToggle,
    required this.onDelete,
  });

  final ChecklistItem item;
  final bool saving;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
          decoration: item.completed ? TextDecoration.lineThrough : null,
          color: item.completed ? AppColors.inkSoft : AppColors.ink,
        );

    return Card(
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: item.completed,
              onChanged: saving ? null : (_) => onToggle(),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title.isEmpty ? '未命名事项' : item.title,
                      style: titleStyle,
                    ),
                    if (item.notes.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        item.notes,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.inkSoft,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            IconButton(
              onPressed: saving ? null : onDelete,
              icon: const Icon(Icons.delete_outline, size: 18),
              tooltip: '删除事项',
            ),
          ],
        ),
      ),
    );
  }
}

typedef TaskUpdateCallback = Future<void> Function(
  Task task, {
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
  bool clearRemindAt,
  String? repeatRule,
  bool clearDeletedAt,
});

class _TaskDetailPanel extends StatelessWidget {
  const _TaskDetailPanel({
    required this.task,
    required this.saving,
    required this.onClose,
    required this.onToggleSubtask,
    required this.generateSubtaskId,
    required this.onUpdateTask,
    this.onDeleteTask,
  });

  final Task? task;
  final bool saving;
  final VoidCallback onClose;
  final void Function(Task task, TaskSubtask subtask) onToggleSubtask;
  final String Function() generateSubtaskId;
  final TaskUpdateCallback onUpdateTask;
  final Future<bool> Function(Task task)? onDeleteTask;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.95),
        borderRadius: BorderRadius.zero,
        border: Border.all(color: AppColors.outline),
      ),
      child: task == null
          ? _buildEmpty(context)
          : SingleChildScrollView(child: _buildDetail(context, task!)),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '任务详情',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const Spacer(),
            IconButton(
              onPressed: onClose,
              icon: const Icon(Icons.close),
              tooltip: '关闭',
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '选择一个任务查看详情。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.inkSoft,
              ),
        ),
      ],
    );
  }

  Widget _buildDetail(BuildContext context, Task task) {
    final timeLabel = _buildDueLabel(task);
    final chips = <Widget>[
      Chip(label: Text(task.isCompleted ? '已完成' : '未完成')),
    ];
    if (task.inbox) chips.add(const Chip(label: Text('收集箱')));
    if (timeLabel != null) chips.add(Chip(label: Text(timeLabel)));
    for (final tag in task.displayTags) {
      chips.add(Chip(label: Text(tag)));
    }

    final attachments = task.attachments;
    final subtasks = task.subtasks;

    DateTime? parseDate(String raw) {
      if (raw.trim().isEmpty) return null;
      try {
        return DateFormat('yyyy-MM-dd').parse(raw);
      } catch (_) {
        return null;
      }
    }

    TimeOfDay? parseTime(String raw) {
      final parts = raw.trim().split(':');
      if (parts.length != 2) return null;
      final hour = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);
      if (hour == null || minute == null) return null;
      if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
      return TimeOfDay(hour: hour, minute: minute);
    }

    String formatTime(TimeOfDay time) {
      final hour = time.hour.toString().padLeft(2, '0');
      final minute = time.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    }

    String formatDateValue(String raw) {
      if (raw.trim().isEmpty) return '未设置';
      final parsed = parseDate(raw);
      if (parsed == null) return raw;
      return DateFormat('M月d日').format(parsed);
    }

    String formatTimeValue(String raw) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return '未设置';
      return trimmed;
    }

    String formatRemindValue(int? millis) {
      if (millis == null) return '未设置';
      try {
        return DateFormat('M/d HH:mm')
            .format(DateTime.fromMillisecondsSinceEpoch(millis));
      } catch (_) {
        return millis.toString();
      }
    }

    String formatRepeatValue(String raw) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return '未设置';
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is! Map) return '已设置';
        final freq = decoded['freq']?.toString() ?? '';
        switch (freq) {
          case 'daily':
            return '每天';
          case 'weekly':
            final weekdays = decoded['weekdays'] is List
                ? decoded['weekdays'] as List
                : const [];
            final labels = weekdays
                .map((value) => int.tryParse(value.toString()) ?? 0)
                .where((value) => value >= 1 && value <= 7)
                .toList()
              ..sort();
            if (labels.isEmpty) return '每周';
            const map = <int, String>{
              1: '一',
              2: '二',
              3: '三',
              4: '四',
              5: '五',
              6: '六',
              7: '日'
            };
            final text = labels
                .map((d) => map[d] ?? '')
                .where((s) => s.isNotEmpty)
                .join(' ');
            return text.isEmpty ? '每周' : '每周($text)';
          case 'monthly':
            final day = int.tryParse(decoded['day']?.toString() ?? '') ?? 1;
            return '每月${day.clamp(1, 31)}号';
          case 'yearly':
            final month = int.tryParse(decoded['month']?.toString() ?? '') ?? 1;
            final day = int.tryParse(decoded['day']?.toString() ?? '') ?? 1;
            return '每年${month.clamp(1, 12)}月${day.clamp(1, 31)}日';
          default:
            return '已设置';
        }
      } catch (_) {
        return '已设置';
      }
    }

    Future<void> editTitle() async {
      final controller = TextEditingController(text: task.title);
      final next = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('修改标题'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '输入任务标题',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('保存'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (!context.mounted) return;
      if (next == null) return;
      final trimmed = next.trim();
      if (trimmed.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('标题不能为空。')),
        );
        return;
      }
      if (trimmed == task.title.trim()) return;
      await onUpdateTask(task, title: trimmed);
    }

    Future<void> editNotes() async {
      final controller = TextEditingController(text: task.notes);
      final next = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('编辑备注'),
          content: TextField(
            controller: controller,
            maxLines: 6,
            decoration: const InputDecoration(
              hintText: '添加备注...',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('保存'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (next == null) return;
      if (next == task.notes) return;
      await onUpdateTask(task, notes: next);
    }

    Future<void> deleteTask() async {
      final handler = onDeleteTask;
      if (handler == null) return;
      if (saving) return;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('删除任务'),
          content:
              Text('确定要删除「${task.title.isEmpty ? '未命名任务' : task.title}」吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      final success = await handler(task);
      if (!context.mounted) return;
      if (!success) return;
      onClose();
    }

    Future<void> pickDueDate() async {
      final now = DateTime.now();
      final initial = parseDate(task.dueDate) ?? now;
      final picked = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );
      if (picked == null) return;
      await onUpdateTask(
        task,
        dueDate: DateFormat('yyyy-MM-dd').format(picked),
        inbox: false,
      );
    }

    Future<void> clearDueDate() async {
      await onUpdateTask(
        task,
        dueDate: '',
        inbox: task.isCompleted
            ? false
            : (task.checklistId != null ? false : true),
      );
    }

    Future<void> pickStartTime() async {
      final initial = parseTime(task.startTime) ?? TimeOfDay.now();
      final picked = await showTimePicker(
        context: context,
        initialTime: initial,
      );
      if (picked == null) return;
      await onUpdateTask(task, startTime: formatTime(picked));
    }

    Future<void> clearStartTime() async {
      await onUpdateTask(task, startTime: '');
    }

    Future<void> pickEndTime() async {
      final initial = parseTime(task.endTime) ?? TimeOfDay.now();
      final picked = await showTimePicker(
        context: context,
        initialTime: initial,
      );
      if (picked == null) return;
      await onUpdateTask(task, endTime: formatTime(picked));
    }

    Future<void> clearEndTime() async {
      await onUpdateTask(task, endTime: '');
    }

    Future<void> pickRemindAt() async {
      final base = task.remindAt != null
          ? DateTime.fromMillisecondsSinceEpoch(task.remindAt!)
          : (parseDate(task.dueDate) ?? DateTime.now());
      final pickedDate = await showDatePicker(
        context: context,
        initialDate: base,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );
      if (pickedDate == null) return;
      final pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(base),
      );
      if (pickedTime == null) return;
      final remind = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
      await onUpdateTask(task, remindAt: remind.millisecondsSinceEpoch);
    }

    Future<void> clearRemindAt() async {
      await onUpdateTask(task, clearRemindAt: true);
    }

    Future<void> editRepeatRule() async {
      final baseDate = parseDate(task.dueDate) ?? DateTime.now();
      RepeatFrequency frequency = RepeatFrequency.daily;
      Set<int> weekdays = {baseDate.weekday};
      int monthDay = baseDate.day;
      int yearMonth = baseDate.month;
      int yearDay = baseDate.day;

      final current = task.repeatRule.trim();
      if (current.isNotEmpty) {
        try {
          final decoded = jsonDecode(current);
          if (decoded is Map) {
            final freq = decoded['freq']?.toString() ?? '';
            frequency = RepeatFrequency.values.firstWhere(
              (f) => f.name == freq,
              orElse: () => RepeatFrequency.daily,
            );
            if (frequency == RepeatFrequency.weekly &&
                decoded['weekdays'] is List) {
              weekdays = (decoded['weekdays'] as List)
                  .map((value) => int.tryParse(value.toString()) ?? 0)
                  .where((value) => value >= 1 && value <= 7)
                  .toSet();
            }
            if (frequency == RepeatFrequency.monthly) {
              monthDay =
                  int.tryParse(decoded['day']?.toString() ?? '') ?? monthDay;
            }
            if (frequency == RepeatFrequency.yearly) {
              yearMonth =
                  int.tryParse(decoded['month']?.toString() ?? '') ?? yearMonth;
              yearDay =
                  int.tryParse(decoded['day']?.toString() ?? '') ?? yearDay;
            }
          }
        } catch (_) {}
      }

      String? nextRule = await showDialog<String>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('重复设置'),
              content: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<RepeatFrequency>(
                      value: frequency,
                      items: RepeatFrequency.values
                          .map(
                            (freq) => DropdownMenuItem(
                              value: freq,
                              child: Text(freq.label),
                            ),
                          )
                          .toList(),
                      onChanged: saving
                          ? null
                          : (value) =>
                              setState(() => frequency = value ?? frequency),
                      decoration: const InputDecoration(labelText: '频率'),
                    ),
                    if (frequency == RepeatFrequency.weekly) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: List.generate(7, (index) {
                          final weekday = index + 1;
                          const labels = ['一', '二', '三', '四', '五', '六', '日'];
                          return FilterChip(
                            label: Text(labels[index]),
                            selected: weekdays.contains(weekday),
                            onSelected: saving
                                ? null
                                : (selected) {
                                    setState(() {
                                      if (selected) {
                                        weekdays.add(weekday);
                                      } else {
                                        weekdays.remove(weekday);
                                      }
                                    });
                                  },
                          );
                        }),
                      ),
                    ],
                    if (frequency == RepeatFrequency.monthly) ...[
                      const SizedBox(height: 10),
                      DropdownButtonFormField<int>(
                        value: monthDay.clamp(1, 31),
                        items: List.generate(
                          31,
                          (index) => DropdownMenuItem(
                            value: index + 1,
                            child: Text('${index + 1}号'),
                          ),
                        ),
                        onChanged: saving
                            ? null
                            : (value) =>
                                setState(() => monthDay = value ?? monthDay),
                        decoration: const InputDecoration(labelText: '每月几号'),
                      ),
                    ],
                    if (frequency == RepeatFrequency.yearly) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              value: yearMonth.clamp(1, 12),
                              items: List.generate(
                                12,
                                (index) => DropdownMenuItem(
                                  value: index + 1,
                                  child: Text('${index + 1}月'),
                                ),
                              ),
                              onChanged: saving
                                  ? null
                                  : (value) => setState(
                                      () => yearMonth = value ?? yearMonth),
                              decoration:
                                  const InputDecoration(labelText: '月份'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              value: yearDay.clamp(1, 31),
                              items: List.generate(
                                31,
                                (index) => DropdownMenuItem(
                                  value: index + 1,
                                  child: Text('${index + 1}日'),
                                ),
                              ),
                              onChanged: saving
                                  ? null
                                  : (value) => setState(
                                      () => yearDay = value ?? yearDay),
                              decoration:
                                  const InputDecoration(labelText: '日期'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                if (task.repeatRule.trim().isNotEmpty)
                  TextButton(
                    onPressed:
                        saving ? null : () => Navigator.of(context).pop(''),
                    child: const Text('关闭重复'),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final rule = <String, dynamic>{
                      'freq': frequency.name,
                      'count': 1
                    };
                    if (frequency == RepeatFrequency.weekly) {
                      final list = weekdays.isNotEmpty
                          ? weekdays.toList()
                          : [baseDate.weekday];
                      list.sort();
                      rule['weekdays'] = list;
                    }
                    if (frequency == RepeatFrequency.monthly) {
                      rule['day'] = monthDay.clamp(1, 31);
                    }
                    if (frequency == RepeatFrequency.yearly) {
                      rule['month'] = yearMonth.clamp(1, 12);
                      rule['day'] = yearDay.clamp(1, 31);
                    }
                    Navigator.of(context).pop(jsonEncode(rule));
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        ),
      );

      if (nextRule == null) return;
      await onUpdateTask(task, repeatRule: nextRule);
    }

    Future<void> addSubtask() async {
      final controller = TextEditingController();
      final title = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('添加子任务'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '子任务内容',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('添加'),
            ),
          ],
        ),
      );
      controller.dispose();
      final trimmed = title?.trim() ?? '';
      if (trimmed.isEmpty) return;
      final next = [
        ...subtasks,
        TaskSubtask(
          id: generateSubtaskId(),
          title: trimmed,
          completed: false,
        ),
      ];
      await onUpdateTask(
        task,
        subtasks: next,
        status: task.isCompleted ? 'todo' : null,
      );
    }

    Future<void> removeSubtask(TaskSubtask subtask) async {
      final next = subtasks.where((item) => item.id != subtask.id).toList();
      String? status;
      if (next.isNotEmpty) {
        final allDone = next.every((item) => item.completed);
        status = allDone ? 'completed' : 'todo';
      }
      await onUpdateTask(task, subtasks: next, status: status);
    }

    Future<void> editColor() async {
      if (!context.mounted) return;
      final picked =
          await showTaskColorPicker(context, initialHex: task.colorHex);
      if (picked == null) return;
      final nextTags = picked.trim().isEmpty
          ? Task.stripSystemColorTags(task.tags)
          : Task.applyColorTag(task.tags, picked);
      await onUpdateTask(task, tags: nextTags);
    }

    Widget settingTile({
      required String label,
      required String value,
      required IconData icon,
      required VoidCallback? onTap,
      VoidCallback? onClear,
    }) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.zero,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.zero,
            border: Border.all(color: AppColors.outline),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppColors.inkSoft),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              Text(
                value,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.inkSoft),
              ),
              if (onClear != null) ...[
                const SizedBox(width: 6),
                InkWell(
                  onTap: onClear,
                  borderRadius: BorderRadius.zero,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child:
                        Icon(Icons.close, size: 16, color: AppColors.inkSoft),
                  ),
                ),
              ] else ...[
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right,
                    size: 18, color: AppColors.inkSoft),
              ],
            ],
          ),
        ),
      );
    }

    final dueDateValue = formatDateValue(task.dueDate);
    final startTimeValue = formatTimeValue(task.startTime);
    final endTimeValue = formatTimeValue(task.endTime);
    final remindValue = formatRemindValue(task.remindAt);
    final repeatValue = formatRepeatValue(task.repeatRule);
    final colorValue = task.colorHex == null ? '默认' : task.colorHex!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '任务详情',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const Spacer(),
            IconButton(
              onPressed: onClose,
              icon: const Icon(Icons.close),
              tooltip: '关闭',
            ),
          ],
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: saving ? null : editTitle,
          child: Text(
            task.title.isEmpty ? '未命名任务' : task.title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: chips,
        ),
        const SizedBox(height: 12),
        Text(
          '更多设置',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 6),
        settingTile(
          label: '开始日期',
          value: dueDateValue,
          icon: Icons.event,
          onTap: saving ? null : pickDueDate,
          onClear: saving || task.dueDate.trim().isEmpty ? null : clearDueDate,
        ),
        const SizedBox(height: 8),
        settingTile(
          label: '开始时间',
          value: startTimeValue,
          icon: Icons.schedule,
          onTap: saving ? null : pickStartTime,
          onClear:
              saving || task.startTime.trim().isEmpty ? null : clearStartTime,
        ),
        const SizedBox(height: 8),
        settingTile(
          label: '截止时间',
          value: endTimeValue,
          icon: Icons.timelapse,
          onTap: saving ? null : pickEndTime,
          onClear: saving || task.endTime.trim().isEmpty ? null : clearEndTime,
        ),
        const SizedBox(height: 8),
        settingTile(
          label: '提醒',
          value: remindValue,
          icon: Icons.notifications_none,
          onTap: saving ? null : pickRemindAt,
          onClear: saving || task.remindAt == null ? null : clearRemindAt,
        ),
        const SizedBox(height: 8),
        settingTile(
          label: '重复',
          value: repeatValue,
          icon: Icons.repeat,
          onTap: saving ? null : editRepeatRule,
          onClear: saving || task.repeatRule.trim().isEmpty
              ? null
              : () => onUpdateTask(task, repeatRule: ''),
        ),
        const SizedBox(height: 8),
        settingTile(
          label: '颜色',
          value: colorValue,
          icon: Icons.color_lens_outlined,
          onTap: saving ? null : editColor,
          onClear: saving || task.colorHex == null
              ? null
              : () => onUpdateTask(task,
                  tags: Task.stripSystemColorTags(task.tags)),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Text(
              '备注',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const Spacer(),
            TextButton(
              onPressed: saving ? null : editNotes,
              child: const Text('编辑'),
            ),
          ],
        ),
        if (task.notes.trim().isNotEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.zero,
              border: Border.all(color: AppColors.outline),
            ),
            child: Text(
              task.notes,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.inkSoft,
                  ),
            ),
          )
        else
          Text(
            '暂无备注。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.inkSoft,
                ),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Text(
              '子任务',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const Spacer(),
            IconButton(
              onPressed: saving ? null : addSubtask,
              icon: const Icon(Icons.add),
              tooltip: '添加子任务',
            ),
          ],
        ),
        if (subtasks.isEmpty)
          Text(
            '暂无子任务。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.inkSoft,
                ),
          )
        else ...[
          const SizedBox(height: 6),
          ...subtasks.map(
            (subtask) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Checkbox(
                    value: subtask.completed,
                    onChanged:
                        saving ? null : (_) => onToggleSubtask(task, subtask),
                  ),
                  Expanded(
                    child: Text(
                      subtask.title,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            decoration: subtask.completed
                                ? TextDecoration.lineThrough
                                : null,
                            color: subtask.completed
                                ? AppColors.inkSoft
                                : AppColors.ink,
                          ),
                    ),
                  ),
                  IconButton(
                    onPressed: saving ? null : () => removeSubtask(subtask),
                    icon: const Icon(Icons.close, size: 16),
                    tooltip: '删除子任务',
                  ),
                ],
              ),
            ),
          ),
        ],
        if (attachments.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            '附件',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 6),
          ...attachments.map(
            (attachment) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${attachment.name} · ${_formatSize(attachment.size)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.inkSoft,
                    ),
              ),
            ),
          ),
        ],
        if (onDeleteTask != null) ...[
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: saving ? null : deleteTask,
            style: OutlinedButton.styleFrom(
              shape:
                  const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              side: BorderSide(color: Colors.red.withOpacity(0.55)),
              foregroundColor: Colors.red,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            icon: const Icon(Icons.delete_outline),
            label: const Text('删除任务'),
          ),
        ],
      ],
    );
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '0B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)}KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)}MB';
  }

  String? _buildDueLabel(Task task) {
    if (task.dueDate.trim().isEmpty) return null;
    try {
      final date = DateFormat('yyyy-MM-dd').parse(task.dueDate);
      final friendly = DateFormat('M月d日').format(date);
      if (task.startTime.trim().isNotEmpty || task.endTime.trim().isNotEmpty) {
        final start = task.startTime.trim();
        final end = task.endTime.trim();
        final range =
            [start, end].where((value) => value.isNotEmpty).join(' - ');
        return '$friendly $range';
      }
      return friendly;
    } catch (_) {
      return task.dueDate;
    }
  }
}

enum RepeatFrequency {
  daily,
  weekly,
  monthly,
  yearly,
}

extension RepeatFrequencyLabel on RepeatFrequency {
  String get label {
    switch (this) {
      case RepeatFrequency.daily:
        return '每天';
      case RepeatFrequency.weekly:
        return '每周';
      case RepeatFrequency.monthly:
        return '每月';
      case RepeatFrequency.yearly:
        return '每年';
    }
  }
}

class _QuickAddTaskDraft {
  _QuickAddTaskDraft({
    required this.title,
    required this.tags,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.repeatRule,
    required this.remindAt,
    required this.subtasks,
    this.notes = '',
  });

  final String title;
  final List<String> tags;
  final String notes;
  final DateTime? date;
  final String startTime;
  final String endTime;
  final String repeatRule;
  final int? remindAt;
  final List<TaskSubtask> subtasks;
}

class _TaskDefaults {
  const _TaskDefaults({
    required this.dueDate,
    required this.inbox,
    required this.status,
  });

  final String dueDate;
  final bool inbox;
  final String status;
}

class _SubtaskDraft {
  _SubtaskDraft({required this.id, required this.title});

  final String id;
  String title;
}

class _ParsedQuickAddInput {
  const _ParsedQuickAddInput({
    required this.title,
    required this.tags,
    required this.dateOverride,
  });

  final String title;
  final List<String> tags;
  final DateTime? dateOverride;
}
