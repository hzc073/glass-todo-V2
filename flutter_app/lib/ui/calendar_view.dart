import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'dart:math' as math;

import '../core/chinese_lunar.dart';
import '../models/holiday_cn.dart';
import '../models/task.dart';
import '../models/user_settings.dart';
import 'app_theme.dart';
import 'task_colors.dart';

const double _axisWidth = 54;
const double _hourHeight = 80;
const double _quarterHeight = _hourHeight / 4;
const double _blockRadius = 10;
const double _gridPadding = 4;
const int _maxOverlapColumns = 2;
const double _minOverlapColumnWidth = 64;

String? _buildTaskRemindLabel(Task task) {
  final millis = task.remindAt;
  if (millis == null) return null;

  DateTime? dueDate;
  if (task.dueDate.trim().isNotEmpty) {
    try {
      dueDate = DateFormat('yyyy-MM-dd').parse(task.dueDate.trim());
    } catch (_) {
      dueDate = null;
    }
  }

  try {
    final remindAt = DateTime.fromMillisecondsSinceEpoch(millis);
    final isSameDay = dueDate != null &&
        remindAt.year == dueDate.year &&
        remindAt.month == dueDate.month &&
        remindAt.day == dueDate.day;
    return isSameDay
        ? DateFormat('HH:mm').format(remindAt)
        : DateFormat('M/d HH:mm').format(remindAt);
  } catch (_) {
    return millis.toString();
  }
}

String? _buildTaskRepeatLabel(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map) return '重复';
    final freq = decoded['freq']?.toString() ?? '';
    switch (freq) {
      case 'daily':
        return '每天';
      case 'weekly':
        return '每周';
      case 'monthly':
        return '每月';
      case 'yearly':
        return '每年';
      default:
        return '重复';
    }
  } catch (_) {
    return '重复';
  }
}

enum CalendarMode { day, week, month }

class CalendarView extends StatefulWidget {
  const CalendarView({
    super.key,
    required this.tasks,
    required this.loading,
    required this.saving,
    required this.settings,
    required this.timelineDefaultHour,
    required this.initialMode,
    required this.loadHolidayCnYear,
    required this.onCreateTask,
    required this.onRescheduleTask,
    required this.onToggleTask,
    this.onOpenTask,
  });

  final List<Task> tasks;
  final bool loading;
  final bool saving;
  final CalendarSettings settings;
  final int timelineDefaultHour;
  final CalendarMode initialMode;
  final Future<HolidayCnYear> Function(int year) loadHolidayCnYear;
  final Future<Task?> Function({
    required String title,
    required DateTime date,
    TimeOfDay? startTime,
  }) onCreateTask;
  final Future<void> Function(
    Task task, {
    required DateTime date,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
  }) onRescheduleTask;
  final Future<void> Function(Task task) onToggleTask;
  final void Function(Task task)? onOpenTask;

  @override
  State<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<CalendarView> {
  static final DateFormat _dateFormatter = DateFormat('yyyy-MM-dd');
  static const int _weekCompactDayCount = 3;
  static const int _weekCompactInitialPage = 10000;
  static final DateFormat _dayLabelFormatter = DateFormat('M月d日 EEE');
  static final DateFormat _monthLabelFormatter = DateFormat('yyyy年M月');

  late CalendarMode _mode;
  DateTime _focusDate = _stripTime(DateTime.now());

  final ScrollController _timelineScroll = ScrollController();
  final ScrollController _weekHeaderScroll = ScrollController();
  final ScrollController _weekGridScroll = ScrollController();
  late final PageController _weekCompactPageController =
      PageController(initialPage: _weekCompactInitialPage);
  DateTime _weekCompactBaseStart =
      _stripTime(DateTime.now()).subtract(const Duration(days: 1));
  int _weekCompactPage = _weekCompactInitialPage;
  bool _syncingWeekScroll = false;
  bool _didAutoJumpToDefaultTimeline = false;

  final Map<int, Map<String, HolidayCnDay>> _holidayByYear = {};
  final Set<int> _loadingHolidayYears = <int>{};
  final Map<String, List<String>> _monthOrderByDayKey = {};

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _weekHeaderScroll.addListener(() {
      _syncWeekHorizontal(source: _weekHeaderScroll, target: _weekGridScroll);
    });
    _weekGridScroll.addListener(() {
      _syncWeekHorizontal(source: _weekGridScroll, target: _weekHeaderScroll);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _autoJumpToDefaultTimeline();
      _prefetchHolidaysForVisibleRange();
    });
  }

