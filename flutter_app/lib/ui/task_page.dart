import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../core/api_client.dart';
import '../core/notifications/local_task_notifications.dart';
import '../core/time_repository.dart';
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
import 'widgets/empty_state.dart';
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
    required this.workspace,
    this.onOpenNavigation,
  });

  final String appTitle;
  final String username;
  final ApiClient apiClient;
  final UserSettings userSettings;
  final VoidCallback onLogout;
  final VoidCallback onOpenSettings;
  final WorkspaceView workspace;
  final VoidCallback? onOpenNavigation;

  @override
  State<TaskPage> createState() => _TaskPageState();
}

class _TaskPageState extends State<TaskPage> {
  bool _isTaskDragActive = false;
  bool _androidQuickAddOpen = false;
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
  int _quickAddEndDayOffset = 0; // 0=同日, 1+=第N天
  bool _quickAddRepeat = false;
  RepeatFrequency _quickAddRepeatFrequency = RepeatFrequency.daily;
  int _quickAddRepeatCount = 1;
  Set<int> _quickAddRepeatWeekdays = {};
  int _quickAddRepeatMonthDay = 1;
  int _quickAddRepeatYearMonth = 1;
  int _quickAddRepeatYearDay = 1;
  DateTime? _quickAddRemindAt;
  int _quickAddMatrixPriority =
      0; // 0=未设置, 1~4=Q4~Q1（见 _normalizeMatrixPriority）
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

  Timer? _undoTimer;
  _UndoAction? _pendingUndo;

  bool get _localRemindersEnabled => widget.userSettings.notifications.enabled;

  Future<void> _syncLocalTaskReminders() async {
    if (kIsWeb) return;
    if (!_localRemindersEnabled) {
      await LocalTaskNotifications.instance.cancelAllTaskReminders();
      return;
    }
    final granted = await LocalTaskNotifications.instance.requestPermission();
    if (!granted) return;
    await LocalTaskNotifications.instance.syncTaskReminders(_tasks);
  }

  bool get _useAndroidUi => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  String _apiBaseUrlLabel() {
    final raw = widget.apiClient.baseUrl.trim();
    return raw.isEmpty ? '(未设置)' : raw;
  }

  bool _looksLikeNetworkError(Object error) {
    if (error is TimeoutException) return true;
    final message = error.toString();
    return message.contains('SocketException') ||
        message.contains('Failed host lookup') ||
        message.contains('Connection refused') ||
        message.contains('ClientException') ||
        message.contains('XMLHttpRequest');
  }

