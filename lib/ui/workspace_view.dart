import 'package:flutter/material.dart';

enum WorkspaceView {
  tasks,
  timeTracking,
  calendar,
  checklists,
  pomodoro,
  stats,
}

extension WorkspaceViewMeta on WorkspaceView {
  String get label {
    switch (this) {
      case WorkspaceView.tasks:
        return '任务列表';
      case WorkspaceView.timeTracking:
        return '时间记录';
      case WorkspaceView.calendar:
        return '日历视图';
      case WorkspaceView.checklists:
        return '清单';
      case WorkspaceView.pomodoro:
        return '番茄钟';
      case WorkspaceView.stats:
        return '统计';
    }
  }

  String get description {
    switch (this) {
      case WorkspaceView.tasks:
        return '收集、安排与执行任务。';
      case WorkspaceView.timeTracking:
        return '记录事件耗时并可并行计时。';
      case WorkspaceView.calendar:
        return '以时间轴查看计划。';
      case WorkspaceView.checklists:
        return '拆分项目与事项。';
      case WorkspaceView.pomodoro:
        return '专注节奏与番茄统计。';
      case WorkspaceView.stats:
        return '进度与效率概览。';
    }
  }

  IconData get icon {
    switch (this) {
      case WorkspaceView.tasks:
        return Icons.view_list;
      case WorkspaceView.timeTracking:
        return Icons.av_timer;
      case WorkspaceView.calendar:
        return Icons.calendar_month;
      case WorkspaceView.checklists:
        return Icons.checklist;
      case WorkspaceView.pomodoro:
        return Icons.timer;
      case WorkspaceView.stats:
        return Icons.bar_chart;
    }
  }
}