  @override
  void didUpdateWidget(covariant CalendarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.timelineDefaultHour != widget.timelineDefaultHour) {
      _didAutoJumpToDefaultTimeline = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _autoJumpToDefaultTimeline();
      });
    }
  }

  @override
  void dispose() {
    _timelineScroll.dispose();
    _weekHeaderScroll.dispose();
    _weekGridScroll.dispose();
    _weekCompactPageController.dispose();
    super.dispose();
  }

  void _syncWeekHorizontal({
    required ScrollController source,
    required ScrollController target,
  }) {
    if (_syncingWeekScroll) return;
    if (!source.hasClients || !target.hasClients) return;
    final offset = source.offset;
    final current = target.offset;
    if ((current - offset).abs() < 0.5) return;
    final max = target.position.maxScrollExtent;
    _syncingWeekScroll = true;
    target.jumpTo(offset.clamp(0.0, max));
    _syncingWeekScroll = false;
  }

  bool _isCompactWeek(double width) => width < 720;

  DateTime _weekCompactStartForPage(int page) {
    final delta = page - _weekCompactInitialPage;
    return _weekCompactBaseStart
        .add(Duration(days: delta * _weekCompactDayCount));
  }

  void _resetWeekCompactPager(DateTime center) {
    _weekCompactBaseStart =
        _stripTime(center).subtract(const Duration(days: 1));
    _weekCompactPage = _weekCompactInitialPage;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_weekCompactPageController.hasClients) return;
      _weekCompactPageController.jumpToPage(_weekCompactInitialPage);
    });
  }

  String _compactRangeLabel(DateTime center) {
    final start = _stripTime(center).subtract(const Duration(days: 1));
    final end = start.add(const Duration(days: 2));
    final fmt = DateFormat('M/d');
    return '${fmt.format(start)}–${fmt.format(end)}';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildControls(context),
        const SizedBox(height: 12),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: switch (_mode) {
              CalendarMode.day => _buildDayView(context, _focusDate),
              CalendarMode.week => _buildWeekView(context, _focusDate),
              CalendarMode.month => _buildMonthView(context, _focusDate),
            },
          ),
        ),
      ],
    );
  }

  Widget _buildControls(BuildContext context) {
    final isSelected = <bool>[
      _mode == CalendarMode.day,
      _mode == CalendarMode.week,
      _mode == CalendarMode.month,
    ];

    void setMode(CalendarMode mode) {
      final today = _stripTime(DateTime.now());
      setState(() {
        _mode = mode;
        if (mode == CalendarMode.week) {
          _focusDate = today;
        }
        _prefetchHolidaysForVisibleRange();
      });
      if (mode == CalendarMode.week) {
        _resetWeekCompactPager(today);
      }
      if ((mode == CalendarMode.day || mode == CalendarMode.week) &&
          !_didAutoJumpToDefaultTimeline) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _autoJumpToDefaultTimeline();
        });
      }
    }

    void goToday() {
      final today = _stripTime(DateTime.now());
      setState(() {
        _focusDate = today;
        _prefetchHolidaysForVisibleRange();
      });
      if (_mode == CalendarMode.week) {
        _resetWeekCompactPager(today);
      }
    }

    final modeToggle = ToggleButtons(
      isSelected: isSelected,
      onPressed:
          widget.saving ? null : (index) => setMode(CalendarMode.values[index]),
      borderRadius: BorderRadius.circular(12),
      constraints: const BoxConstraints(minHeight: 40, minWidth: 44),
      children: const [
        Text('日'),
        Text('周'),
        Text('月'),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compactWeek =
            _mode == CalendarMode.week && _isCompactWeek(constraints.maxWidth);
        final rangeLabel = switch (_mode) {
          CalendarMode.day => _dayLabelFormatter.format(_focusDate),
          CalendarMode.week => compactWeek
              ? _compactRangeLabel(_focusDate)
              : _weekLabel(_focusDate),
          CalendarMode.month => _monthLabelFormatter.format(_focusDate),
        };

        void moveCompactWeekPage(int delta) {
          if (!_weekCompactPageController.hasClients) return;
          final next = (_weekCompactPage + delta).clamp(0, 999999);
          _weekCompactPageController.animateToPage(
            next,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          );
        }

        final navRow = Row(
          children: [
            IconButton(
              onPressed: widget.saving
                  ? null
                  : () {
                      if (compactWeek) {
                        moveCompactWeekPage(-1);
                        return;
                      }
                      _goPrev();
                    },
              icon: const Icon(Icons.chevron_left),
              tooltip: '上一页',
            ),
            Expanded(
              child: Text(
                rangeLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              onPressed: widget.saving
                  ? null
                  : () {
                      if (compactWeek) {
                        moveCompactWeekPage(1);
                        return;
                      }
                      _goNext();
                    },
              icon: const Icon(Icons.chevron_right),
              tooltip: '下一页',
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: widget.saving ? null : goToday,
              child: const Text('今天'),
            ),
          ],
        );

        final isNarrow = constraints.maxWidth < 520;
        if (!isNarrow) {
          return Row(
            children: [
              modeToggle,
              const SizedBox(width: 12),
              Expanded(child: navRow),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            modeToggle,
            const SizedBox(height: 8),
            navRow,
          ],
        );
      },
    );
  }

  Widget _buildDayView(BuildContext context, DateTime date) {
    final tasks = _tasksForDate(date);
    final allDay =
        tasks.where((t) => _parseTimeToMinutes(t.startTime) == null).toList();
    final timed =
        tasks.where((t) => _parseTimeToMinutes(t.startTime) != null).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DaySummaryHeader(
          date: date,
          lunarLabel: ChineseLunar.format(date),
          holiday: _holidayFor(date),
        ),
        const SizedBox(height: 10),
        _AllDayLane(
          date: date,
          tasks: allDay,
          holiday: _holidayFor(date),
          onCreate: widget.saving ? null : () => _promptCreateTask(date, null),
          onReschedule: widget.saving ? null : _rescheduleTask,
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _TimelineView(
            scrollController: _timelineScroll,
            dayCount: 1,
            dayWidth: null,
            dayForIndex: (_) => date,
            tasks: timed,
            showTaskStartTime: widget.settings.taskBlockShowStartTimeDay,
            showTaskTags: widget.settings.taskBlockShowTagsDay,
            onTapSlot:
                widget.saving ? null : (d, time) => _promptCreateTask(d, time),
            onDropTask: widget.saving ? null : _rescheduleTask,
            onResizeTask: widget.saving ? null : _rescheduleTaskRange,
            onToggleTask: widget.saving ? null : widget.onToggleTask,
            onOpenTask: widget.onOpenTask,
          ),
        ),
      ],
    );
  }

  Widget _buildWeekView(BuildContext context, DateTime focus) {
    final timedTasks = widget.tasks
        .where((task) =>
            task.deletedAt == null &&
            _parseTimeToMinutes(task.startTime) != null)
        .toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = _isCompactWeek(constraints.maxWidth);
        if (isCompact) {
          final start = _weekCompactStartForPage(_weekCompactPage);
          final days =
              List.generate(_weekCompactDayCount, (i) => start.add(Duration(days: i)));
          final availableWidth = (constraints.maxWidth - _axisWidth)
              .clamp(0.0, double.infinity)
              .toDouble();
          final dayWidth =
              (availableWidth / _weekCompactDayCount).clamp(0.0, availableWidth).toDouble();
          final gridHeight = _hourHeight * 24;

          void handlePageSwipe(DragEndDetails details) {
            if (!_weekCompactPageController.hasClients) return;
            final velocity = details.primaryVelocity ?? 0;
            if (velocity.abs() < 250) return;
            if (velocity < 0) {
              _weekCompactPageController.nextPage(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
              );
              return;
            }
            _weekCompactPageController.previousPage(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
            );
          }

          Widget buildHeader() {
            return GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragEnd: handlePageSwipe,
              child: Row(
                children: [
                  const SizedBox(width: _axisWidth),
                  for (final day in days)
                    SizedBox(
                      width: dayWidth,
                      child: _WeekDayHeader(
                        date: day,
                        lunarLabel: ChineseLunar.format(day),
                        holiday: _holidayFor(day),
                        onTap: widget.saving
                            ? null
                            : () {
                                setState(() {
                                  _focusDate = day;
                                  _mode = CalendarMode.day;
                                  _prefetchHolidaysForVisibleRange();
                                });
                                if (!_didAutoJumpToDefaultTimeline) {
                                  WidgetsBinding.instance
                                      .addPostFrameCallback((_) {
                                    if (!mounted) return;
                                    _autoJumpToDefaultTimeline();
                                  });
                                }
                              },
                      ),
                    ),
                ],
              ),
            );
          }

          Widget buildAllDayRow() {
            return GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragEnd: handlePageSwipe,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(width: _axisWidth),
                  for (final day in days)
                    SizedBox(
                      width: dayWidth,
                      child: _AllDayCell(
                        date: day,
                        tasks: _tasksForDate(day)
                            .where(
                                (t) => _parseTimeToMinutes(t.startTime) == null)
                            .toList(),
                        onCreate: widget.saving
                            ? null
                            : () => _promptCreateTask(day, null),
                        onReschedule: widget.saving ? null : _rescheduleTask,
                      ),
                    ),
                ],
              ),
            );
          }

          final timeline = Expanded(
            child: SingleChildScrollView(
              controller: _timelineScroll,
              child: SizedBox(
                height: gridHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: _axisWidth,
                      height: gridHeight,
                      child: const _TimeAxisColumn(),
                    ),
                    Expanded(
                      child: SizedBox(
                        height: gridHeight,
                        child: PageView.builder(
                          controller: _weekCompactPageController,
                          onPageChanged: (page) {
                            final pageStart = _weekCompactStartForPage(page);
                            final center =
                                pageStart.add(const Duration(days: 1));
                            setState(() {
                              _weekCompactPage = page;
                              _focusDate = _stripTime(center);
                              _prefetchHolidaysForVisibleRange();
                            });
                          },
                          itemBuilder: (context, pageIndex) {
                            final pageStart =
                                _weekCompactStartForPage(pageIndex);
                            final pageDays = List.generate(_weekCompactDayCount,
                                (i) => pageStart.add(Duration(days: i)));

                            return SizedBox(
                              width: availableWidth,
                              height: gridHeight,
                              child: _TimeGrid(
                                dayCount: _weekCompactDayCount,
                                dayWidth: dayWidth,
                                dayForIndex: (i) => pageDays[i],
                                tasks: timedTasks,
                                showTaskStartTime:
                                    widget.settings.taskBlockShowStartTimeWeek,
                                showTaskTags:
                                    widget.settings.taskBlockShowTagsWeek,
                                onTapSlot: widget.saving
                                    ? null
                                    : (d, time) => _promptCreateTask(d, time),
                                onDropTask:
                                    widget.saving ? null : _rescheduleTask,
                                onResizeTask:
                                    widget.saving ? null : _rescheduleTaskRange,
                                onToggleTask:
                                    widget.saving ? null : widget.onToggleTask,
                                onOpenTask: widget.onOpenTask,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              buildHeader(),
              const SizedBox(height: 10),
              buildAllDayRow(),
              const SizedBox(height: 10),
              timeline,
            ],
          );
        }

        final start = _weekStart(focus);
        final days = List.generate(7, (i) => start.add(Duration(days: i)));
        final computedWidth = (constraints.maxWidth - _axisWidth)
                .clamp(0.0, double.infinity) /
            7.0;
        final dayWidth = computedWidth.isFinite && computedWidth > 0
            ? computedWidth
            : 1.0;
        final stripWidth = dayWidth * days.length;

        final headerStrip = Row(
          children: [
            const SizedBox(width: _axisWidth),
            Expanded(
              child: SingleChildScrollView(
                controller: _weekHeaderScroll,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: stripWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          for (final day in days)
                            SizedBox(
                              width: dayWidth,
                              child: _WeekDayHeader(
                                date: day,
                                lunarLabel: ChineseLunar.format(day),
                                holiday: _holidayFor(day),
                                onTap: widget.saving
                                    ? null
                                    : () {
                                        setState(() {
                                          _focusDate = day;
                                          _mode = CalendarMode.day;
                                          _prefetchHolidaysForVisibleRange();
                                        });
                                        if (!_didAutoJumpToDefaultTimeline) {
                                          WidgetsBinding.instance
                                              .addPostFrameCallback((_) {
                                            if (!mounted) return;
                                            _autoJumpToDefaultTimeline();
                                          });
                                        }
                                      },
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final day in days)
                            SizedBox(
                              width: dayWidth,
                              child: _AllDayCell(
                                date: day,
                                tasks: _tasksForDate(day)
                                    .where((t) =>
                                        _parseTimeToMinutes(t.startTime) ==
                                        null)
                                    .toList(),
                                onCreate: widget.saving
                                    ? null
                                    : () => _promptCreateTask(day, null),
                                onReschedule:
                                    widget.saving ? null : _rescheduleTask,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            headerStrip,
            const SizedBox(height: 10),
            Expanded(
              child: _TimelineView(
                scrollController: _timelineScroll,
                horizontalController: _weekGridScroll,
                dayCount: 7,
                dayWidth: dayWidth,
                dayForIndex: (i) => days[i],
                tasks: timedTasks,
                showTaskStartTime: widget.settings.taskBlockShowStartTimeWeek,
                showTaskTags: widget.settings.taskBlockShowTagsWeek,
                onTapSlot: widget.saving
                    ? null
                    : (d, time) => _promptCreateTask(d, time),
                onDropTask: widget.saving ? null : _rescheduleTask,
                onResizeTask: widget.saving ? null : _rescheduleTaskRange,
                onToggleTask: widget.saving ? null : widget.onToggleTask,
                onOpenTask: widget.onOpenTask,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMonthView(BuildContext context, DateTime focus) {
    final firstOfMonth = DateTime(focus.year, focus.month, 1);
    final lastOfMonth = DateTime(focus.year, focus.month + 1, 0);
    final gridStart = _weekStart(firstOfMonth);
    final weekRowCount =
        (_weekStart(lastOfMonth).difference(gridStart).inDays ~/ 7) + 1;
    final days = List.generate(
        weekRowCount * 7, (i) => gridStart.add(Duration(days: i)));

    final tasksByDayKey = <String, List<Task>>{};
    for (final date in days) {
      tasksByDayKey[_dateFormatter.format(date)] = _tasksForDate(date);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const headerHeight = 20.0;
        const headerGap = 0.0;
        const mainSpacing = 0.0;
        const crossSpacing = 0.0;
        final rowCount = weekRowCount;

        final gridHeight = (constraints.maxHeight - headerHeight - headerGap)
            .clamp(0.0, double.infinity);
        final cellWidth = (constraints.maxWidth - crossSpacing * 6)
                .clamp(0.0, double.infinity) /
            7.0;
        final cellHeight = (gridHeight - mainSpacing * (rowCount - 1))
                .clamp(1.0, double.infinity) /
            rowCount;
        final ratio = cellWidth <= 0 ? 1.25 : (cellWidth / cellHeight);

        return Column(
          children: [
            SizedBox(
              height: headerHeight,
              child: Row(
                children: const [
                  Expanded(child: Center(child: Text('一'))),
                  Expanded(child: Center(child: Text('二'))),
                  Expanded(child: Center(child: Text('三'))),
                  Expanded(child: Center(child: Text('四'))),
                  Expanded(child: Center(child: Text('五'))),
                  Expanded(child: Center(child: Text('六'))),
                  Expanded(child: Center(child: Text('日'))),
                ],
              ),
            ),
            const SizedBox(height: headerGap),
            Expanded(
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                primary: false,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisSpacing: mainSpacing,
                  crossAxisSpacing: crossSpacing,
                  childAspectRatio: ratio.isFinite && ratio > 0 ? ratio : 1.25,
                ),
                itemCount: days.length,
                itemBuilder: (context, index) {
                  final date = days[index];
                  final isInMonth = date.month == focus.month;
                  final key = _dateFormatter.format(date);
                  final orderedTasks =
                      _sortedMonthTasks(key, tasksByDayKey[key] ?? const []);
                  return _MonthDayCell(
                    dayKey: key,
                    date: date,
                    inMonth: isInMonth,
                    selected: _isSameDay(date, _focusDate),
                    lunarLabel: ChineseLunar.format(date),
                    holiday: _holidayFor(date),
                    tasks: orderedTasks,
                    showTaskStartTime:
                        widget.settings.taskBlockShowStartTimeMonth,
                    showTaskTags: widget.settings.taskBlockShowTagsMonth,
                    onTap: widget.saving
                        ? null
                        : () {
                            setState(() {
                              _focusDate = date;
                              _mode = CalendarMode.day;
                              _prefetchHolidaysForVisibleRange();
                            });
                            if (!_didAutoJumpToDefaultTimeline) {
                              WidgetsBinding.instance
                                  .addPostFrameCallback((_) {
                                if (!mounted) return;
                                _autoJumpToDefaultTimeline();
                              });
                            }
                          },
                    onDrop: widget.saving
                        ? null
                        : (task) => _rescheduleTask(task, date, null),
                    onToggleTask: widget.saving ? null : widget.onToggleTask,
                    onReorderTasks: widget.saving ? null : _setMonthDayOrder,
                    onOpenTask: widget.onOpenTask,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _promptCreateTask(DateTime date, TimeOfDay? time) async {
    final label = time == null ? '全天' : time.format(context);
    String draft = '';
    final title = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) {
          void submit() {
            final trimmed = draft.trim();
            if (trimmed.isEmpty) return;
            Navigator.of(dialogContext).pop(trimmed);
          }

          return AlertDialog(
            title: Text('添加任务 · $label'),
            content: TextField(
              autofocus: true,
              decoration: InputDecoration(
                hintText: '任务标题',
                helperText: '必填',
                errorText: draft.isNotEmpty && draft.trim().isEmpty
                    ? '请输入任务标题'
                    : null,
              ),
              onChanged: (value) => setState(() => draft = value),
              onSubmitted: (_) => submit(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: draft.trim().isEmpty ? null : submit,
                child: const Text('添加'),
              ),
            ],
          );
        },
      ),
    );
    if (!mounted) return;
    if (title == null) return;
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await widget.onCreateTask(title: trimmed, date: date, startTime: time);
  }

  Future<void> _rescheduleTask(
      Task task, DateTime date, TimeOfDay? time) async {
    await widget.onRescheduleTask(task, date: date, startTime: time);
  }

  Future<void> _rescheduleTaskRange(
    Task task,
    DateTime date,
    TimeOfDay startTime,
    TimeOfDay endTime,
  ) async {
    await widget.onRescheduleTask(
      task,
      date: date,
      startTime: startTime,
      endTime: endTime,
    );
  }

  void _goPrev() {
    setState(() {
      _focusDate = switch (_mode) {
        CalendarMode.day => _focusDate.subtract(const Duration(days: 1)),
        CalendarMode.week => _focusDate.subtract(const Duration(days: 7)),
        CalendarMode.month =>
          DateTime(_focusDate.year, _focusDate.month - 1, 1),
      };
      _prefetchHolidaysForVisibleRange();
    });
  }

  void _goNext() {
    setState(() {
      _focusDate = switch (_mode) {
        CalendarMode.day => _focusDate.add(const Duration(days: 1)),
        CalendarMode.week => _focusDate.add(const Duration(days: 7)),
        CalendarMode.month =>
          DateTime(_focusDate.year, _focusDate.month + 1, 1),
      };
      _prefetchHolidaysForVisibleRange();
    });
  }

  void _jumpToHour(int hour) {
    final target = hour.clamp(0, 23) * _hourHeight;
    if (_timelineScroll.hasClients) {
      _timelineScroll
          .jumpTo(target.clamp(0, _timelineScroll.position.maxScrollExtent));
    }
  }

  void _autoJumpToDefaultTimeline() {
    if (_didAutoJumpToDefaultTimeline) return;
    if (_mode == CalendarMode.month) return;
    if (!_timelineScroll.hasClients) return;
    _jumpToHour(widget.timelineDefaultHour);
    _didAutoJumpToDefaultTimeline = true;
  }

  List<Task> _tasksForDate(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    final key = _dateFormatter.format(day);
    final result = <Task>[];
    for (final task in widget.tasks) {
      if (task.deletedAt != null) continue;
      final startDay = _tryParseDayKey(task.dueDate.trim());
      if (startDay == null) continue;
      final startDayKey = _dateFormatter.format(startDay);

      final startMinutes = _parseTimeToMinutes(task.startTime);
      if (startMinutes == null) {
        final endDayParsed = _tryParseDayKey(task.endDate.trim()) ?? startDay;
        final endDay = endDayParsed.isBefore(startDay) ? startDay : endDayParsed;
        if (!day.isBefore(startDay) && !day.isAfter(endDay)) {
          result.add(task);
        }
        continue;
      }

      if (startDayKey == key) {
        result.add(task);
        continue;
      }

      final rawEnd = task.endTime.trim();
      if (rawEnd.isEmpty) continue;
      var endMinutesOfDay = _parseTimeToMinutes(rawEnd);
      if (endMinutesOfDay == null) continue;
      var extraOffsetDays = 0;
      if (endMinutesOfDay == 24 * 60) {
        endMinutesOfDay = 0;
        extraOffsetDays = 1;
      }

      int offsetDays = 0;
      final endDateKey = task.endDate.trim();
      if (endDateKey.isNotEmpty) {
        final parsedEndDay = _tryParseDayKey(endDateKey);
        if (parsedEndDay != null) {
          offsetDays = parsedEndDay.difference(startDay).inDays;
        }
      } else {
        offsetDays = _parseOffsetDays(rawEnd);
      }
      if (offsetDays < 0) offsetDays = 0;
      offsetDays += extraOffsetDays;
      if (offsetDays == 0 && endMinutesOfDay <= startMinutes) {
        offsetDays = 1;
      }
      if (offsetDays <= 0) continue;

      final endDay = startDay.add(Duration(days: offsetDays));
      final isEndDay = day.year == endDay.year &&
          day.month == endDay.month &&
          day.day == endDay.day;
      final overlaps = day.isAfter(startDay) &&
          (day.isBefore(endDay) || (isEndDay && endMinutesOfDay > 0));
      if (overlaps) {
        result.add(task);
      }
    }
    return result;
  }

  int _monthTaskSort(Task a, Task b) {
    if (a.isCompleted != b.isCompleted) {
      return a.isCompleted ? 1 : -1;
    }
    final aStart = _parseTimeToMinutes(a.startTime) ?? -1;
    final bStart = _parseTimeToMinutes(b.startTime) ?? -1;
    final compare = aStart.compareTo(bStart);
    if (compare != 0) return compare;
    if (a.isCompleted) {
      return a.updatedAt.compareTo(b.updatedAt);
    }
    return b.updatedAt.compareTo(a.updatedAt);
  }

  List<Task> _sortedMonthTasks(String dayKey, List<Task> tasks) {
    final defaultSorted = List<Task>.from(tasks)..sort(_monthTaskSort);
    final manual = _monthOrderByDayKey[dayKey];
    if (manual == null || manual.isEmpty) return defaultSorted;

    final taskById = <String, Task>{
      for (final task in defaultSorted) task.id: task
    };
    final ordered = <Task>[];
    for (final id in manual) {
      final task = taskById.remove(id);
      if (task != null) ordered.add(task);
    }
    for (final task in defaultSorted) {
      final remaining = taskById.remove(task.id);
      if (remaining != null) ordered.add(remaining);
    }
    final pending = <Task>[];
    final completed = <Task>[];
    for (final task in ordered) {
      (task.isCompleted ? completed : pending).add(task);
    }
    return [...pending, ...completed];
  }

  void _setMonthDayOrder(String dayKey, List<String> orderedTaskIds) {
    setState(() => _monthOrderByDayKey[dayKey] = orderedTaskIds);
  }

  HolidayCnDay? _holidayFor(DateTime date) {
    final map = _holidayByYear[date.year];
    if (map == null) return null;
    return map[_dateFormatter.format(date)];
  }

  void _prefetchHolidaysForVisibleRange() {
    final years = <int>{};
    switch (_mode) {
      case CalendarMode.day:
        years.add(_focusDate.year);
        break;
      case CalendarMode.week:
        final start = _weekStart(_focusDate);
        final end = start.add(const Duration(days: 6));
        years.add(start.year);
        years.add(end.year);
        break;
      case CalendarMode.month:
        final first = DateTime(_focusDate.year, _focusDate.month, 1);
        final start = _weekStart(first);
        final end = start.add(const Duration(days: 41));
        years.add(start.year);
        years.add(end.year);
        break;
    }

    for (final year in years) {
      if (_holidayByYear.containsKey(year) ||
          _loadingHolidayYears.contains(year)) continue;
      _loadingHolidayYears.add(year);
      widget.loadHolidayCnYear(year).then((value) {
        if (!mounted) return;
        setState(() {
          _holidayByYear[year] = value.byDate;
          _loadingHolidayYears.remove(year);
        });
      }).catchError((_) {
        if (!mounted) return;
        setState(() => _loadingHolidayYears.remove(year));
      });
    }
  }

  String _weekLabel(DateTime date) {
    final start = _weekStart(date);
    final end = start.add(const Duration(days: 6));
    final fmt = DateFormat('M月d日');
    return '${fmt.format(start)} - ${fmt.format(end)}';
  }
}

class _DaySummaryHeader extends StatelessWidget {
  const _DaySummaryHeader({
    required this.date,
    required this.lunarLabel,
    required this.holiday,
  });

  final DateTime date;
  final String lunarLabel;
  final HolidayCnDay? holiday;

  @override
  Widget build(BuildContext context) {
    final title = DateFormat('yyyy年M月d日 EEEE').format(date);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85),
        border: Border.all(color: AppColors.outline),
      ),
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
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  lunarLabel,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
          if (holiday != null) _HolidayBadge(day: holiday!),
        ],
      ),
    );
  }
}

class _WeekDayHeader extends StatelessWidget {
  const _WeekDayHeader({
    required this.date,
    required this.lunarLabel,
    required this.holiday,
    required this.onTap,
  });

  final DateTime date;
  final String lunarLabel;
  final HolidayCnDay? holiday;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final label = DateFormat('E\nM/d').format(date);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.85),
          border: Border.all(color: AppColors.outline),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  lunarLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: AppColors.inkSoft),
                ),
              ],
            ),
            if (holiday != null)
              Positioned(top: 0, right: 0, child: _HolidayBadge(day: holiday!)),
          ],
        ),
      ),
    );
  }
}

class _HolidayBadge extends StatelessWidget {
  const _HolidayBadge({required this.day, this.dense = false});

  final HolidayCnDay day;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final isOff = day.isOffDay;
    final bg = (isOff ? Colors.green : Colors.red).withOpacity(0.15);
    final fg = isOff ? Colors.green.shade800 : Colors.red.shade800;
    final label = isOff ? '休' : '班';
    return Tooltip(
      message: day.name,
      child: Container(
        padding: dense
            ? const EdgeInsets.symmetric(horizontal: 6, vertical: 2)
            : const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: fg.withOpacity(0.5)),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: fg,
                fontWeight: FontWeight.w800,
                fontSize: dense ? 10 : null,
                height: dense ? 1.0 : null,
              ),
        ),
      ),
    );
  }
}