  String? _tryParseServerError(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) {
        final value = decoded['error'] ?? decoded['message'];
        final msg = value?.toString().trim() ?? '';
        if (msg.isNotEmpty) return msg;
      }
    } catch (_) {}
    return null;
  }

  String _describeFailure(String fallback, Object error) {
    if (error is ApiException) {
      final msg = _tryParseServerError(error.body) ?? error.body.trim();
      final text = msg.isEmpty ? fallback : msg;
      return '$text (HTTP ${error.statusCode})';
    }
    if (error is TimeoutException) {
      return '$fallback：请求超时（后端：${_apiBaseUrlLabel()}）';
    }
    if (_looksLikeNetworkError(error)) {
      final hint = _useAndroidUi ? '（Android 模拟器用 10.0.2.2:3000）' : '';
      return '$fallback：无法连接后端（${_apiBaseUrlLabel()}）$hint';
    }
    return fallback;
  }

  void _showFailureSnackBar(String fallback, Object error) {
    if (!mounted) return;
    final action = _looksLikeNetworkError(error) || error is TimeoutException
        ? SnackBarAction(label: '设置', onPressed: widget.onOpenSettings)
        : null;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_describeFailure(fallback, error)),
        action: action,
      ),
    );
  }

  bool get _undoEnabled => widget.userSettings.preferences.undoEnabled;

  Duration _undoDuration() {
    final seconds = widget.userSettings.preferences.undoSeconds;
    return Duration(seconds: seconds.clamp(1, 20));
  }

  void _clearUndo() {
    _undoTimer?.cancel();
    _undoTimer = null;
    _pendingUndo = null;
  }

  void _queueUndo({
    required String message,
    required Future<void> Function() onUndo,
  }) {
    if (!_undoEnabled || !mounted) return;
    _undoTimer?.cancel();
    final action = _UndoAction(message: message, onUndo: onUndo);
    _pendingUndo = action;
    final duration = _undoDuration();
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    final controller = messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration,
        action: SnackBarAction(
          label: '撤回',
          onPressed: () => _performUndo(),
        ),
      ),
    );
    _undoTimer = Timer(duration, () {
      if (!mounted) return;
      if (!identical(_pendingUndo, action)) return;
      controller.close();
      _clearUndo();
    });
    controller.closed.then((_) {
      if (!mounted) return;
      if (identical(_pendingUndo, action)) {
        _clearUndo();
      }
    });
  }

  Future<void> _performUndo() async {
    final action = _pendingUndo;
    if (action == null || !mounted) return;
    _clearUndo();
    ScaffoldMessenger.of(context).clearSnackBars();
    try {
      await action.onUndo();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已撤回。'),
          duration: Duration(seconds: 1),
        ),
      );
    } on UnauthorizedException {
      widget.onLogout();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('撤回失败。')),
      );
    }
  }

  Future<void> _applyTaskSnapshot(Task snapshot) async {
    setState(() => _saving = true);
    try {
      final updated = await widget.apiClient.updateTask(
        snapshot.id,
        title: snapshot.title,
        notes: snapshot.notes,
        status: snapshot.status,
        dueDate: snapshot.dueDate,
        startTime: snapshot.startTime,
        endTime: snapshot.endTime,
        tags: snapshot.tags,
        subtasks: snapshot.subtasks,
        inbox: snapshot.inbox,
        priority: snapshot.priority,
        remindAt: snapshot.remindAt,
        clearRemindAt: snapshot.remindAt == null,
        repeatRule: snapshot.repeatRule,
        deletedAt: snapshot.deletedAt,
        clearDeletedAt: snapshot.deletedAt == null,
      );
      if (!mounted) return;
      setState(() {
        final exists = _tasks.any((task) => task.id == snapshot.id);
        if (exists) {
          _tasks = _tasks.map((t) => t.id == snapshot.id ? updated : t).toList();
        } else {
          _tasks = [..._tasks, updated];
        }
        _lastSync = DateTime.now();
      });
      unawaited(_syncLocalTaskReminders());
    } on UnauthorizedException {
      widget.onLogout();
    } catch (e) {
      _showFailureSnackBar('撤回失败', e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _undoMessageForTaskUpdate({
    String? title,
    String? notes,
    String? status,
    String? dueDate,
    String? startTime,
    String? endTime,
    bool clearDeletedAt = false,
  }) {
    if (clearDeletedAt) return '已还原任务。';
    if (status != null) {
      return status == 'completed' ? '已完成任务。' : '已恢复为待办。';
    }
    if (dueDate != null || startTime != null || endTime != null) {
      return '已更新日程。';
    }
    if (title != null) return '已修改标题。';
    if (notes != null) return '已更新备注。';
    return '已更新任务。';
  }

  @override
  void initState() {
    super.initState();
    if (widget.userSettings.preferences.defaultView.trim() == 'today') {
      _filter = TaskFilter.today;
    }
    _loadTasks();
    _loadChecklists();
    _setDefaultStatsRange();
    _loadTimeTracking();
    if (widget.workspace == WorkspaceView.stats &&
        (_timeStats == null || _pomodoroSummary == null) &&
        !_loadingStats) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadTimeStats());
    }
  }

  @override
  void didUpdateWidget(covariant TaskPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace != widget.workspace) {
      _handleWorkspaceChanged(widget.workspace);
    }
    if (oldWidget.userSettings.notifications.enabled !=
        widget.userSettings.notifications.enabled) {
      unawaited(_syncLocalTaskReminders());
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _quickAddController.dispose();
    _checklistAddController.dispose();
    _scrollController.dispose();
    _undoTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final counts = _buildCounts();
    final screenWidth = MediaQuery.of(context).size.width;
    final workspace = widget.workspace;
    final isTasks = workspace == WorkspaceView.tasks;
    final isMatrix = workspace == WorkspaceView.matrix;
    final isTimeTracking = workspace == WorkspaceView.timeTracking;
    final isCalendar = workspace == WorkspaceView.calendar;
    final isPomodoro = workspace == WorkspaceView.pomodoro;
    final isStats = workspace == WorkspaceView.stats;
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
    final matrixFiltered = isMatrix ? _applyMatrixTasks(_tasks) : <Task>[];
    final filtered = isTasks
        ? _applySearch(baseFiltered)
        : isMatrix
            ? _applySearch(matrixFiltered)
            : <Task>[];
    final selectedTask = isTrash ? null : _findTaskById(_selectedTaskId);
    final showDetailPanel = (isTasks && !isTrash && screenWidth >= 1200) ||
        (isMatrix && screenWidth >= 1200);
    final showInlineFilters = isTasks && !showTaskNav && !isTrash;
    final headerTitle = isTasks
        ? (isTrash
            ? '回收站'
            : isChecklistView
                ? (_findChecklistById(_activeChecklistId)?.name ?? '清单')
                : _filter.label)
        : (isMatrix ? '' : workspace.label);
    final headerSubtitle = isTasks
        ? (isTrash
            ? '已删除的任务，可还原或清空。'
            : isChecklistView
                ? '清单分类任务。'
                : _filter.description)
        : (isTimeTracking || isMatrix ? '' : workspace.description);
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
    } else if (isMatrix) {
      headerMetaTitle = '${filtered.length} 个未完成';
      headerMetaSubtitle = '';
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

    final showAndroidTrashTarget = _useAndroidUi &&
        !_showTrash &&
        _isTaskDragActive &&
        !_androidQuickAddOpen;
	    final showAndroidAddFab = _useAndroidUi &&
	        widget.workspace == WorkspaceView.tasks &&
	        !_showTrash &&
	        !_isTaskDragActive &&
	        !_androidQuickAddOpen;

    final content = Stack(
      children: [
        Column(
          key: const ValueKey('task_detail_scroll_column'),
          children: [
            _buildToolbar(
              context,
              isTasks: isTasks ||
                  isMatrix ||
                  isCalendar ||
                  isTimeTracking ||
                  isPomodoro ||
                  isStats,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                child: _buildWorkspaceBody(
                  isTasks: isTasks,
                  isMatrix: isMatrix,
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
        if (showAndroidTrashTarget || showAndroidAddFab)
          Positioned(
            right: 16,
            bottom: 16,
            child: showAndroidTrashTarget
                ? _buildFloatingTrashTarget(context)
                : FloatingActionButton(
                    heroTag: 'task_add_fab',
                    onPressed: _saving ? null : _openQuickAddSheet,
                    backgroundColor: AppColors.accentCool,
                    child: const Icon(Icons.add, size: 28),
                  ),
          ),
        if (_useAndroidUi && _androidQuickAddOpen) ...[
          Positioned.fill(
            child: GestureDetector(
              onTap: _closeAndroidQuickAdd,
              child: Container(
                color: Colors.black.withOpacity(0.35),
              ),
            ),
          ),
          Positioned(
            left: 14,
            right: 14,
            bottom: 14,
            child: AnimatedPadding(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SafeArea(
                top: false,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.78,
                  ),
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: _buildQuickAddField(
                      context,
                      autofocus: true,
                      onSubmitted: (value) async {
                        final ok = await _tryQuickAdd(value);
                        if (!mounted) return;
                        if (ok) _closeAndroidQuickAdd();
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );

    if (!_useAndroidUi) return content;

    return PopScope(
      canPop: !_androidQuickAddOpen,
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (_androidQuickAddOpen) _closeAndroidQuickAdd();
      },
      child: content,
    );
  }

  Widget _buildToolbar(
    BuildContext context, {
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
            color: AppColors.surface.withOpacity(0.85),
            borderRadius: BorderRadius.zero,
            border: Border.all(color: AppColors.outline),
          ),
          child: Row(
            children: [
              Icon(Icons.search, size: 18, color: AppColors.inkSoft),
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
                  child: Padding(
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
              if (widget.onOpenNavigation != null) ...[
                IconButton(
                  onPressed: widget.onOpenNavigation,
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
                  child: CircleAvatar(
                    radius: 14,
                    backgroundColor: AppColors.accentCool,
                    child: Icon(
                      Icons.person,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSecondary,
                    ),
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
                  child: CircleAvatar(
                    radius: 14,
                    backgroundColor: AppColors.accentCool,
                    child: Icon(
                      Icons.person,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSecondary,
                    ),
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
    required bool isMatrix,
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
    final hasSearch = _searchQuery.trim().isNotEmpty;
    if (hasSearch && !isTasks && !isMatrix && !isCalendar) {
      final results =
          _applySearch(_tasks.where((task) => task.deletedAt == null).toList())
            ..sort(_sortTask);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.search, size: 18, color: AppColors.inkSoft),
              const SizedBox(width: 8),
              Text(
                '搜索结果（${results.length}）',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: results.isEmpty
                ? Center(
                    child: EmptyState(
                      title: '没有找到任务',
                      subtitle: '',
                      flat: true,
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: results.length,
                    itemBuilder: (context, index) {
                      final task = results[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TaskCard(
                          task: task,
                          isSelected: false,
                          onTap: () => _openTaskDetailFromCalendar(task),
                          onToggle: () => _toggleTask(task),
                          onEditTitle:
                              _saving ? null : () => _promptEditTaskTitle(task),
                        ),
                      );
                    },
                  ),
          ),
        ],
      );
    }

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
            final feedback = Material(
              color: Colors.transparent,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Opacity(opacity: 0.95, child: card),
              ),
            );
            final draggable = _useAndroidUi
                ? LongPressDraggable<Task>(
                    data: task,
                    onDragStarted: () => _setTaskDragActive(true),
                    onDragEnd: (_) => _setTaskDragActive(false),
                    onDragCompleted: () => _setTaskDragActive(false),
                    onDraggableCanceled: (_, __) => _setTaskDragActive(false),
                    feedback: feedback,
                    childWhenDragging: Opacity(opacity: 0.35, child: card),
                    child: card,
                  )
                : Draggable<Task>(
                    data: task,
                    onDragStarted: () => _setTaskDragActive(true),
                    onDragEnd: (_) => _setTaskDragActive(false),
                    onDragCompleted: () => _setTaskDragActive(false),
                    onDraggableCanceled: (_, __) => _setTaskDragActive(false),
                    feedback: feedback,
                    childWhenDragging: Opacity(opacity: 0.35, child: card),
                    child: card,
                  );
            final taskCell = _wrapAndroidSwipeEditTask(task, draggable);
            return StaggeredFadeSlide(
              index: index,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: taskCell,
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
          ] else if (!isTrashView && !_useAndroidUi) ...[
            _buildQuickAddField(context),
          ],
          if (showInlineFilters && !isTrashView && !isChecklistView) ...[
            const SizedBox(height: 12),
            if (_useAndroidUi) ...[
              _ChecklistChips(
                checklists: _checklists,
                activeChecklistId: _activeChecklistId,
                loading: _loadingChecklists,
                saving: _saving,
                username: widget.username,
                singleRow: true,
                onSelect: _selectChecklist,
                onCreate: _promptCreateChecklist,
                onDelete: _confirmDeleteChecklist,
                onDropTask: _applyDropToChecklist,
              ),
              const SizedBox(height: 12),
              _TaskFilterChips(
                selected: _filter,
                counts: counts,
                activeChecklistId: _activeChecklistId,
                saving: _saving,
                singleRow: true,
                onSelect: _setFilter,
                onDropTask: _applyDropToFilter,
              ),
            ] else ...[
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
          if (!isTrashView && !isChecklistView && !_useAndroidUi) ...[
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

    if (isMatrix) {
      return _buildMatrixWorkspace(
        context,
        tasks: filtered,
        showDetailPanel: showDetailPanel,
        selectedTask: selectedTask,
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
              onRefresh: _loadTimeTracking,
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
      final visibleTasks = _tasks.where((task) => task.deletedAt == null).toList();
      final initialMode = switch (
          widget.userSettings.calendarDefaultMode.trim().toLowerCase()) {
        'day' => CalendarMode.day,
        'week' => CalendarMode.week,
        'month' => CalendarMode.month,
        _ => CalendarMode.week,
      };
      return CalendarView(
        tasks: _applySearch(visibleTasks),
        loading: _loading,
        saving: _saving,
        settings: widget.userSettings.calendarSettings,
        timelineDefaultHour:
            widget.userSettings.preferences.calendarTimelineDefaultHour,
        initialMode: initialMode,
        loadHolidayCnYear: _loadHolidayCnYear,
        onCreateTask: _createTaskFromCalendar,
        onRescheduleTask: _rescheduleTaskFromCalendar,
        onToggleTask: _toggleTask,
        onOpenTask: _openTaskDetailFromCalendar,
      );
    }

    if (isStats) {
      return ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(widget.apiClient)],
        child: StatsDashboardView(
          tasks: _tasks,
          timeStats: _timeStats,
          pomodoroSummary: _pomodoroSummary,
          pomodoroSessions: _pomodoroSessions,
          loading: _loadingStats,
          onRefresh: _loadTimeStats,
        ),
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
              title: '${widget.workspace.label} 开发中',
              subtitle: '当前版本先体验任务列表，其他模块即将上线。',
            ),
          ),
        ),
      ],
    );
  }

  List<Task> _applyMatrixTasks(List<Task> tasks) {
    final scope = widget.userSettings.preferences.matrixScope.trim();
    final visible = tasks
        .where((task) => task.deletedAt == null && !task.isCompleted)
        .toList();

    final fmt = DateFormat('yyyy-MM-dd');
    final today = DateTime.now();
    final todayKey = fmt.format(today);
    final threeDaysEndKey = fmt.format(today.add(const Duration(days: 2)));

    if (scope == 'all') return visible;
    if (scope == '3days') {
      return visible
          .where(
            (task) =>
                task.dueDate.isNotEmpty &&
                task.dueDate.compareTo(todayKey) >= 0 &&
                task.dueDate.compareTo(threeDaysEndKey) <= 0,
          )
          .toList();
    }

    // Default: today
    return visible.where((task) => task.dueDate == todayKey).toList();
  }

  String _matrixScopeLabel(String scope) {
    return switch (scope.trim()) {
      'all' => '范围：全部未完成',
      '3days' => '范围：近3天',
      _ => '范围：今天',
    };
  }

  Widget _buildMatrixWorkspace(
    BuildContext context, {
    required List<Task> tasks,
    required bool showDetailPanel,
    required Task? selectedTask,
  }) {
    final normalized = <Task>[];
    for (final task in tasks) {
      final nextPriority = _normalizeMatrixPriority(task.priority);
      normalized.add(nextPriority == task.priority
          ? task
          : task.copyWith(priority: nextPriority));
    }

    final q1 = <Task>[];
    final q2 = <Task>[];
    final q3 = <Task>[];
    final q4 = <Task>[];
    var unsetCount = 0;

    for (final task in normalized) {
      switch (task.priority) {
        case 4:
          q1.add(task);
          break;
        case 3:
          q2.add(task);
          break;
        case 2:
          q3.add(task);
          break;
        case 1:
          q4.add(task);
          break;
        default:
          unsetCount += 1;
          q4.add(task);
          break;
      }
    }

    int compareTask(Task a, Task b) {
      if (a.dueDate.isEmpty && b.dueDate.isNotEmpty) return 1;
      if (a.dueDate.isNotEmpty && b.dueDate.isEmpty) return -1;
      final dateCompare = a.dueDate.compareTo(b.dueDate);
      if (dateCompare != 0) return dateCompare;
      final aStart = _parseTimeMinutes(a.startTime) ?? 9999;
      final bStart = _parseTimeMinutes(b.startTime) ?? 9999;
      if (aStart != bStart) return aStart.compareTo(bStart);
      return b.updatedAt.compareTo(a.updatedAt);
    }

    q1.sort(compareTask);
    q2.sort(compareTask);
    q3.sort(compareTask);
    q4.sort(compareTask);

    final grid = LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 900;

        Widget panel({
          required String title,
          required String subtitle,
          required int targetPriority,
          required List<Task> items,
          required Color accent,
        }) {
          return _buildMatrixQuadrantPanel(
            context,
            title: title,
            subtitle: subtitle,
            accent: accent,
            tasks: items,
            targetPriority: targetPriority,
            showDetailPanel: showDetailPanel,
            selectedTaskId: selectedTask?.id,
          );
        }

        final q1Panel = panel(
          title: 'Q1 重要且紧急',
          subtitle: '马上做',
          targetPriority: 4,
          items: q1,
          accent: AppColors.accentDeep,
        );
        final q2Panel = panel(
          title: 'Q2 重要不紧急',
          subtitle: '计划做',
          targetPriority: 3,
          items: q2,
          accent: AppColors.accentCool,
        );
        final q3Panel = panel(
          title: 'Q3 紧急不重要',
          subtitle: '尽快做 / 可委托',
          targetPriority: 2,
          items: q3,
          accent: AppColors.accent,
        );
        final q4Panel = panel(
          title: 'Q4 不重要不紧急',
          subtitle: unsetCount > 0 ? '低优先级 · 未设置 $unsetCount' : '低优先级',
          targetPriority: 1,
          items: q4,
          accent: AppColors.accentSoft,
        );

        if (isNarrow) {
          const panelHeight = 320.0;
          return ListView(
            children: [
              SizedBox(height: panelHeight, child: q1Panel),
              const SizedBox(height: 12),
              SizedBox(height: panelHeight, child: q2Panel),
              const SizedBox(height: 12),
              SizedBox(height: panelHeight, child: q3Panel),
              const SizedBox(height: 12),
              SizedBox(height: panelHeight, child: q4Panel),
            ],
          );
        }

        return Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  Expanded(child: q1Panel),
                  const SizedBox(height: 12),
                  Expanded(child: q3Panel),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                children: [
                  Expanded(child: q2Panel),
                  const SizedBox(height: 12),
                  Expanded(child: q4Panel),
                ],
              ),
            ),
          ],
        );
      },
    );

    final body = grid;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: body),
        if (showDetailPanel) ...[
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

  int _normalizeMatrixPriority(int raw) {
    if (raw < 0) return 0;
    if (raw > 4) return 0;
    return raw;
  }

  Widget _buildMatrixQuadrantPanel(
    BuildContext context, {
    required String title,
    required String subtitle,
    required Color accent,
    required List<Task> tasks,
    required int targetPriority,
    required bool showDetailPanel,
    required String? selectedTaskId,
  }) {
    return DragTarget<Task>(
      onWillAcceptWithDetails: (_) => !_saving,
      onAcceptWithDetails: (details) async {
        final task = details.data;
        if (_saving) return;
        if (_normalizeMatrixPriority(task.priority) == targetPriority) return;
        await _updateTaskFromDetail(task, priority: targetPriority);
        if (!mounted) return;
        setState(() => _selectedTaskId = task.id);
      },
      builder: (context, candidateData, rejectedData) {
        final highlight = candidateData.isNotEmpty;
        final borderColor =
            highlight ? accent.withOpacity(0.85) : AppColors.outline;
        final headerColor = highlight
            ? accent.withOpacity(0.10)
            : AppColors.surface.withOpacity(0.92);

        return Material(
          elevation: highlight ? 4 : 2,
          shadowColor: accent.withOpacity(0.18),
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(color: borderColor, width: highlight ? 2 : 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.surface.withOpacity(0.98),
                  accent.withOpacity(0.08),
                ],
              ),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                  width: double.infinity,
                  color: headerColor,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.ink,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.inkSoft,
                                  ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: accent.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: accent.withOpacity(0.35)),
                        ),
                        child: Text(
                          '${tasks.length}',
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: accent,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: tasks.isEmpty
                      ? Center(
                          child: Text(
                            '拖拽任务到这里',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppColors.inkSoft),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: tasks.length,
                          itemBuilder: (context, index) {
                            final task = tasks[index];
                            final selected = selectedTaskId == task.id;
                            final card = _MatrixTaskTile(
                              task: task,
                              selected: selected,
                              onTap: () {
                                if (showDetailPanel) {
                                  _selectTask(task.id);
                                } else {
                                  _openTaskDetailFromCalendar(task);
                                }
                              },
                              onToggle: () => _toggleTask(task),
                            );
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Draggable<Task>(
                                data: task,
                                onDragStarted: () => _setTaskDragActive(true),
                                onDragEnd: (_) => _setTaskDragActive(false),
                                onDragCompleted: () => _setTaskDragActive(false),
                                onDraggableCanceled: (_, __) => _setTaskDragActive(false),
                                feedback: Material(
                                  color: Colors.transparent,
                                  child: ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxWidth: 420),
                                    child: Opacity(opacity: 0.95, child: card),
                                  ),
                                ),
                                childWhenDragging:
                                    Opacity(opacity: 0.35, child: card),
                                child: card,
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _updateSearchQuery(String value) {
    if (_searchQuery == value) return;
    setState(() {
      _searchQuery = value;
      _selectedTaskId = null;
    });
  }

  void _setTaskDragActive(bool value) {
    if (_isTaskDragActive == value) return;
    setState(() => _isTaskDragActive = value);
  }

  void _openQuickAddSheet() {
    if (_saving || _androidQuickAddOpen) return;
    _quickAddController.clear();
    _resetQuickAddForm();
    setState(() {
      _quickAddExpanded = false;
      _androidQuickAddOpen = true;
    });
  }

  void _closeAndroidQuickAdd() {
    if (!_androidQuickAddOpen) return;
    FocusScope.of(context).unfocus();
    setState(() => _androidQuickAddOpen = false);
  }

  Widget _buildFloatingTrashTarget(BuildContext context) {
    final trashCount = _tasks.where((task) => task.deletedAt != null).length;
    return DragTarget<Task>(
      onWillAcceptWithDetails: (_) => !_saving,
      onAcceptWithDetails: (details) => _moveTaskToTrash(details.data),
      builder: (context, candidate, rejected) {
        final hovering = candidate.isNotEmpty;
        final icon = hovering ? Icons.delete : Icons.delete_outline;
        final borderColor = hovering ? AppColors.accent : AppColors.outline;
        final bg = hovering
            ? AppColors.accent.withOpacity(0.18)
            : AppColors.surface.withOpacity(0.95);
        final iconColor = hovering ? AppColors.accentDeep : AppColors.inkSoft;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _openTrash,
            borderRadius: BorderRadius.circular(999),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: bg,
                shape: BoxShape.circle,
                border: Border.all(color: borderColor, width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.14),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedScale(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOut,
                    scale: hovering ? 1.18 : 1.0,
                    child: Icon(icon, size: 26, color: iconColor),
                  ),
                  if (trashCount > 0)
                    Positioned(
                      right: -6,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.accentDeep,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: AppColors.surface, width: 2),
                        ),
                        child: Text(
                          trashCount > 99 ? '99+' : '$trashCount',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
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

  Widget _buildQuickAddField(
    BuildContext context, {
    Future<void> Function(String value)? onSubmitted,
    bool autofocus = false,
  }) {
    Future<void> submit() async {
      final handler = onSubmitted ?? _handleQuickAdd;
      await handler(_quickAddController.text);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.95),
        borderRadius: BorderRadius.zero,
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.add_circle_outline, color: AppColors.accentCool),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _quickAddController,
                  autofocus: autofocus,
                  enabled: !_saving,
                  decoration: InputDecoration(
                    hintText: _saving ? '正在保存...' : '输入任务名称，回车添加',
                    border: InputBorder.none,
                    isDense: true,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: onSubmitted ?? _handleQuickAdd,
                ),
              ),
              if (_useAndroidUi)
                IconButton(
                  onPressed: _saving ? null : submit,
                  icon: const Icon(Icons.check),
                  tooltip: '添加',
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
            if (_useAndroidUi)
              Column(
                children: [
                  _buildQuickAddPicker(
                    context,
                    label: '开始',
                    value: _formatQuickAddStartDateTime(context),
                    width: double.infinity,
                    onTap: _pickQuickAddStartDateTime,
                  ),
                  const SizedBox(height: 8),
                  _buildQuickAddPicker(
                    context,
                    label: '截止',
                    value: _formatQuickAddEndDateTime(context),
                    width: double.infinity,
                    onTap: _pickQuickAddEndDateTime,
                  ),
                  const SizedBox(height: 12),
                  _buildQuickAddPicker(
                    context,
                    label: '重复',
                    value: _repeatSummary(),
                    width: double.infinity,
                    onTap: _openRepeatConfig,
                  ),
                  const SizedBox(height: 8),
                  _buildQuickAddPicker(
                    context,
                    label: '提醒',
                    value: _remindSummary(),
                    width: double.infinity,
                    onTap: _handleQuickAddRemindTap,
                  ),
                  const SizedBox(height: 8),
                  _buildQuickAddPicker(
                    context,
                    label: '附件',
                    value: _attachmentSummary(),
                    width: double.infinity,
                    onTap: _pickQuickAddAttachments,
                  ),
                  const SizedBox(height: 8),
                  _buildQuickAddPicker(
                    context,
                    label: '颜色',
                    value: _quickAddColorHex.isEmpty
                        ? _quickAddDefaultColorLabel
                        : '#${_quickAddColorHex.toUpperCase()}',
                    width: double.infinity,
                    onTap: _pickQuickAddColor,
                  ),
                  const SizedBox(height: 8),
                  _buildQuickAddPicker(
                    context,
                    label: '四象限',
                    value: _matrixSummary(),
                    width: double.infinity,
                    onTap: _pickQuickAddMatrixPriority,
                  ),
                  const SizedBox(height: 8),
                  _buildQuickAddPicker(
                    context,
                    label: '子任务',
                    value: _subtaskSummary(),
                    width: double.infinity,
                    onTap: _toggleQuickAddSubtasks,
                  ),
                ],
              )
            else
              Align(
                alignment: Alignment.centerLeft,
                child: SingleChildScrollView(
                  key: const ValueKey('task_detail_scroll'),
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildQuickAddPicker(
                        context,
                        label: '开始',
                        value: _formatQuickAddStartDateTime(context),
                        width: 200,
                        onTap: _pickQuickAddStartDateTime,
                      ),
                      const SizedBox(width: 8),
                      _buildQuickAddPicker(
                        context,
                        label: '截止',
                        value: _formatQuickAddEndDateTime(context),
                        width: 200,
                        onTap: _pickQuickAddEndDateTime,
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
                        icon: Icons.grid_view_rounded,
                        label: _matrixSummary(),
                        active: _quickAddMatrixPriority != 0,
                        onTap: _pickQuickAddMatrixPriority,
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
        color: AppColors.surface.withOpacity(0.95),
        borderRadius: BorderRadius.zero,
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        children: [
          Icon(Icons.playlist_add, color: AppColors.accentCool),
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

  Future<bool> _tryQuickAdd(String value) async {
    final parsed = _parseQuickAddInput(value);
    final title = parsed.title.trim();
    if (title.isEmpty || _saving) return false;

    _quickAddController.clear();
    FocusScope.of(context).unfocus();
    final subtasks = _buildSubtasksFromDrafts();
    final startTimeValue = _quickAddStartTime;
    final endTimeValue = _quickAddEndTime;
    final startTime = _timeToString(startTimeValue);
    final endTime = _timeToString(endTimeValue);
    var endDayOffset = _quickAddEndDayOffset.clamp(0, 36525);
    if (endTime.isNotEmpty &&
        startTimeValue != null &&
        endTimeValue != null &&
        endDayOffset == 0) {
      final startMinutes = startTimeValue.hour * 60 + startTimeValue.minute;
      final endMinutes = endTimeValue.hour * 60 + endTimeValue.minute;
      if (endMinutes <= startMinutes) {
        endDayOffset = 1;
      }
    }
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
            endDayOffset: endDayOffset,
            endTime: endTime,
            repeatRule: repeatRule,
            remindAt: _buildRemindAtForDate(date, baseDate),
            subtasks: subtasks,
            priority: _normalizeMatrixPriority(_quickAddMatrixPriority),
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
          endDayOffset: endDayOffset,
          endTime: endTime,
          repeatRule: repeatRule,
          remindAt: _buildSingleRemindAt(),
          subtasks: subtasks,
          priority: _normalizeMatrixPriority(_quickAddMatrixPriority),
        ),
      );
    }

    final created = await _addTasks(tasksToCreate);
    if (created.isEmpty) return false;
    if (_quickAddAttachments.isNotEmpty) {
      await _uploadQuickAddAttachments(created.first);
    }
    _resetQuickAddForm();
    return true;
  }

  Future<void> _handleQuickAdd(String value) async {
    await _tryQuickAdd(value);
  }

  void _toggleQuickAddExpanded() {
    setState(() => _quickAddExpanded = !_quickAddExpanded);
  }

  Future<void> _pickQuickAddStartDateTime() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _quickAddDate ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (pickedDate == null) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: _quickAddStartTime ?? TimeOfDay.now(),
    );
    if (!mounted) return;
    setState(() {
      _quickAddDate = pickedDate;
      if (pickedTime != null) _quickAddStartTime = pickedTime;
    });
  }

  Future<void> _pickQuickAddEndDateTime() async {
    final now = DateTime.now();
    final base =
        _quickAddDate ?? DateTime(now.year, now.month, now.day);
    final baseDay = DateTime(base.year, base.month, base.day);
    final initialDate =
        baseDay.add(Duration(days: _quickAddEndDayOffset.clamp(0, 36525)));
    final maxDate = DateTime(2100);
    final safeInitialDate =
        initialDate.isAfter(maxDate) ? maxDate : initialDate;
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: safeInitialDate,
      firstDate: baseDay,
      lastDate: maxDate,
    );
    if (pickedDate == null) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: _quickAddEndTime ?? TimeOfDay.now(),
    );
    if (!mounted) return;
    setState(() {
      final pickedDay =
          DateTime(pickedDate.year, pickedDate.month, pickedDate.day);
      if (_quickAddDate == null) _quickAddDate = baseDay;
      _quickAddEndDayOffset =
          pickedDay.difference(baseDay).inDays.clamp(0, 36525);
      if (pickedTime != null) _quickAddEndTime = pickedTime;
    });
  }

  String _formatQuickAddStartDateTime(BuildContext context) {
    final date = _quickAddDate;
    final time = _quickAddStartTime;
    if (date == null && time == null) return '未设置';
    final dateLabel = date == null ? '' : DateFormat('M月d日').format(date);
    final timeLabel = time == null ? '' : time.format(context);
    final parts = [dateLabel, timeLabel].where((value) => value.isNotEmpty);
    return parts.isEmpty ? '未设置' : parts.join(' ');
  }

  String _formatQuickAddEndDateTime(BuildContext context) {
    final time = _quickAddEndTime;
    if (time == null) return '未设置';
    final offsetDays = _quickAddEndDayOffset.clamp(0, 36525);
    final baseDate = _quickAddDate;
    final dateLabel = baseDate == null
        ? (offsetDays > 0 ? '+$offsetDays天' : '')
        : DateFormat('M月d日')
            .format(baseDate.add(Duration(days: offsetDays)));
    final timeLabel = time.format(context);
    final parts = [dateLabel, timeLabel].where((value) => value.isNotEmpty);
    return parts.isEmpty ? '未设置' : parts.join(' ');
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

  String _matrixSummary() {
    final normalized = _normalizeMatrixPriority(_quickAddMatrixPriority);
    final label = switch (normalized) {
      4 => 'Q1',
      3 => 'Q2',
      2 => 'Q3',
      1 => 'Q4',
      _ => '未设置',
    };
    if (label == '未设置') return label;
    return '四象限 $label';
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

  Future<void> _pickQuickAddMatrixPriority() async {
    if (_saving) return;
    final current = _normalizeMatrixPriority(_quickAddMatrixPriority);
    final next = await showDialog<int>(
      context: context,
      builder: (context) {
        Widget option(int value, String label) {
          final selected = value == current;
          return SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(value),
            child: Row(
              children: [
                Expanded(child: Text(label)),
                if (selected)
                  Icon(Icons.check, size: 18, color: AppColors.accent),
              ],
            ),
          );
        }

        return SimpleDialog(
          title: const Text('四象限设置'),
          children: [
            option(0, '未设置'),
            option(4, 'Q1 重要且紧急'),
            option(3, 'Q2 重要不紧急'),
            option(2, 'Q3 紧急不重要'),
            option(1, 'Q4 不重要不紧急'),
          ],
        );
      },
    );
    if (next == null) return;
    if (!mounted) return;
    setState(() => _quickAddMatrixPriority = _normalizeMatrixPriority(next));
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
                    color: AppColors.surface,
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
                        child: Icon(Icons.close,
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
      _quickAddEndDayOffset = 0;
      _quickAddRepeat = false;
      _quickAddRepeatFrequency = RepeatFrequency.daily;
      _quickAddRepeatCount = 1;
      _quickAddRepeatWeekdays = {};
      _quickAddRepeatMonthDay = 1;
      _quickAddRepeatYearMonth = 1;
      _quickAddRepeatYearDay = 1;
      _quickAddRemindAt = null;
      _quickAddMatrixPriority = 0;
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
            color: AppColors.surface,
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
    final shouldCloseChecklist = _activeChecklistId != null;
    final shouldCloseTrash = _showTrash;
    final shouldClearSelection = _selectedTaskId != null;
    if (_filter == filter &&
        !shouldCloseChecklist &&
        !shouldCloseTrash &&
        !shouldClearSelection) {
      return;
    }
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
    if (!mounted) return;
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) return;

    setState(() => _saving = true);
    try {
      final created = await widget.apiClient.createChecklist(name: trimmed);
      if (!mounted) return;
      setState(() {
        _checklists = [..._checklists, created];
        _activeChecklistId = created.id;
        _showTrash = false;
        _selectedTaskId = null;
      });
      await _loadChecklistItems(created.id);
    } on UnauthorizedException {
      widget.onLogout();
    } catch (e) {
      _showFailureSnackBar('创建清单失败', e);
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
    if (!mounted) return;
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      await widget.apiClient.deleteChecklist(list.id);
      if (!mounted) return;
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
      if (!mounted) return;
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
      if (!mounted) return;
      setState(() {
        final existing = _checklistItems[listId] ?? <ChecklistItem>[];
        _checklistItems[listId] = [...existing, created];
      });
    } on UnauthorizedException {
      widget.onLogout();
    } catch (e) {
      _showFailureSnackBar('创建清单事项失败', e);
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
      if (!mounted) return;
      setState(() {
        final items = _checklistItems[item.listId] ?? <ChecklistItem>[];
        _checklistItems[item.listId] =
            items.map((it) => it.id == item.id ? updated : it).toList();
      });
    } on UnauthorizedException {
      widget.onLogout();
    } catch (_) {
      if (!mounted) return;
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
    if (!mounted) return;
    if (confirmed != true) return;

    final snapshot = _undoEnabled ? item : null;
    setState(() => _saving = true);
    try {
      await widget.apiClient
          .deleteChecklistItem(listId: item.listId, itemId: item.id);
      if (!mounted) return;
      setState(() {
        final items = _checklistItems[item.listId] ?? <ChecklistItem>[];
        _checklistItems[item.listId] =
            items.where((it) => it.id != item.id).toList();
      });
      if (snapshot != null) {
        _queueUndo(
          message: '已删除事项。',
          onUndo: () async {
            final created = await widget.apiClient.createChecklistItem(
              listId: snapshot.listId,
              title: snapshot.title,
              notes: snapshot.notes,
              columnId: snapshot.columnId,
            );
            final restored = snapshot.completed
                ? await widget.apiClient.updateChecklistItem(
                    listId: snapshot.listId,
                    itemId: created.id,
                    completed: true,
                  )
                : created;
            if (!mounted) return;
            setState(() {
              final items = _checklistItems[snapshot.listId] ?? <ChecklistItem>[];
              _checklistItems[snapshot.listId] = [...items, restored];
            });
          },
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已删除事项。'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } on UnauthorizedException {
      widget.onLogout();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('删除事项失败。')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _moveTaskToTrash(Task task) async {
    if (_saving) return false;
    final snapshot = _undoEnabled ? task.copyWith() : null;
    setState(() => _saving = true);
    try {
      await widget.apiClient.deleteTask(task.id);
      if (!context.mounted) return false;
      if (_selectedTaskId == task.id) {
        setState(() => _selectedTaskId = null);
      }
      await _loadTasks();
      if (!context.mounted) return false;
      if (snapshot != null) {
        _queueUndo(
          message: '已移入回收站。',
          onUndo: () => _applyTaskSnapshot(snapshot),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('已移入回收站。'),
            duration: const Duration(seconds: 1),
            action: SnackBarAction(
              label: '查看',
              onPressed: _openTrash,
            ),
          ),
        );
      }
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

  void _handleWorkspaceChanged(WorkspaceView view) {
    _isTaskDragActive = false;
    _androidQuickAddOpen = false;
    _quickAddExpanded = false;
    if (view != WorkspaceView.tasks) {
      setState(() {
        _showTrash = false;
        _searchQuery = '';
        _selectedTaskId = null;
        _searchController.clear();
      });
    }

    if (view == WorkspaceView.timeTracking && _activities.isEmpty && !_loadingTime) {
      _loadTimeTracking();
    }
    if (view == WorkspaceView.stats &&
        (_timeStats == null || _pomodoroSummary == null) &&
        !_loadingStats) {
      _loadTimeStats();
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
    if (_savingTime) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final running = _runningEntries.where((entry) => entry.isRunning).toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    final wasRunning = running.any((entry) => entry.activityId == activity.id);

    final previousRunning = List<TimeEntry>.from(_runningEntries);
    final previousEntries = List<TimeEntry>.from(_timeEntries);

    final optimisticStopped = running
        .map(
          (entry) => TimeEntry(
            id: entry.id,
            activityId: entry.activityId,
            taskId: entry.taskId,
            startedAt: entry.startedAt,
            endedAt: nowMs,
            durationMs: null,
            note: entry.note,
            tags: entry.tags,
            createdAt: entry.createdAt,
            updatedAt: nowMs,
            deletedAt: entry.deletedAt,
          ),
        )
        .toList();

    final optimisticStartId = wasRunning ? null : 'optimistic_$nowMs';
    final optimisticStartEntry = optimisticStartId == null
        ? null
        : TimeEntry(
            id: optimisticStartId,
            activityId: activity.id,
            taskId: activity.taskId,
            startedAt: nowMs,
            endedAt: null,
            durationMs: null,
            note: '',
            tags: const <String>[],
            createdAt: nowMs,
            updatedAt: nowMs,
            deletedAt: null,
          );

    setState(() {
      _savingTime = true;
      _runningEntries =
          optimisticStartEntry == null ? <TimeEntry>[] : [optimisticStartEntry];
      _timeEntries = _mergeTimeEntries(_timeEntries, optimisticStopped);
      if (optimisticStartEntry != null) {
        _timeEntries = _mergeTimeEntries(_timeEntries, [optimisticStartEntry]);
      }
      _lastTimeSync = DateTime.now();
    });

    try {
      final stopped = running.isEmpty
          ? const <TimeEntry>[]
          : await Future.wait(
              running.map(
                (entry) =>
                    widget.apiClient.stopEntry(entry.id, endedAt: nowMs),
              ),
            );

      if (wasRunning) {
        if (!mounted) return;
        setState(() {
          _runningEntries = <TimeEntry>[];
          _timeEntries = _mergeTimeEntries(_timeEntries, stopped);
          _lastTimeSync = DateTime.now();
        });
        return;
      }

      final entry = await widget.apiClient.startEntry(
        activityId: activity.id,
        taskId: activity.taskId,
        startedAt: nowMs,
      );
      if (!mounted) return;
      setState(() {
        if (optimisticStartId != null) {
          _timeEntries = _timeEntries
              .where((candidate) => candidate.id != optimisticStartId)
              .toList();
        }
        _runningEntries = [entry];
        _timeEntries = _mergeTimeEntries(_timeEntries, stopped);
        _timeEntries = _mergeTimeEntries(_timeEntries, [entry]);
        _lastTimeSync = DateTime.now();
      });
    } on UnauthorizedException {
      widget.onLogout();
    } catch (_) {
      if (!context.mounted) return;
      setState(() {
        _runningEntries = previousRunning;
        _timeEntries = previousEntries;
      });
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
    final snapshot = _undoEnabled ? activity : null;
    setState(() => _savingTime = true);
    try {
      await widget.apiClient.deleteActivity(activity.id);
      if (!mounted) return;
      setState(() {
        _activities =
            _activities.where((item) => item.id != activity.id).toList();
        _runningEntries = _runningEntries
            .where((entry) => entry.activityId != activity.id)
            .toList();
        _lastTimeSync = DateTime.now();
      });
      if (snapshot != null) {
        _queueUndo(
          message: '已删除事件。',
          onUndo: () async {
            await widget.apiClient.updateActivity(
              snapshot.id,
              clearDeletedAt: true,
            );
            await _loadTimeTracking();
          },
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已删除事件。'),
            duration: Duration(seconds: 1),
          ),
        );
      }
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
        String resolveEndDate() {
          final dueDate = defaults.dueDate.trim();
          if (dueDate.isEmpty) return '';
          if (draft.endTime.trim().isEmpty) return '';
          try {
            final start = _dateFormatter.parseStrict(dueDate);
            final offset = draft.endDayOffset.clamp(0, 36525);
            return _dateFormatter.format(start.add(Duration(days: offset)));
          } catch (_) {
            return '';
          }
        }

        final task = await widget.apiClient.createTask(
          title: draft.title,
          notes: draft.notes,
          dueDate: defaults.dueDate,
          startTime: draft.startTime,
          endDate: resolveEndDate(),
          endTime: draft.endTime,
          tags: draft.tags,
          priority: draft.priority,
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
      unawaited(_syncLocalTaskReminders());
    } on UnauthorizedException {
      widget.onLogout();
    } catch (e) {
      _showFailureSnackBar('创建任务失败', e);
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

    String dueDate = date != null ? _dateFormatter.format(date) : '';
    bool inbox = false;
    String status = 'todo';

    if (dueDate.isEmpty) {
      switch (_filter) {
        case TaskFilter.today:
          dueDate = today;
          break;
        case TaskFilter.next7:
          dueDate = today;
          break;
        case TaskFilter.done:
          status = 'completed';
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
    if (_saving) return;
    await _updateTaskFromDetail(
      task,
      status: task.isCompleted ? 'todo' : 'completed',
      undoMessage: task.isCompleted ? '已恢复为待办。' : '已完成任务。',
    );
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
    if (_saving) return;
    await _updateTaskFromDetail(
      task,
      status: status,
      subtasks: updatedSubtasks,
      undoMessage: '已更新子任务。',
    );
  }

  Future<void> _applyDropToFilter(Task task, TaskFilter target) async {
    if (_saving) return;

    final now = DateTime.now();
    final todayStr = _dateFormatter.format(now);
    final next7Str = _dateFormatter.format(now.add(const Duration(days: 7)));

    switch (target) {
      case TaskFilter.today:
        await _updateTaskFromDetail(
          task,
          dueDate: todayStr,
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
    String? endDate,
    String? endTime,
    List<String>? tags,
    List<TaskSubtask>? subtasks,
    bool? inbox,
    int? priority,
    int? remindAt,
    bool clearRemindAt = false,
    String? repeatRule,
    bool clearDeletedAt = false,
    bool allowUndo = true,
    String? undoMessage,
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
        endDate: endDate,
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
      unawaited(_syncLocalTaskReminders());
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
      unawaited(_syncLocalTaskReminders());
    } on UnauthorizedException {
      widget.onLogout();
    } catch (e) {
      _showFailureSnackBar('加载任务失败', e);
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
      String endDate = '';
      String endTime = '';
      if (startTime != null) {
        final startAt = DateTime(
          date.year,
          date.month,
          date.day,
          startTime.hour,
          startTime.minute,
        );
        final endAt = startAt.add(const Duration(minutes: 15));
        endDate = _dateFormatter.format(endAt);
        endTime = _timeToString(TimeOfDay.fromDateTime(endAt));
      }
      final created = await widget.apiClient.createTask(
        title: title,
        dueDate: dueDate,
        startTime: start,
        endDate: endDate,
        endTime: endTime,
        inbox: false,
        status: 'todo',
      );
      final next = [..._tasks, created]..sort(_sortTask);
      setState(() {
        _tasks = next;
        _lastSync = DateTime.now();
        _selectedTaskId = created.id;
      });
      unawaited(_syncLocalTaskReminders());
      return created;
    } on UnauthorizedException {
      widget.onLogout();
    } catch (e) {
      _showFailureSnackBar('创建任务失败', e);
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
    final dueDate = _dateFormatter.format(date);
    if (startTime == null) {
      final wasAllDay = task.startTime.trim().isEmpty;
      String nextEndDate = '';
      if (wasAllDay) {
        try {
          final startDay = _dateFormatter.parseStrict(task.dueDate);
          final endKey = task.endDate.trim();
          final endDay = endKey.isNotEmpty
              ? _dateFormatter.parseStrict(endKey)
              : startDay;
          final spanDays = endDay.difference(startDay).inDays;
          if (spanDays > 0) {
            nextEndDate =
                _dateFormatter.format(date.add(Duration(days: spanDays)));
          }
        } catch (_) {}
      }
      await _updateTaskFromDetail(
        task,
        dueDate: dueDate,
        startTime: '',
        endDate: nextEndDate,
        endTime: '',
        inbox: false,
        undoMessage: '已更新日程。',
      );
      return;
    }

    final start = _timeToString(startTime);
    final startAt = DateTime(
      date.year,
      date.month,
      date.day,
      startTime.hour,
      startTime.minute,
    );

    DateTime endAt;
    if (endTime != null) {
      final startMinutes = startTime.hour * 60 + startTime.minute;
      final pickedMinutes = endTime.hour * 60 + endTime.minute;
      final crossesMidnight =
          (pickedMinutes == 0 && startMinutes > 0) ||
              pickedMinutes <= startMinutes;
      endAt = DateTime(
        date.year,
        date.month,
        date.day,
        endTime.hour,
        endTime.minute,
      ).add(Duration(days: crossesMidnight ? 1 : 0));
      if (endAt.difference(startAt).inMinutes < 15) {
        endAt = startAt.add(const Duration(minutes: 15));
      }
    } else {
      final durationMinutes =
          (_taskDurationMinutes(task) ?? 15).clamp(15, 36525 * 24 * 60);
      endAt = startAt.add(Duration(minutes: durationMinutes));
    }

    await _updateTaskFromDetail(
      task,
      dueDate: dueDate,
      startTime: start,
      endDate: _dateFormatter.format(endAt),
      endTime: _timeToString(TimeOfDay.fromDateTime(endAt)),
      inbox: false,
      undoMessage: '已更新日程。',
    );
  }

  int? _parseTimeMinutes(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final timePart = trimmed.split('+').first.trim();
    final parts = timePart.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 24) return null;
    if (minute < 0 || minute > 59) return null;
    if (hour == 24 && minute != 0) return null;
    return hour * 60 + minute;
  }

  int _parseEndOffsetDays(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 0;
    final plusIndex = trimmed.lastIndexOf('+');
    if (plusIndex <= 0) return 0;
    final parsed = int.tryParse(trimmed.substring(plusIndex + 1).trim()) ?? 0;
    return parsed < 0 ? 0 : parsed;
  }

  int? _taskDurationMinutes(Task task) {
    final startDayKey = task.dueDate.trim();
    if (startDayKey.isEmpty) return null;
    final startMinutes = _parseTimeMinutes(task.startTime);
    if (startMinutes == null) return null;
    final endRaw = task.endTime.trim();
    if (endRaw.isEmpty) return null;

    final plusIndex = endRaw.lastIndexOf('+');
    final hasExplicitOffset = plusIndex > 0;
    final explicitOffset = hasExplicitOffset
        ? (int.tryParse(endRaw.substring(plusIndex + 1).trim()) ?? 0)
        : 0;
    final timePart =
        (hasExplicitOffset ? endRaw.substring(0, plusIndex) : endRaw).trim();
    var endMinutes = _parseTimeMinutes(timePart);
    if (endMinutes == null) return null;

    DateTime? startDay;
    try {
      startDay = _dateFormatter.parseStrict(startDayKey);
    } catch (_) {
      startDay = DateTime.tryParse('${startDayKey}T00:00:00');
    }
    if (startDay == null) return null;

    DateTime endDay = startDay;
    final endDateKey = task.endDate.trim();
    if (endDateKey.isNotEmpty) {
      try {
        final parsed = _dateFormatter.parseStrict(endDateKey);
        if (!parsed.isBefore(startDay)) endDay = parsed;
      } catch (_) {
        final parsed = DateTime.tryParse('${endDateKey}T00:00:00');
        if (parsed != null && !parsed.isBefore(startDay)) endDay = parsed;
      }
    } else if (explicitOffset > 0) {
      endDay = startDay.add(Duration(days: explicitOffset));
    } else {
      final legacyOffset = _parseEndOffsetDays(endRaw);
      if (legacyOffset > 0) {
        endDay = startDay.add(Duration(days: legacyOffset));
      }
    }

    if (endMinutes == 24 * 60 || timePart == '24:00') {
      endMinutes = 0;
      endDay = endDay.add(const Duration(days: 1));
    } else if (endDay.year == startDay.year &&
        endDay.month == startDay.month &&
        endDay.day == startDay.day &&
        endMinutes <= startMinutes) {
      endDay = endDay.add(const Duration(days: 1));
    }

    final startAt = DateTime(
      startDay.year,
      startDay.month,
      startDay.day,
      startMinutes ~/ 60,
      startMinutes % 60,
    );
    final endAt = DateTime(
      endDay.year,
      endDay.month,
      endDay.day,
      endMinutes ~/ 60,
      endMinutes % 60,
    );

    final duration = endAt.difference(startAt).inMinutes;
    if (duration <= 0) return null;
    return duration;
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
                String? endDate,
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
                  endDate: endDate,
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
                  color: AppColors.surface,
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

  Widget _wrapAndroidSwipeEditTask(Task task, Widget child) {
    if (!_useAndroidUi || task.deletedAt != null) return child;
    final accent = AppColors.accentCool;
    return Dismissible(
      key: ValueKey('task_swipe_edit_${task.id}'),
      direction: DismissDirection.endToStart,
      dismissThresholds: const {DismissDirection.endToStart: 0.28},
      confirmDismiss: (direction) async {
        if (direction != DismissDirection.endToStart) return false;
        if (_saving) return false;
        HapticFeedback.selectionClick();
        _openTaskDetailFromCalendar(task);
        return false;
      },
      background: const SizedBox.shrink(),
      secondaryBackground: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        alignment: Alignment.centerRight,
        color: accent.withOpacity(0.12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.edit, size: 20, color: accent),
            const SizedBox(width: 8),
            Text(
              '编辑',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
            ),
          ],
        ),
      ),
      child: child,
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
      WorkspaceView.matrix: visible,
      WorkspaceView.timeTracking: visibleActivities,
      WorkspaceView.calendar: 0,
      WorkspaceView.pomodoro: 0,
      WorkspaceView.stats: 0,
    };
  }

  List<Task> _applyFilter(List<Task> tasks, TaskFilter filter) {
    final today = DateTime.now();
    final todayStr = _dateFormatter.format(today);
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
      case TaskFilter.next7:
        result = visible
            .where((task) => !task.isCompleted && isWithinWeek(task))
            .toList();
        break;
      case TaskFilter.done:
        result = visible.where((task) => task.isCompleted).toList();
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
          final hasTitle = title.trim().isNotEmpty;
          final hasSubtitle = subtitle.trim().isNotEmpty;

          final titleWidget = Text(
            title,
            style: GoogleFonts.fraunces(
              textStyle: Theme.of(context).textTheme.headlineSmall,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          );
          final bodyWidget = Text(
            subtitle,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.inkSoft),
          );
          final leftChildren = <Widget>[
            if (hasTitle) titleWidget,
            if (hasTitle && hasSubtitle) const SizedBox(height: 6),
            if (hasSubtitle) bodyWidget,
          ];
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
                ...leftChildren,
                if (leftChildren.isNotEmpty) const SizedBox(height: 12),
                stats,
              ],
            );
          }

          if (leftChildren.isEmpty) {
            return Align(alignment: Alignment.centerRight, child: stats);
          }

          return Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...leftChildren,
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
                    ? Border(
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
    this.singleRow = false,
    required this.onSelect,
    required this.onDropTask,
  });

  final TaskFilter selected;
  final Map<TaskFilter, int> counts;
  final int? activeChecklistId;
  final bool saving;
  final bool singleRow;
  final ValueChanged<TaskFilter> onSelect;
  final void Function(Task task, TaskFilter target) onDropTask;

  @override
  Widget build(BuildContext context) {
    final chips = TaskFilter.values.map((filter) {
      final count = counts[filter] ?? 0;
      final label = count > 0 ? '${filter.label} · $count' : filter.label;
      return DragTarget<Task>(
        onWillAcceptWithDetails: (_) => !saving,
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
    }).toList();

    if (singleRow) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < chips.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              chips[i],
            ],
          ],
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: chips,
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
    this.singleRow = false,
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
  final bool singleRow;
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
          Builder(
            builder: (context) {
              final chips = checklists
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
                  .toList();

              if (singleRow) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var i = 0; i < chips.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        chips[i],
                      ],
                    ],
                  ),
                );
              }

              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: chips,
              );
            },
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
                  : AppColors.surface.withOpacity(0.85),
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
            Icon(Icons.inventory_2_outlined,
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

class _MatrixTaskTile extends StatelessWidget {
  const _MatrixTaskTile({
    required this.task,
    required this.selected,
    required this.onTap,
    required this.onToggle,
  });

  final Task task;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return TaskCard(
      task: task,
      isSelected: selected,
      onTap: onTap,
      onToggle: onToggle,
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
  String? endDate,
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

  int? _parseTimeMinutes(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final timePart = trimmed.split('+').first.trim();
    final parts = timePart.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 24) return null;
    if (minute < 0 || minute > 59) return null;
    if (hour == 24 && minute != 0) return null;
    return hour * 60 + minute;
  }

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
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;
      final timePart = trimmed.split('+').first.trim();
      if (timePart == '24:00') return const TimeOfDay(hour: 0, minute: 0);
      final parts = timePart.split(':');
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

    Future<void> pickStartDateTime() async {
      final now = DateTime.now();
      final initial = parseDate(task.dueDate) ?? now;
      final pickedDate = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );
      if (pickedDate == null) return;
      final currentStartTime = task.startTime.trim();
      final pickedTime = await showTimePicker(
        context: context,
        initialTime: parseTime(currentStartTime) ?? TimeOfDay.now(),
      );
      if (!context.mounted) return;
      final nextDueDate = DateFormat('yyyy-MM-dd').format(pickedDate);
      final nextStartTime =
          pickedTime == null ? currentStartTime : formatTime(pickedTime);

      final hasEnd = task.endTime.trim().isNotEmpty;
      String? nextEndDate;
      String? nextEndTime;
      if (hasEnd) {
        final oldStartDate = parseDate(task.dueDate);
        final oldStartTime = parseTime(task.startTime);
        final oldEndDate = parseDate(
          task.endDate.trim().isNotEmpty ? task.endDate : task.dueDate,
        );
        final oldEndTime = parseTime(task.endTime);
        final newStartTime = parseTime(nextStartTime);
        if (oldStartDate != null &&
            oldStartTime != null &&
            oldEndDate != null &&
            oldEndTime != null &&
            newStartTime != null) {
          final oldStartAt = DateTime(
            oldStartDate.year,
            oldStartDate.month,
            oldStartDate.day,
            oldStartTime.hour,
            oldStartTime.minute,
          );
          var oldEndAt = DateTime(
            oldEndDate.year,
            oldEndDate.month,
            oldEndDate.day,
            oldEndTime.hour,
            oldEndTime.minute,
          );
          if (!oldEndAt.isAfter(oldStartAt)) {
            oldEndAt = oldEndAt.add(const Duration(days: 1));
          }
          final duration = oldEndAt.difference(oldStartAt);
          final newStartAt = DateTime(
            pickedDate.year,
            pickedDate.month,
            pickedDate.day,
            newStartTime.hour,
            newStartTime.minute,
          );
          final newEndAt = newStartAt.add(duration);
          nextEndDate = DateFormat('yyyy-MM-dd').format(newEndAt);
          nextEndTime = formatTime(TimeOfDay.fromDateTime(newEndAt));
        } else {
          nextEndDate = task.endDate.trim().isNotEmpty ? task.endDate : nextDueDate;
          nextEndTime = task.endTime.trim();
          if (nextEndDate.compareTo(nextDueDate) < 0) {
            nextEndDate = nextDueDate;
          }
        }
      }
      await onUpdateTask(
        task,
        dueDate: nextDueDate,
        startTime: nextStartTime,
        endDate: nextEndDate,
        endTime: nextEndTime,
        inbox: false,
      );
    }

    Future<void> clearStartDateTime() async {
      await onUpdateTask(
        task,
        dueDate: '',
        startTime: '',
        endDate: '',
        endTime: '',
        inbox: task.isCompleted
            ? false
            : (task.checklistId != null ? false : true),
      );
    }

    Future<void> pickEndDateTime() async {
      final startDate = parseDate(task.dueDate);
      if (startDate == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先设置开始日期。')),
        );
        return;
      }
      final startDay = DateTime(startDate.year, startDate.month, startDate.day);
      final existingEndDate = parseDate(task.endDate) ?? startDay;
      final maxDate = DateTime(2100);
      final initialDate =
          existingEndDate.isBefore(startDay) ? startDay : existingEndDate;
      final safeInitialDate =
          initialDate.isAfter(maxDate) ? maxDate : initialDate;

      final pickedDate = await showDatePicker(
        context: context,
        initialDate: safeInitialDate,
        firstDate: startDay,
        lastDate: maxDate,
      );
      if (pickedDate == null) return;
      final pickedTime = await showTimePicker(
        context: context,
        initialTime: parseTime(task.endTime) ?? TimeOfDay.now(),
      );
      if (!context.mounted) return;
      if (pickedTime == null) return;

      var endDay = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
      );
      final startMinutes = _parseTimeMinutes(task.startTime);
      final endMinutes = pickedTime.hour * 60 + pickedTime.minute;
      if (endDay.year == startDay.year &&
          endDay.month == startDay.month &&
          endDay.day == startDay.day &&
          startMinutes != null &&
          endMinutes <= startMinutes) {
        endDay = startDay.add(const Duration(days: 1));
      }

      await onUpdateTask(
        task,
        endDate: DateFormat('yyyy-MM-dd').format(endDay),
        endTime: formatTime(pickedTime),
      );
    }

    Future<void> clearEndDateTime() async {
      await onUpdateTask(task, endDate: '', endTime: '');
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

    int normalizeMatrixPriority(int raw) {
      if (raw < 0 || raw > 4) return 0;
      return raw;
    }

    String matrixPriorityLabel(int raw) {
      switch (normalizeMatrixPriority(raw)) {
        case 4:
          return 'Q1 重要且紧急';
        case 3:
          return 'Q2 重要不紧急';
        case 2:
          return 'Q3 紧急不重要';
        case 1:
          return 'Q4 不重要不紧急';
        default:
          return '未设置';
      }
    }

    Future<void> editMatrixPriority() async {
      if (saving) return;
      final current = normalizeMatrixPriority(task.priority);
      final next = await showDialog<int>(
        context: context,
        builder: (context) {
          Widget option(int value, String label) {
            final selected = value == current;
            return SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(value),
              child: Row(
                children: [
                  Expanded(child: Text(label)),
                  if (selected)
                    Icon(Icons.check, size: 18, color: AppColors.accent),
                ],
              ),
            );
          }

          return SimpleDialog(
            title: const Text('四象限设置'),
            children: [
              option(0, '未设置'),
              option(4, 'Q1 重要且紧急'),
              option(3, 'Q2 重要不紧急'),
              option(2, 'Q3 紧急不重要'),
              option(1, 'Q4 不重要不紧急'),
            ],
          );
        },
      );
      if (next == null) return;
      final normalized = normalizeMatrixPriority(next);
      if (normalized == current) return;
      await onUpdateTask(task, priority: normalized);
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
            color: AppColors.surface,
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
                  child: Padding(
                    padding: EdgeInsets.all(4),
                    child:
                        Icon(Icons.close, size: 16, color: AppColors.inkSoft),
                  ),
                ),
              ] else ...[
                const SizedBox(width: 6),
                Icon(Icons.chevron_right, size: 18, color: AppColors.inkSoft),
              ],
            ],
          ),
        ),
      );
    }

    String formatStartDateTimeValue() {
      final dateRaw = task.dueDate.trim();
      final timeRaw = task.startTime.trim();
      if (dateRaw.isEmpty && timeRaw.isEmpty) return '未设置';
      final dateLabel = dateRaw.isEmpty ? '' : formatDateValue(dateRaw);
      final parts = [dateLabel, timeRaw].where((value) => value.isNotEmpty);
      return parts.isEmpty ? '未设置' : parts.join(' ');
    }

    String formatEndDateTimeValue() {
      final dateRaw = task.endDate.trim();
      final timeRaw = task.endTime.trim();
      if (dateRaw.isEmpty && timeRaw.isEmpty) return '未设置';
      if (timeRaw.isEmpty) {
        return dateRaw.isEmpty ? '未设置' : formatDateValue(dateRaw);
      }

      final startDateKey = task.dueDate.trim();
      final endDateKey = dateRaw.isEmpty ? startDateKey : dateRaw;
      final dateLabel =
          endDateKey.isEmpty || endDateKey == startDateKey
              ? ''
              : formatDateValue(endDateKey);

      final parts = [dateLabel, timeRaw].where((value) => value.isNotEmpty);
      return parts.isEmpty ? '未设置' : parts.join(' ');
    }

    final startAtValue = formatStartDateTimeValue();
    final endAtValue = formatEndDateTimeValue();
    final remindValue = formatRemindValue(task.remindAt);
    final repeatValue = formatRepeatValue(task.repeatRule);
    final matrixValue = matrixPriorityLabel(task.priority);
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
          label: '开始',
          value: startAtValue,
          icon: Icons.event,
          onTap: saving ? null : pickStartDateTime,
          onClear: saving ||
                  (task.dueDate.trim().isEmpty && task.startTime.trim().isEmpty)
              ? null
              : clearStartDateTime,
        ),
        const SizedBox(height: 8),
        settingTile(
          label: '截止',
          value: endAtValue,
          icon: Icons.timelapse,
          onTap: saving ? null : pickEndDateTime,
          onClear: saving ||
                  (task.endDate.trim().isEmpty && task.endTime.trim().isEmpty)
              ? null
              : clearEndDateTime,
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
        const SizedBox(height: 8),
        settingTile(
          label: '四象限',
          value: matrixValue,
          icon: Icons.grid_view_rounded,
          onTap: saving ? null : editMatrixPriority,
          onClear: saving || normalizeMatrixPriority(task.priority) == 0
              ? null
              : () => onUpdateTask(task, priority: 0),
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
              color: AppColors.surface,
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
              side: BorderSide(color: AppColors.accentDeep.withOpacity(0.55)),
              foregroundColor: AppColors.accentDeep,
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
      final startDateLabel = DateFormat('M月d日').format(date);
      final startTime = task.startTime.trim();
      final endRaw = task.endTime.trim();
      final endDateKey = task.endDate.trim();

      if (startTime.isEmpty && endRaw.isEmpty) {
        if (endDateKey.isNotEmpty) {
          try {
            final endDay = DateFormat('yyyy-MM-dd').parseStrict(endDateKey);
            if (endDay.isAfter(date)) {
              final endDateLabel = DateFormat('M月d日').format(endDay);
              return '$startDateLabel - $endDateLabel';
            }
          } catch (_) {}
        }
        return startDateLabel;
      }

      final startLabel =
          startTime.isEmpty ? startDateLabel : '$startDateLabel $startTime';
      if (endRaw.isEmpty) return startLabel;

      final plusIndex = endRaw.lastIndexOf('+');
      final hasExplicitOffset = plusIndex > 0;
      final explicitOffset = hasExplicitOffset
          ? (int.tryParse(endRaw.substring(plusIndex + 1).trim()) ?? 0)
          : 0;
      final timePart =
          (hasExplicitOffset ? endRaw.substring(0, plusIndex) : endRaw).trim();

      var offsetDays = explicitOffset;
      if (endDateKey.isNotEmpty) {
        try {
          final parsedEndDay = DateFormat('yyyy-MM-dd').parseStrict(endDateKey);
          offsetDays = parsedEndDay.difference(date).inDays;
        } catch (_) {}
      }
      if (offsetDays < 0) offsetDays = 0;
      var displayTime = timePart;
      if (timePart == '24:00') {
        offsetDays += 1;
        displayTime = '00:00';
      } else if (!hasExplicitOffset) {
        final startMinutes = _parseTimeMinutes(startTime);
        final endMinutes = _parseTimeMinutes(timePart);
        if (startMinutes != null &&
            endMinutes != null &&
            endMinutes <= startMinutes) {
          if (offsetDays == 0) offsetDays = 1;
        }
      }

      if (offsetDays > 0) {
        final endDateLabel =
            DateFormat('M月d日').format(date.add(Duration(days: offsetDays)));
        return startTime.isEmpty
            ? '$startDateLabel - $endDateLabel $displayTime'
            : '$startDateLabel $startTime - $endDateLabel $displayTime';
      }

      return startTime.isEmpty
          ? '$startDateLabel $displayTime'
          : '$startDateLabel $startTime - $displayTime';
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
    required this.endDayOffset,
    required this.endTime,
    required this.repeatRule,
    required this.remindAt,
    required this.subtasks,
    required this.priority,
    this.notes = '',
  });

  final String title;
  final List<String> tags;
  final String notes;
  final DateTime? date;
  final String startTime;
  final int endDayOffset;
  final String endTime;
  final String repeatRule;
  final int? remindAt;
  final List<TaskSubtask> subtasks;
  final int priority;
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

class _UndoAction {
  const _UndoAction({required this.message, required this.onUndo});

  final String message;
  final Future<void> Function() onUndo;
}