class _AllDayLane extends StatelessWidget {
  const _AllDayLane({
    required this.date,
    required this.tasks,
    required this.holiday,
    required this.onCreate,
    required this.onReschedule,
  });

  final DateTime date;
  final List<Task> tasks;
  final HolidayCnDay? holiday;
  final VoidCallback? onCreate;
  final void Function(Task task, DateTime date, TimeOfDay? time)? onReschedule;

  @override
  Widget build(BuildContext context) {
    return DragTarget<_TaskDragPayload>(
      onWillAcceptWithDetails: (details) => onReschedule != null,
      onAcceptWithDetails: (details) =>
          onReschedule?.call(details.data.task, date, null),
      builder: (context, _, __) {
        return InkWell(
          onTap: onCreate,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.85),
              border: Border.all(color: AppColors.outline),
            ),
            child: Row(
              children: [
                Text(
                  '全天',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.inkSoft,
                      ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final task in tasks.take(8)) _AllDayChip(task: task),
                      if (tasks.length > 8)
                        Text(
                          '+${tasks.length - 8}',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: AppColors.inkSoft),
                        ),
                    ],
                  ),
                ),
                if (holiday != null) _HolidayBadge(day: holiday!),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AllDayCell extends StatelessWidget {
  const _AllDayCell({
    required this.date,
    required this.tasks,
    required this.onCreate,
    required this.onReschedule,
  });

  final DateTime date;
  final List<Task> tasks;
  final VoidCallback? onCreate;
  final void Function(Task task, DateTime date, TimeOfDay? time)? onReschedule;

  @override
  Widget build(BuildContext context) {
    return DragTarget<_TaskDragPayload>(
      onWillAcceptWithDetails: (details) => onReschedule != null,
      onAcceptWithDetails: (details) =>
          onReschedule?.call(details.data.task, date, null),
      builder: (context, _, __) {
        return InkWell(
          onTap: onCreate,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.85),
              border: Border.all(color: AppColors.outline),
            ),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final task in tasks.take(3)) _AllDayChip(task: task),
                if (tasks.length > 3)
                  Text(
                    '+${tasks.length - 3}',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: AppColors.inkSoft),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AllDayChip extends StatelessWidget {
  const _AllDayChip({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context) {
    final bg = TaskColors.resolveBackground(task.id, task.colorHex);
    return Draggable<_TaskDragPayload>(
      data: _TaskDragPayload(task),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(
          opacity: 0.95,
          child: SizedBox(width: 240, child: _chip(context, bg)),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: _chip(context, bg)),
      child: _chip(context, bg),
    );
  }

  Widget _chip(BuildContext context, Color? bg) {
    final title = task.title.trim().isEmpty ? '未命名任务' : task.title.trim();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg ?? Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: (bg ?? AppColors.outline).withOpacity(0.6)),
      ),
      child: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: task.isCompleted ? AppColors.inkSoft : AppColors.ink,
            ),
      ),
    );
  }
}

class _TaskDragPayload {
  const _TaskDragPayload(this.task);

  final Task task;
}

class _TimelineView extends StatefulWidget {
  const _TimelineView({
    required this.scrollController,
    required this.dayCount,
    required this.dayWidth,
    required this.dayForIndex,
    required this.tasks,
    required this.showTaskStartTime,
    required this.showTaskTags,
    required this.onTapSlot,
    required this.onDropTask,
    this.horizontalController,
    this.onResizeTask,
    this.onToggleTask,
    this.onOpenTask,
  });

  final ScrollController scrollController;
  final ScrollController? horizontalController;
  final int dayCount;
  final double? dayWidth;
  final DateTime Function(int index) dayForIndex;
  final List<Task> tasks;
  final bool showTaskStartTime;
  final bool showTaskTags;
  final void Function(DateTime date, TimeOfDay time)? onTapSlot;
  final void Function(Task task, DateTime date, TimeOfDay time)? onDropTask;
  final Future<void> Function(
          Task task, DateTime date, TimeOfDay startTime, TimeOfDay endTime)?
      onResizeTask;
  final Future<void> Function(Task task)? onToggleTask;
  final void Function(Task task)? onOpenTask;

  @override
  State<_TimelineView> createState() => _TimelineViewState();
}

class _TimelineViewState extends State<_TimelineView> {
  final ScrollController _internalHorizontal = ScrollController();

  ScrollController get _horizontal =>
      widget.horizontalController ?? _internalHorizontal;

  @override
  void dispose() {
    _internalHorizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = (constraints.maxWidth - _axisWidth)
            .clamp(0.0, double.infinity)
            .toDouble();
        final effectiveDayWidth =
            widget.dayWidth ?? (availableWidth / widget.dayCount);
        final gridWidth = effectiveDayWidth * widget.dayCount;
        final gridHeight = _hourHeight * 24;

        final needsHorizontalScroll = gridWidth > availableWidth + 0.5;
        final grid = SizedBox(
          width: gridWidth,
          height: gridHeight,
          child: _TimeGrid(
            dayCount: widget.dayCount,
            dayWidth: effectiveDayWidth,
            dayForIndex: widget.dayForIndex,
            tasks: widget.tasks,
            showTaskStartTime: widget.showTaskStartTime,
            showTaskTags: widget.showTaskTags,
            onTapSlot: widget.onTapSlot,
            onDropTask: widget.onDropTask,
            onResizeTask: widget.onResizeTask,
            onToggleTask: widget.onToggleTask,
            onOpenTask: widget.onOpenTask,
          ),
        );

        final scrollableGrid = needsHorizontalScroll
            ? SingleChildScrollView(
                controller: _horizontal,
                scrollDirection: Axis.horizontal,
                child: grid,
              )
            : grid;

        final content = SizedBox(
          height: gridHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: _axisWidth,
                height: gridHeight,
                child: const _TimeAxisColumn(),
              ),
              Expanded(
                child: SizedBox(
                  height: gridHeight,
                  child: scrollableGrid,
                ),
              ),
            ],
          ),
        );

        return SingleChildScrollView(
          controller: widget.scrollController,
          child: content,
        );
      },
    );
  }
}

class _TimeAxisColumn extends StatelessWidget {
  const _TimeAxisColumn();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var hour = 0; hour < 24; hour++)
          SizedBox(
            height: _hourHeight,
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '${hour.toString().padLeft(2, '0')}:00',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.inkSoft,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SlotHit {
  const _SlotHit({required this.date, required this.time});

  final DateTime date;
  final TimeOfDay time;
}

class _TimeGrid extends StatefulWidget {
  const _TimeGrid({
    required this.dayCount,
    required this.dayWidth,
    required this.dayForIndex,
    required this.tasks,
    required this.showTaskStartTime,
    required this.showTaskTags,
    required this.onTapSlot,
    required this.onDropTask,
    required this.onResizeTask,
    this.onToggleTask,
    this.onOpenTask,
  });

  final int dayCount;
  final double dayWidth;
  final DateTime Function(int index) dayForIndex;
  final List<Task> tasks;
  final bool showTaskStartTime;
  final bool showTaskTags;
  final void Function(DateTime date, TimeOfDay time)? onTapSlot;
  final void Function(Task task, DateTime date, TimeOfDay time)? onDropTask;
  final Future<void> Function(
          Task task, DateTime date, TimeOfDay startTime, TimeOfDay endTime)?
      onResizeTask;
  final Future<void> Function(Task task)? onToggleTask;
  final void Function(Task task)? onOpenTask;

  @override
  State<_TimeGrid> createState() => _TimeGridState();
}

class _TimeGridState extends State<_TimeGrid> {
  final Map<String, _TimeRangeOverride> _overrides =
      <String, _TimeRangeOverride>{};

  String _formatMinutes(int minutes) {
    minutes = minutes.clamp(0, 24 * 60);
    final hour = minutes ~/ 60;
    final minute = minutes % 60;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  void _openOverlappingTasksSheet(
    DateTime date,
    int startMinutes,
    int endMinutes,
    List<Task> tasks,
  ) {
    if (tasks.isEmpty) return;
    final sheetTasks = List<Task>.from(tasks);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final maxHeight = MediaQuery.of(sheetContext).size.height * 0.75;
        final title = DateFormat('yyyy-MM-dd').format(date);
        final rangeLabel =
            '${_formatMinutes(startMinutes)}-${_formatMinutes(endMinutes)}';

        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            Future<void> handleToggle(Task task) async {
              final idx = sheetTasks.indexWhere((t) => t.id == task.id);
              if (idx < 0) return;
              final current = sheetTasks[idx];
              setSheetState(() {
                sheetTasks[idx] = current.copyWith(
                  status: current.isCompleted ? 'todo' : 'completed',
                );
              });
              if (widget.onToggleTask != null) {
                await widget.onToggleTask!(current);
              }
            }

            return SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxHeight),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$title  $rangeLabel  (${sheetTasks.length})',
                        style: Theme.of(sheetContext)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView.builder(
                          itemCount: sheetTasks.length,
                          itemBuilder: (context, index) {
                            final task = sheetTasks[index];
                            return _MonthTaskTile(
                              key: ValueKey(task.id),
                              task: task,
                              showStartTime: widget.showTaskStartTime,
                              showTags: widget.showTaskTags,
                              onTap: widget.onOpenTask == null
                                  ? null
                                  : () {
                                      Navigator.of(sheetContext).pop();
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                        widget.onOpenTask?.call(task);
                                      });
                                    },
                              onToggle: widget.onToggleTask == null
                                  ? null
                                  : () => handleToggle(task),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  void didUpdateWidget(covariant _TimeGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_overrides.isEmpty) return;
    final ids = widget.tasks.map((task) => task.id).toSet();
    _overrides.removeWhere((id, _) => !ids.contains(id));
  }

  void _previewTaskRange(String taskId, int startMinutes, int endMinutes) {
    setState(() {
      _overrides[taskId] = _TimeRangeOverride(
          startMinutes: startMinutes, endMinutes: endMinutes);
    });
  }

  Future<void> _commitTaskRange(
      Task task, DateTime date, int startMinutes, int endMinutes) async {
    final callback = widget.onResizeTask;
    if (callback == null) {
      if (!mounted) return;
      setState(() => _overrides.remove(task.id));
      return;
    }

    final start =
        TimeOfDay(hour: startMinutes ~/ 60, minute: startMinutes % 60);
    final endMinuteOfDay = endMinutes % (24 * 60);
    final end =
        TimeOfDay(hour: endMinuteOfDay ~/ 60, minute: endMinuteOfDay % 60);
    await callback(task, date, start, end);
    if (!mounted) return;
    setState(() => _overrides.remove(task.id));
  }

  @override
  Widget build(BuildContext context) {
    final dateIndexByKey = <String, int>{
      for (var i = 0; i < widget.dayCount; i++)
        _CalendarViewState._dateFormatter.format(widget.dayForIndex(i)): i,
    };

    final eventsByDay =
        List.generate(widget.dayCount, (_) => <_TimelineEvent>[]);
    for (final task in widget.tasks) {
      final override = _overrides[task.id];
      final startMinutes =
          override?.startMinutes ?? _parseTimeToMinutes(task.startTime);
      if (startMinutes == null || startMinutes >= 24 * 60) continue;

      final dueKey = task.dueDate.trim();
      final rawEnd = task.endTime.trim();
      final hasEndTime = rawEnd.isNotEmpty;
      final endDateKey = task.endDate.trim();
      final startDate = _tryParseDayKey(dueKey);
      if (startDate == null) continue;

      var endMinutesOfDay = _parseTimeToMinutes(rawEnd);
      var extraOffsetDays = 0;
      if (endMinutesOfDay != null && endMinutesOfDay == 24 * 60) {
        endMinutesOfDay = 0;
        extraOffsetDays = 1;
      }

      int offsetDays = 0;
      if (hasEndTime) {
        if (endDateKey.isNotEmpty) {
          final parsedEndDay = _tryParseDayKey(endDateKey);
          if (parsedEndDay != null) {
            offsetDays = parsedEndDay.difference(startDate).inDays;
          } else {
            offsetDays = _parseOffsetDays(rawEnd);
          }
        } else {
          offsetDays = _parseOffsetDays(rawEnd);
        }
        offsetDays = offsetDays < 0 ? 0 : offsetDays;
        offsetDays += extraOffsetDays;
      }

      final impliedCrossDay = hasEndTime &&
          offsetDays == 0 &&
          endMinutesOfDay != null &&
          endMinutesOfDay <= startMinutes;
      final effectiveOffsetDays = hasEndTime
          ? (offsetDays > 0 ? offsetDays : (impliedCrossDay ? 1 : 0))
          : 0;
      final crossesDay = override == null && effectiveOffsetDays > 0;
      final allowResize = !crossesDay;

      final baseEndMinutes = override?.endMinutes ??
          (crossesDay
              ? 24 * 60
              : (hasEndTime && endMinutesOfDay != null && endMinutesOfDay > startMinutes
                  ? endMinutesOfDay
                  : (startMinutes + 30).clamp(0, 24 * 60)));

      final startDayIndex = dateIndexByKey[dueKey];
      if (startDayIndex != null) {
        final minEnd = math.min(startMinutes + 15, 24 * 60);
        final endMinutes = baseEndMinutes.clamp(minEnd, 24 * 60).toInt();
        eventsByDay[startDayIndex].add(
          _TimelineEvent(
            task: task,
            startMinutes: startMinutes,
            endMinutes: endMinutes,
            allowResize: allowResize,
          ),
        );
      }

      if (!crossesDay) continue;
      final finalEndMinutes = (endMinutesOfDay ?? 0).clamp(0, 24 * 60).toInt();
      if (finalEndMinutes <= 0) continue;

      for (var dayOffset = 1; dayOffset <= effectiveOffsetDays; dayOffset++) {
        final dayKey = _CalendarViewState._dateFormatter
            .format(startDate.add(Duration(days: dayOffset)));
        final dayIndex = dateIndexByKey[dayKey];
        if (dayIndex == null) continue;
        final segmentEnd =
            dayOffset == effectiveOffsetDays ? finalEndMinutes : 24 * 60;
        if (segmentEnd <= 0) continue;
        final endMinutes = segmentEnd.clamp(15, 24 * 60).toInt();
        eventsByDay[dayIndex].add(
          _TimelineEvent(
            task: task,
            startMinutes: 0,
            endMinutes: endMinutes,
            allowResize: false,
          ),
        );
      }
    }

    const columnGap = 2.0;
    final taskLayout = <_TaskLayout>[];
    final moreLayout = <_OverlapMoreLayout>[];
    for (var dayIndex = 0; dayIndex < widget.dayCount; dayIndex++) {
      final dayEvents = eventsByDay[dayIndex];
      if (dayEvents.isEmpty) continue;
      dayEvents.sort((a, b) {
        final byStart = a.startMinutes.compareTo(b.startMinutes);
        if (byStart != 0) return byStart;
        return a.endMinutes.compareTo(b.endMinutes);
      });

      final base = widget.dayForIndex(dayIndex);
      final dayDate = DateTime(base.year, base.month, base.day);

      final clusters = <List<_TimelineEvent>>[];
      var current = <_TimelineEvent>[];
      var clusterEnd = -1;
      for (final event in dayEvents) {
        if (current.isEmpty) {
          current = <_TimelineEvent>[event];
          clusterEnd = event.endMinutes;
          continue;
        }
        if (event.startMinutes < clusterEnd) {
          current.add(event);
          clusterEnd = math.max(clusterEnd, event.endMinutes);
          continue;
        }
        clusters.add(current);
        current = <_TimelineEvent>[event];
        clusterEnd = event.endMinutes;
      }
      if (current.isNotEmpty) clusters.add(current);

      for (final cluster in clusters) {
        final columnEnds = <int>[];
        final placed = <_TimelineEventPlacement>[];
        for (final event in cluster) {
          var columnIndex = -1;
          for (var i = 0; i < columnEnds.length; i++) {
            if (columnEnds[i] <= event.startMinutes) {
              columnIndex = i;
              break;
            }
          }
          if (columnIndex < 0) {
            columnIndex = columnEnds.length;
            columnEnds.add(event.endMinutes);
          } else {
            columnEnds[columnIndex] = event.endMinutes;
          }
          placed.add(
              _TimelineEventPlacement(event: event, columnIndex: columnIndex));
        }

        final columnCount = columnEnds.length.clamp(1, 9999);
        final available =
            (widget.dayWidth - _gridPadding * 2 - columnGap * (columnCount - 1))
                .clamp(0.0, double.infinity);
        final width =
            (available / columnCount).clamp(0.0, double.infinity).toDouble();

        final shouldCollapse =
            columnCount > _maxOverlapColumns && width < _minOverlapColumnWidth;
        if (!shouldCollapse) {
          for (final placement in placed) {
            final event = placement.event;
            final top = (event.startMinutes / 15) * _quarterHeight;
            final duration =
                (event.endMinutes - event.startMinutes).clamp(15, 24 * 60);
            final height = (duration / 15) * _quarterHeight;
            final left = dayIndex * widget.dayWidth +
                _gridPadding +
                placement.columnIndex * (width + columnGap);
            taskLayout.add(
              _TaskLayout(
                task: event.task,
                date: dayDate,
                startMinutes: event.startMinutes,
                endMinutes: event.endMinutes,
                left: left,
                top: top,
                width: width,
                height: height,
                allowResize: event.allowResize,
              ),
            );
          }
          continue;
        }

        final collapsedAvailable =
            (widget.dayWidth - _gridPadding * 2 - columnGap * 1)
                .clamp(0.0, double.infinity);
        final collapsedWidth =
            (collapsedAvailable / _maxOverlapColumns)
                .clamp(0.0, double.infinity)
                .toDouble();

        final hiddenTasks = <Task>[];
        var hiddenStart = 24 * 60;
        var hiddenEnd = 0;

        for (final placement in placed) {
          final event = placement.event;
          if (placement.columnIndex >= _maxOverlapColumns) {
            hiddenTasks.add(event.task);
            hiddenStart = math.min(hiddenStart, event.startMinutes);
            hiddenEnd = math.max(hiddenEnd, event.endMinutes);
            continue;
          }

          final top = (event.startMinutes / 15) * _quarterHeight;
          final duration =
              (event.endMinutes - event.startMinutes).clamp(15, 24 * 60);
          final height = (duration / 15) * _quarterHeight;
          final left = dayIndex * widget.dayWidth +
              _gridPadding +
              placement.columnIndex * (collapsedWidth + columnGap);
          taskLayout.add(
            _TaskLayout(
              task: event.task,
              date: dayDate,
              startMinutes: event.startMinutes,
              endMinutes: event.endMinutes,
              left: left,
              top: top,
              width: collapsedWidth.toDouble(),
              height: height,
              allowResize: event.allowResize,
            ),
          );
        }

        if (hiddenTasks.isNotEmpty) {
          final left = dayIndex * widget.dayWidth + _gridPadding;
          final top = (hiddenStart / 15) * _quarterHeight;
          moreLayout.add(
            _OverlapMoreLayout(
              date: dayDate,
              startMinutes: hiddenStart,
              endMinutes:
                  hiddenEnd.clamp(hiddenStart + 15, 24 * 60).toInt(),
              tasks: hiddenTasks,
              left: left,
              top: top,
              width: (widget.dayWidth - _gridPadding * 2)
                  .clamp(0.0, double.infinity)
                  .toDouble(),
            ),
          );
        }
      }
    }

    return DragTarget<_TaskDragPayload>(
      onWillAcceptWithDetails: (details) => widget.onDropTask != null,
      onAcceptWithDetails: (details) {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        final local = box.globalToLocal(details.offset);
        final hit = _hitTestSlot(local);
        if (hit == null) return;
        widget.onDropTask?.call(details.data.task, hit.date, hit.time);
      },
      builder: (context, _, __) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: widget.onTapSlot == null
              ? null
              : (details) {
                  final hit = _hitTestSlot(details.localPosition);
                  if (hit == null) return;
                  widget.onTapSlot?.call(hit.date, hit.time);
                },
          child: Stack(
            children: [
              CustomPaint(
                size: Size(widget.dayWidth * widget.dayCount, _hourHeight * 24),
                painter: _GridPainter(
                    dayCount: widget.dayCount, dayWidth: widget.dayWidth),
              ),
              for (final item in taskLayout)
                Positioned(
                  left: item.left,
                  top: item.top,
                  width: item.width,
                  height: item.height,
                  child: _ResizableTaskBlock(
                    key: ValueKey(
                        '${item.task.id}_${_CalendarViewState._dateFormatter.format(item.date)}_${item.startMinutes}'),
                    task: item.task,
                    date: item.date,
                    startMinutes: item.startMinutes,
                    endMinutes: item.endMinutes,
                    onResizePreview:
                        widget.onResizeTask == null || !item.allowResize
                        ? null
                        : (startMinutes, endMinutes) => _previewTaskRange(
                            item.task.id, startMinutes, endMinutes),
                    onResizeCommit: widget.onResizeTask == null || !item.allowResize
                        ? null
                        : (startMinutes, endMinutes) => _commitTaskRange(
                            item.task, item.date, startMinutes, endMinutes),
                    child: _TimelineTaskBlock(
                      task: item.task,
                      showStartTime: widget.showTaskStartTime,
                      showTags: widget.showTaskTags,
                      onToggle: widget.onToggleTask == null
                          ? null
                          : () => widget.onToggleTask!(item.task),
                      onOpen: widget.onOpenTask == null
                          ? null
                          : () => widget.onOpenTask!(item.task),
                    ),
                  ),
                ),
              for (final more in moreLayout)
                Positioned(
                  left: more.left,
                  top: more.top + 2,
                  width: more.width,
                  height: 20,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _openOverlappingTasksSheet(
                          more.date,
                          more.startMinutes,
                          more.endMinutes,
                          more.tasks,
                        ),
                        child: _MoreBadge(count: more.tasks.length),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  _SlotHit? _hitTestSlot(Offset local) {
    if (local.dx < 0 || local.dy < 0) return null;
    final dayIndex =
        (local.dx ~/ widget.dayWidth).clamp(0, widget.dayCount - 1);
    final date = widget.dayForIndex(dayIndex);
    final minutes = (local.dy / _quarterHeight).floor() * 15;
    final snapped = minutes.clamp(0, 24 * 60 - 15);
    return _SlotHit(
      date: DateTime(date.year, date.month, date.day),
      time: TimeOfDay(hour: snapped ~/ 60, minute: snapped % 60),
    );
  }
}

class _GridPainter extends CustomPainter {
  const _GridPainter({required this.dayCount, required this.dayWidth});

  final int dayCount;
  final double dayWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final hourPaint = Paint()
      ..color = AppColors.outline
      ..strokeWidth = 1;
    final quarterPaint = Paint()
      ..color = AppColors.outline.withOpacity(0.55)
      ..strokeWidth = 1;
    final dayPaint = Paint()
      ..color = AppColors.outline.withOpacity(0.9)
      ..strokeWidth = 1;

    for (var i = 0; i <= 96; i++) {
      final y = i * _quarterHeight;
      canvas.drawLine(Offset(0, y), Offset(size.width, y),
          i % 4 == 0 ? hourPaint : quarterPaint);
    }
    for (var day = 1; day < dayCount; day++) {
      final x = day * dayWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), dayPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) {
    return oldDelegate.dayCount != dayCount || oldDelegate.dayWidth != dayWidth;
  }
}

class _TaskLayout {
  const _TaskLayout({
    required this.task,
    required this.date,
    required this.startMinutes,
    required this.endMinutes,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.allowResize,
  });

  final Task task;
  final DateTime date;
  final int startMinutes;
  final int endMinutes;
  final double left;
  final double top;
  final double width;
  final double height;
  final bool allowResize;
}

class _TimeRangeOverride {
  const _TimeRangeOverride(
      {required this.startMinutes, required this.endMinutes});

  final int startMinutes;
  final int endMinutes;
}

class _TimelineEvent {
  const _TimelineEvent({
    required this.task,
    required this.startMinutes,
    required this.endMinutes,
    required this.allowResize,
  });

  final Task task;
  final int startMinutes;
  final int endMinutes;
  final bool allowResize;
}

class _TimelineEventPlacement {
  const _TimelineEventPlacement(
      {required this.event, required this.columnIndex});

  final _TimelineEvent event;
  final int columnIndex;
}

class _OverlapMoreLayout {
  const _OverlapMoreLayout({
    required this.date,
    required this.startMinutes,
    required this.endMinutes,
    required this.tasks,
    required this.left,
    required this.top,
    required this.width,
  });

  final DateTime date;
  final int startMinutes;
  final int endMinutes;
  final List<Task> tasks;
  final double left;
  final double top;
  final double width;
}

// ignore: unused_element
class _TaskBlock extends StatelessWidget {
  const _TaskBlock({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context) {
    final bg = TaskColors.resolveBackground(task.id, task.colorHex);
    final baseColor = bg ?? Colors.white;
    final borderColor = bg?.withOpacity(0.65) ?? AppColors.outline;

    final title = task.title.trim().isEmpty ? '未命名任务' : task.title.trim();
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: task.isCompleted ? baseColor.withOpacity(0.55) : baseColor,
        borderRadius: BorderRadius.circular(_blockRadius),
        border: Border.all(color: borderColor),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final textStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: task.isCompleted ? AppColors.inkSoft : AppColors.ink,
                height: 1.0,
              );
          return ClipRect(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth:
                        (constraints.maxWidth - 8).clamp(0.0, double.infinity),
                  ),
                  child: Text(
                    title,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: textStyle,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );

    return Draggable<_TaskDragPayload>(
      data: _TaskDragPayload(task),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        color: Colors.transparent,
        child:
            Opacity(opacity: 0.95, child: SizedBox(width: 240, child: content)),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: content),
      child: content,
    );
  }
}

class _TimelineTaskBlock extends StatelessWidget {
  const _TimelineTaskBlock({
    required this.task,
    required this.showStartTime,
    required this.showTags,
    this.onToggle,
    this.onOpen,
  });

  final Task task;
  final bool showStartTime;
  final bool showTags;
  final Future<void> Function()? onToggle;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final bg = TaskColors.resolveBackground(task.id, task.colorHex);
    final baseColor = bg ?? Colors.white;
    final borderColor = bg?.withOpacity(0.65) ?? AppColors.outline;

    final isDone = task.isCompleted;
    final fg =
        ThemeData.estimateBrightnessForColor(baseColor) == Brightness.dark
            ? Colors.white
            : AppColors.ink;
    final mutedFg = isDone ? fg.withOpacity(0.65) : fg;

    final title = task.title.trim().isEmpty ? '未命名任务' : task.title.trim();
    final start = task.startTime.trim();
    final tags = task.displayTags;
    final shownTags = tags.take(1).toList();
    final extraTags = (tags.length - shownTags.length).clamp(0, 999);

    final metaParts = <String>[];
    if (showStartTime && start.isNotEmpty) metaParts.add(start);
    if (showTags) {
      metaParts.addAll(shownTags);
      if (extraTags > 0) metaParts.add('+$extraTags');
    }
    final metaText = metaParts.join('  ');

    final remindLabel = _buildTaskRemindLabel(task);
    final repeatLabel = _buildTaskRepeatLabel(task.repeatRule);
    final attachmentCount = task.attachments.length;
    final hasIndicators =
        remindLabel != null || repeatLabel != null || attachmentCount > 0;

    final checkbox = InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: mutedFg.withOpacity(0.9), width: 1.6),
          color: isDone ? AppColors.accentCool : Colors.transparent,
        ),
        child: isDone
            ? const Icon(Icons.check, size: 10, color: Colors.white)
            : null,
      ),
    );

    final body = Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isDone ? baseColor.withOpacity(0.55) : baseColor,
        borderRadius: BorderRadius.circular(_blockRadius),
        border: Border.all(color: borderColor),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final textStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: mutedFg,
                height: 1.0,
              );
          final metaStyle = textStyle?.copyWith(
            fontWeight: FontWeight.w700,
            color: mutedFg.withOpacity(0.9),
          );
          final showMeta = (metaText.isNotEmpty || hasIndicators) &&
              constraints.maxHeight >= 46;
          final indicatorColor = mutedFg.withOpacity(0.9);

          final inlineIcons = <IconData>[];
          if (hasIndicators && !showMeta) {
            if (remindLabel != null) {
              inlineIcons.add(Icons.notifications_active_outlined);
            }
            if (attachmentCount > 0) {
              inlineIcons.add(Icons.attach_file);
            }
            if (repeatLabel != null) {
              inlineIcons.add(Icons.repeat);
            }
            final maxIcons = constraints.maxWidth >= 90 ? 3 : 1;
            if (inlineIcons.length > maxIcons) {
              inlineIcons.removeRange(maxIcons, inlineIcons.length);
            }
          }

          final metaSpans = <InlineSpan>[];
          void addMetaSeparator() {
            if (metaSpans.isEmpty) return;
            metaSpans.add(const TextSpan(text: '  '));
          }

          void addMetaText(String text) {
            if (text.trim().isEmpty) return;
            addMetaSeparator();
            metaSpans.add(TextSpan(text: text));
          }

          void addMetaIcon(IconData icon, {String label = ''}) {
            addMetaSeparator();
            metaSpans.add(
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Icon(icon, size: 12, color: indicatorColor),
              ),
            );
            if (label.trim().isEmpty) return;
            metaSpans.add(TextSpan(text: ' $label'));
          }

          if (showStartTime && start.isNotEmpty) {
            addMetaText(start);
          }
          if (remindLabel != null) {
            final showLabel = !(showStartTime &&
                start.isNotEmpty &&
                remindLabel.trim() == start);
            addMetaIcon(
              Icons.notifications_active_outlined,
              label: showLabel ? remindLabel : '',
            );
          }
          if (attachmentCount > 0) {
            addMetaIcon(Icons.attach_file, label: attachmentCount.toString());
          }
          if (repeatLabel != null) {
            addMetaIcon(Icons.repeat, label: repeatLabel);
          }
          if (showTags) {
            for (final tag in shownTags) {
              addMetaText(tag);
            }
            if (extraTags > 0) addMetaText('+$extraTags');
          }
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  checkbox,
                  const SizedBox(width: 6),
                  if (inlineIcons.isNotEmpty) ...[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < inlineIcons.length; i++) ...[
                          if (i > 0) const SizedBox(width: 2),
                          Icon(
                            inlineIcons[i],
                            size: 12,
                            color: indicatorColor,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: ClipRect(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: constraints.maxWidth
                                  .clamp(0.0, double.infinity),
                            ),
                            child: Text(
                              title,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.left,
                              style: textStyle,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (showMeta) ...[
                const SizedBox(height: 2),
                Padding(
                  padding: const EdgeInsets.only(left: 20),
                  child: Text.rich(
                    TextSpan(style: metaStyle, children: metaSpans),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );

    final interactive = Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(_blockRadius),
        child: body,
      ),
    );

    final useImmediateDrag = kIsWeb ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;

    if (useImmediateDrag) {
      return Draggable<_TaskDragPayload>(
        data: _TaskDragPayload(task),
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: Material(
          color: Colors.transparent,
          child:
              Opacity(opacity: 0.95, child: SizedBox(width: 240, child: body)),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: body),
        child: interactive,
      );
    }

    return LongPressDraggable<_TaskDragPayload>(
      data: _TaskDragPayload(task),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(opacity: 0.95, child: SizedBox(width: 240, child: body)),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: body),
      child: interactive,
    );
  }
}

class _ResizableTaskBlock extends StatefulWidget {
  const _ResizableTaskBlock({
    super.key,
    required this.task,
    required this.date,
    required this.startMinutes,
    required this.endMinutes,
    required this.child,
    this.onResizePreview,
    this.onResizeCommit,
  });

  final Task task;
  final DateTime date;
  final int startMinutes;
  final int endMinutes;
  final Widget child;
  final void Function(int startMinutes, int endMinutes)? onResizePreview;
  final Future<void> Function(int startMinutes, int endMinutes)? onResizeCommit;

  @override
  State<_ResizableTaskBlock> createState() => _ResizableTaskBlockState();
}

class _ResizableTaskBlockState extends State<_ResizableTaskBlock> {
  double _resizeCarry = 0;
  int? _resizeInitialStart;
  int? _resizeInitialEnd;
  bool _resizingTop = false;

  bool get _canResize =>
      widget.onResizePreview != null && widget.onResizeCommit != null;

  void _beginResize({required bool top}) {
    if (!_canResize) return;
    _resizeCarry = 0;
    _resizeInitialStart = widget.startMinutes;
    _resizeInitialEnd = widget.endMinutes;
    _resizingTop = top;
  }

  void _updateResize(DragUpdateDetails details) {
    final preview = widget.onResizePreview;
    if (preview == null) return;

    _resizeCarry += details.delta.dy;
    final steps = (_resizeCarry / _quarterHeight).truncate();
    if (steps == 0) return;
    _resizeCarry -= steps * _quarterHeight;
    final deltaMinutes = steps * 15;

    if (_resizingTop) {
      final nextStart =
          (widget.startMinutes + deltaMinutes).clamp(0, widget.endMinutes - 15);
      if (nextStart == widget.startMinutes) return;
      preview(nextStart, widget.endMinutes);
      return;
    }

    final nextEnd = (widget.endMinutes + deltaMinutes)
        .clamp(widget.startMinutes + 15, 24 * 60);
    if (nextEnd == widget.endMinutes) return;
    preview(widget.startMinutes, nextEnd);
  }

  Future<void> _endResize() async {
    final commit = widget.onResizeCommit;
    final initialStart = _resizeInitialStart;
    final initialEnd = _resizeInitialEnd;
    _resizeCarry = 0;
    _resizeInitialStart = null;
    _resizeInitialEnd = null;
    if (commit == null || initialStart == null || initialEnd == null) return;
    if (widget.startMinutes == initialStart && widget.endMinutes == initialEnd)
      return;
    await commit(widget.startMinutes, widget.endMinutes);
  }

  Widget _buildHandle({required bool top}) {
    final handleColor = AppColors.inkSoft.withOpacity(0.6);
    return Positioned(
      left: 0,
      right: 0,
      top: top ? 0 : null,
      bottom: top ? null : 0,
      height: 14,
      child: Align(
        alignment: top ? Alignment.topCenter : Alignment.bottomCenter,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (_) => _beginResize(top: top),
          onVerticalDragUpdate: _updateResize,
          onVerticalDragEnd: (_) => _endResize(),
          onVerticalDragCancel: () => _endResize(),
          child: SizedBox(
            width: 60,
            height: 14,
            child: Center(
              child: Container(
                width: 28,
                height: 3,
                decoration: BoxDecoration(
                  color: handleColor,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        if (_canResize) _buildHandle(top: true),
        if (_canResize) _buildHandle(top: false),
      ],
    );
  }
}

class _MonthDayCell extends StatelessWidget {
  const _MonthDayCell({
    required this.dayKey,
    required this.date,
    required this.inMonth,
    required this.selected,
    required this.lunarLabel,
    required this.holiday,
    required this.tasks,
    required this.showTaskStartTime,
    required this.showTaskTags,
    required this.onTap,
    required this.onDrop,
    required this.onToggleTask,
    required this.onReorderTasks,
    required this.onOpenTask,
  });

  final String dayKey;
  final DateTime date;
  final bool inMonth;
  final bool selected;
  final String lunarLabel;
  final HolidayCnDay? holiday;
  final List<Task> tasks;
  final bool showTaskStartTime;
  final bool showTaskTags;
  final VoidCallback? onTap;
  final void Function(Task task)? onDrop;
  final Future<void> Function(Task task)? onToggleTask;
  final void Function(String dayKey, List<String> orderedTaskIds)?
      onReorderTasks;
  final void Function(Task task)? onOpenTask;

  @override
  Widget build(BuildContext context) {
    final textColor = inMonth ? AppColors.ink : AppColors.inkSoft;
    final borderColor = selected ? AppColors.accent : AppColors.outline;
    final bg = selected
        ? AppColors.accent.withOpacity(0.06)
        : (inMonth
            ? Colors.white.withOpacity(0.85)
            : Colors.white.withOpacity(0.55));
    final orderedTasks = tasks;

    return DragTarget<_TaskDragPayload>(
      onWillAcceptWithDetails: (details) => onDrop != null,
      onAcceptWithDetails: (details) => onDrop?.call(details.data.task),
      builder: (context, _, __) {
        return Container(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(
              color: borderColor,
              width: selected ? 2 : 0.5,
            ),
          ),
	          child: LayoutBuilder(
	            builder: (context, constraints) {
	              final textScale = MediaQuery.textScaleFactorOf(context);
              final dayStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: textColor,
                    fontSize: 14,
                    height: 1.0,
                  );
              final lunarStyle =
                  Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.inkSoft,
                        fontSize: 10,
                        height: 1.0,
                      );
	              final holidayStyle =
	                  Theme.of(context).textTheme.labelSmall?.copyWith(
	                        fontWeight: FontWeight.w800,
	                        fontSize: 10,
                        height: 1.0,
                      );
	              const baseTaskFontSize = 11.0;
	              final taskStyle =
	                  Theme.of(context).textTheme.labelSmall?.copyWith(
	                        color: AppColors.ink,
	                        fontWeight: FontWeight.w700,
	                        fontSize: baseTaskFontSize,
	                        height: 1.0,
	                      );

              double lineHeight(TextStyle? style, double fallbackFontSize) {
                final fontSize =
                    (style?.fontSize ?? fallbackFontSize) * textScale;
                final heightFactor = style?.height ?? 1.2;
                return fontSize * heightFactor;
              }

              const contentGap = 2.0;
              final dayLine = lineHeight(dayStyle, 14);
              final lunarLine = lineHeight(lunarStyle, 10);
              final textLine = dayLine > lunarLine ? dayLine : lunarLine;
              final badgeHeight =
                  holiday == null ? 0.0 : lineHeight(holidayStyle, 10) + 6;
              final headerLine =
                  textLine > badgeHeight ? textLine : badgeHeight;
	              final reservedHeight = headerLine + contentGap;
	              final available = (constraints.maxHeight - reservedHeight)
	                  .clamp(0.0, double.infinity)
	                  .toDouble();

	              final showCheckbox = constraints.maxWidth >= 110;
	              final showStartTimeInline =
	                  showTaskStartTime && constraints.maxWidth >= 110;
	              final showTagsInline = showTaskTags && constraints.maxWidth >= 110;

	              const taskRowHeight = 16.0;
	              const taskGap = 1.0;

	              int fitLines(double space) {
	                const safety = 2.0;
	                space = (space - safety).clamp(0.0, double.infinity);
	                if (space + 0.5 < taskRowHeight) return 0;
	                final perLine = taskRowHeight + taskGap;
	                final count = ((space + taskGap) / perLine).floor();
	                return count.clamp(0, 6);
	              }

	              final maxLines = fitLines(available);
	              final visible = orderedTasks.take(maxLines).toList();
	              final remaining =
	                  (orderedTasks.length - visible.length).clamp(0, 9999);
              void openAllTasks() {
                final sheetTasks = List<Task>.from(orderedTasks);
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (sheetContext) {
                    final title = DateFormat('yyyy-MM-dd').format(date);
                    final maxHeight =
                        MediaQuery.of(sheetContext).size.height * 0.75;
                    return StatefulBuilder(
                      builder: (sheetContext, setSheetState) {
                        void handleReorder(int oldIndex, int newIndex) {
                          if (newIndex > oldIndex) newIndex -= 1;
                          setSheetState(() {
                            final item = sheetTasks.removeAt(oldIndex);
                            sheetTasks.insert(newIndex, item);
                          });
                          onReorderTasks?.call(dayKey,
                              sheetTasks.map((task) => task.id).toList());
                        }

                        void handleToggle(Task task) {
                          final idx =
                              sheetTasks.indexWhere((t) => t.id == task.id);
                          if (idx < 0) return;
                          final current = sheetTasks[idx];
                          setSheetState(() {
                            final updated = current.copyWith(
                              status:
                                  current.isCompleted ? 'todo' : 'completed',
                            );
                            sheetTasks.removeAt(idx);
                            if (updated.isCompleted) {
                              sheetTasks.add(updated);
                              return;
                            }
                            final firstCompleted =
                                sheetTasks.indexWhere((t) => t.isCompleted);
                            final insertAt = firstCompleted < 0
                                ? sheetTasks.length
                                : firstCompleted;
                            sheetTasks.insert(insertAt, updated);
                          });
                          onToggleTask?.call(current);
                          onReorderTasks?.call(
                              dayKey, sheetTasks.map((t) => t.id).toList());
                        }

                        return SafeArea(
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(18)),
                            ),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(maxHeight: maxHeight),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '$title  (${sheetTasks.length})',
                                          style: Theme.of(sheetContext)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                  fontWeight: FontWeight.w800),
                                        ),
                                      ),
                                      if (holiday != null)
                                        _HolidayBadge(day: holiday!),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    lunarLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(sheetContext)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: AppColors.inkSoft),
                                  ),
                                  const SizedBox(height: 12),
                                  Expanded(
                                    child: ReorderableListView.builder(
                                      buildDefaultDragHandles: false,
                                      itemCount: sheetTasks.length,
                                      onReorder: handleReorder,
                                      itemBuilder: (context, index) {
                                        final task = sheetTasks[index];
                                        return _MonthTaskTile(
                                          key: ValueKey(task.id),
                                          task: task,
                                          showStartTime: showTaskStartTime,
                                          showTags: showTaskTags,
                                          onTap: onOpenTask == null
                                              ? null
                                              : () {
                                                  Navigator.of(sheetContext)
                                                      .pop();
                                                  WidgetsBinding.instance
                                                      .addPostFrameCallback(
                                                          (_) {
                                                    onOpenTask?.call(task);
                                                  });
                                                },
                                          onToggle: onToggleTask == null
                                              ? null
                                              : () => handleToggle(task),
                                          trailing:
                                              ReorderableDragStartListener(
                                            index: index,
                                            child: const Padding(
                                              padding: EdgeInsets.only(top: 2),
                                              child: Icon(Icons.drag_handle),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              }

              return ClipRect(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Material(
                        type: MaterialType.transparency,
                        child: InkWell(
                          onTap: onTap,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                height: headerLine,
                                child: Stack(
                                  alignment: Alignment.topLeft,
                                  clipBehavior: Clip.hardEdge,
                                  children: [
                                    Row(
                                      children: [
                                        Text('${date.day}', style: dayStyle),
                                        SizedBox(
                                            width: constraints.maxWidth < 60
                                                ? 2
                                                : 6),
                                        Expanded(
                                          child: Padding(
                                            padding: EdgeInsets.only(
                                              right: holiday == null
                                                  ? 0
                                                  : (constraints.maxWidth < 60
                                                      ? 18
                                                      : 24),
                                            ),
                                            child: Text(
                                              lunarLabel,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: lunarStyle,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (holiday != null)
                                      Positioned(
                                        top: 0,
                                        right: 0,
                                        child:
                                            _HolidayBadge(day: holiday!, dense: true),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: contentGap),
                              for (var i = 0; i < visible.length; i++) ...[
                                if (i > 0) const SizedBox(height: taskGap),
                                SizedBox(
                                  width: double.infinity,
	                                  child: _MonthTaskLine(
	                                    task: visible[i],
	                                    style: taskStyle,
	                                    height: taskRowHeight,
	                                    showCheckbox: showCheckbox,
	                                    showStartTime: showStartTimeInline,
	                                    showTags: showTagsInline,
	                                    onTap: onOpenTask == null
	                                        ? openAllTasks
	                                        : () => onOpenTask?.call(visible[i]),
	                                    onLongPress: openAllTasks,
	                                    onToggle: onToggleTask == null
	                                        ? null
	                                        : () {
	                                            final task = visible[i];
	                                            onToggleTask!.call(task);

                                          if (onReorderTasks == null) return;
                                          final updatedIsDone =
                                              !task.isCompleted;
                                          final nextOrder =
                                              List<Task>.from(orderedTasks);
                                          final idx = nextOrder.indexWhere(
                                              (candidate) =>
                                                  candidate.id == task.id);
                                          if (idx < 0) return;
                                          final item = nextOrder.removeAt(idx);
                                          if (updatedIsDone) {
                                            nextOrder.add(item);
                                          } else {
                                            final firstCompleted = nextOrder
                                                .indexWhere((candidate) =>
                                                    candidate.isCompleted);
                                            final insertAt = firstCompleted < 0
                                                ? nextOrder.length
                                                : firstCompleted;
                                            nextOrder.insert(insertAt, item);
                                          }
                                          onReorderTasks!.call(
                                              dayKey,
                                              nextOrder
                                                  .map((task) => task.id)
                                                  .toList());
	                                          },
	                                  ),
	                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (remaining > 0)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: openAllTasks,
                          child: _MoreBadge(count: remaining),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _MonthTaskLine extends StatelessWidget {
  const _MonthTaskLine({
    required this.task,
    required this.style,
    required this.height,
    required this.showCheckbox,
    required this.showStartTime,
    required this.showTags,
    this.onTap,
    this.onLongPress,
    this.onToggle,
  });

  final Task task;
  final TextStyle? style;
  final double height;
  final bool showCheckbox;
  final bool showStartTime;
  final bool showTags;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onToggle;

  static const _textHeightBehavior = TextHeightBehavior(
    applyHeightToFirstAscent: false,
    applyHeightToLastDescent: false,
  );

  @override
  Widget build(BuildContext context) {
    final isDone = task.isCompleted;
    final bg = TaskColors.resolveBackground(task.id, task.colorHex);
    final baseBg = bg ?? AppColors.surface;
    final blockBg = isDone ? baseBg.withOpacity(0.55) : baseBg;
    final blockBorder = (bg ?? AppColors.outline).withOpacity(0.85);
    final fg = ThemeData.estimateBrightnessForColor(baseBg) == Brightness.dark
        ? Colors.white
        : AppColors.ink;
    final title = task.title.trim().isEmpty ? '未命名任务' : task.title.trim();
    final tags = showTags ? task.displayTags : const <String>[];
    final shownTags = tags.take(1).toList();
    final extraTags = (tags.length - shownTags.length).clamp(0, 999);
    final start = showStartTime ? task.startTime.trim() : '';
    final remindLabel = _buildTaskRemindLabel(task);
    final repeatLabel = _buildTaskRepeatLabel(task.repeatRule);
    final attachmentCount = task.attachments.length;

    final labelParts = <String>[
      title,
      if (start.isNotEmpty) start,
      ...shownTags,
      if (extraTags > 0) '+$extraTags',
    ];
    final label =
        labelParts.where((part) => part.trim().isNotEmpty).join('  ');

    final baseStyle =
        (style ?? Theme.of(context).textTheme.labelSmall)?.copyWith(
      decoration: isDone ? TextDecoration.lineThrough : null,
      color: isDone ? fg.withOpacity(0.65) : fg,
      height: 1.0,
    );
    final fontSize = baseStyle?.fontSize ?? 11.0;
    final indicatorColor = isDone ? fg.withOpacity(0.6) : fg.withOpacity(0.85);
    final indicatorTextStyle = baseStyle?.copyWith(
      fontWeight: FontWeight.w700,
      color: indicatorColor,
      height: 1.0,
    );

    final indicators = <Widget>[];
    void addIndicator(Widget widget) {
      if (indicators.isNotEmpty) indicators.add(const SizedBox(width: 4));
      indicators.add(widget);
    }

    var compactIconCount = 0;
    void addCompactIcon(IconData icon, {double size = 10}) {
      if (compactIconCount >= 2) return;
      compactIconCount += 1;
      addIndicator(Icon(icon, size: size, color: indicatorColor));
    }

    if (!showCheckbox) {
      if (remindLabel != null) {
        addCompactIcon(Icons.notifications_active_outlined);
      }
      if (attachmentCount > 0) {
        addCompactIcon(Icons.attach_file);
      }
      if (repeatLabel != null) {
        addCompactIcon(Icons.repeat);
      }
    } else {
      if (remindLabel != null) {
        final showLabel =
            remindLabel.trim().isNotEmpty && remindLabel.trim() != start;
        addIndicator(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.notifications_active_outlined,
                size: 10,
                color: indicatorColor,
              ),
              if (showLabel) ...[
                const SizedBox(width: 2),
                Text(remindLabel, style: indicatorTextStyle),
              ],
            ],
          ),
        );
      }
      if (attachmentCount > 0) {
        addIndicator(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.attach_file, size: 10, color: indicatorColor),
              const SizedBox(width: 2),
              Text('$attachmentCount', style: indicatorTextStyle),
            ],
          ),
        );
      }
      if (repeatLabel != null) {
        addIndicator(Icon(Icons.repeat, size: 10, color: indicatorColor));
      }
    }

    final content = SizedBox(
      width: double.infinity,
      height: height,
      child: Container(
        width: double.infinity,
        height: height,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: blockBg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: blockBorder, width: 0.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (showCheckbox) ...[
              InkWell(
                onTap: onToggle,
                borderRadius: BorderRadius.circular(3),
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: fg.withOpacity(0.9), width: 1.4),
                    color: isDone ? AppColors.accentCool : Colors.transparent,
                  ),
                  child: isDone
                      ? const Icon(Icons.check, size: 10, color: Colors.white)
                      : null,
                ),
              ),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: baseStyle,
                strutStyle: StrutStyle(
                  fontSize: fontSize,
                  height: 1.0,
                  leading: 0,
                  forceStrutHeight: true,
                ),
                textHeightBehavior: _textHeightBehavior,
              ),
            ),
            if (indicators.isNotEmpty) ...[
              const SizedBox(width: 4),
              ...indicators,
            ],
          ],
        ),
      ),
    );

    if (onTap == null && onLongPress == null) return content;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: content,
      ),
    );
  }
}

class _MonthTaskTile extends StatelessWidget {
  const _MonthTaskTile({
    super.key,
    required this.task,
    required this.showStartTime,
    required this.showTags,
    this.onTap,
    this.onToggle,
    this.trailing,
  });

  final Task task;
  final bool showStartTime;
  final bool showTags;
  final VoidCallback? onTap;
  final VoidCallback? onToggle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final isDone = task.isCompleted;
    final bg = TaskColors.resolveBackground(task.id, task.colorHex);
    final baseColor = bg ?? Colors.white;
    final borderColor = bg?.withOpacity(0.65) ?? AppColors.outline;
    final fg =
        ThemeData.estimateBrightnessForColor(baseColor) == Brightness.dark
            ? Colors.white
            : AppColors.ink;
    final mutedFg = isDone ? fg.withOpacity(0.65) : fg;

    final title = task.title.trim().isEmpty ? '未命名任务' : task.title.trim();
    final start = showStartTime ? task.startTime.trim() : '';
    final remindLabel = _buildTaskRemindLabel(task);
    final repeatLabel = _buildTaskRepeatLabel(task.repeatRule);
    final attachmentCount = task.attachments.length;
    final tags = showTags ? task.displayTags : const <String>[];
    final shownTags = tags.take(6).toList();
    final extraTags = (tags.length - shownTags.length).clamp(0, 999);

    final titleStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w800,
          decoration: isDone ? TextDecoration.lineThrough : null,
          color: mutedFg,
        );
    final metaStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w700,
          decoration: isDone ? TextDecoration.lineThrough : null,
          color: mutedFg,
        );

    final indicatorColor = mutedFg.withOpacity(0.9);
    final spans = <InlineSpan>[
      TextSpan(text: title, style: titleStyle),
      if (showStartTime && start.isNotEmpty)
        TextSpan(text: '  $start', style: metaStyle),
      if (remindLabel != null) ...[
        const TextSpan(text: '  '),
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Icon(
            Icons.notifications_active_outlined,
            size: 14,
            color: indicatorColor,
          ),
        ),
        if (!(showStartTime && start.isNotEmpty && remindLabel.trim() == start))
          TextSpan(text: ' $remindLabel', style: metaStyle),
      ],
      if (attachmentCount > 0) ...[
        const TextSpan(text: '  '),
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Icon(Icons.attach_file, size: 14, color: indicatorColor),
        ),
        TextSpan(text: ' $attachmentCount', style: metaStyle),
      ],
      if (repeatLabel != null) ...[
        const TextSpan(text: '  '),
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Icon(Icons.repeat, size: 14, color: indicatorColor),
        ),
        TextSpan(text: ' $repeatLabel', style: metaStyle),
      ],
      if (showTags)
        for (final tag in shownTags) TextSpan(text: '  $tag', style: metaStyle),
      if (showTags && extraTags > 0)
        TextSpan(text: '  +$extraTags', style: metaStyle),
    ];
    final label = Text.rich(
      TextSpan(children: spans),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );

    final checkbox = InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: mutedFg.withOpacity(0.9), width: 1.6),
          color: isDone ? AppColors.accentCool : Colors.transparent,
        ),
        child: isDone
            ? const Icon(Icons.check, size: 14, color: Colors.white)
            : null,
      ),
    );

    final tile = Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDone ? baseColor.withOpacity(0.55) : baseColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          checkbox,
          const SizedBox(width: 10),
          Expanded(
            child: label,
          ),
          if (trailing != null) ...[
            const SizedBox(width: 6),
            trailing!,
          ],
        ],
      ),
    );

    if (onTap == null) return tile;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: tile,
      ),
    );
  }
}

class _MoreBadge extends StatelessWidget {
  const _MoreBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = '+$count';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.outline),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.inkSoft,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

DateTime _stripTime(DateTime date) => DateTime(date.year, date.month, date.day);

DateTime _weekStart(DateTime date) {
  final normalized = _stripTime(date);
  final delta = (normalized.weekday + 6) % 7;
  return normalized.subtract(Duration(days: delta));
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

int? _parseTimeToMinutes(String value) {
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

int _parseOffsetDays(String raw) {
  final trimmed = raw.trim();
  final plusIndex = trimmed.lastIndexOf('+');
  if (plusIndex <= 0) return 0;
  final parsed = int.tryParse(trimmed.substring(plusIndex + 1).trim()) ?? 0;
  return parsed <= 0 ? 0 : parsed;
}

bool _isCrossDayTask(Task task) {
  final startDay = _tryParseDayKey(task.dueDate.trim());
  if (startDay == null) return false;

  final startMinutes = _parseTimeToMinutes(task.startTime);
  final endMinutesRaw = _parseTimeToMinutes(task.endTime);
  final endDateKey = task.endDate.trim();

  if (startMinutes == null) {
    final endDay = _tryParseDayKey(endDateKey);
    return endDay != null && endDay.isAfter(startDay);
  }
  if (endMinutesRaw == null) return false;

  var endMinutes = endMinutesRaw;
  var offsetDays = 0;
  if (endMinutes == 24 * 60) {
    endMinutes = 0;
    offsetDays += 1;
  }
  if (endDateKey.isNotEmpty) {
    final endDay = _tryParseDayKey(endDateKey);
    if (endDay != null) {
      offsetDays += endDay.difference(startDay).inDays;
    }
  } else {
    offsetDays += _parseOffsetDays(task.endTime);
  }
  if (offsetDays < 0) offsetDays = 0;
  if (offsetDays > 0) return true;
  return endMinutes <= startMinutes;
}

DateTime? _tryParseDayKey(String key) {
  final trimmed = key.trim();
  if (trimmed.isEmpty) return null;
  try {
    return _stripTime(_CalendarViewState._dateFormatter.parseStrict(trimmed));
  } catch (_) {
    final parsed = DateTime.tryParse(trimmed);
    if (parsed == null) return null;
    return _stripTime(parsed);
  }
}

int _parseEndMinutes(Task task, int startMinutes) {
  final raw = task.endTime.trim();
  if (raw.isEmpty) return (startMinutes + 30).clamp(0, 24 * 60);
  final offsetDays = _parseOffsetDays(raw);

  if (offsetDays > 0) return 24 * 60;

  final end = _parseTimeToMinutes(raw);
  if (end != null) {
    if (end > startMinutes) return end;
    // Implicitly treat end <= start as next day.
    if (end <= startMinutes) return 24 * 60;
  }

  return (startMinutes + 30).clamp(0, 24 * 60);
}
