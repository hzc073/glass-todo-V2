enum TaskFilter {
  all,
  today,
  tomorrow,
  next7,
  inbox,
  done,
}

extension TaskFilterLabel on TaskFilter {
  String get label {
    switch (this) {
      case TaskFilter.inbox:
        return '收集箱';
      case TaskFilter.today:
        return '今天';
      case TaskFilter.tomorrow:
        return '明天';
      case TaskFilter.next7:
        return '未来7天';
      case TaskFilter.done:
        return '已完成';
      case TaskFilter.all:
        return '全部任务';
    }
  }

  String get description {
    switch (this) {
      case TaskFilter.inbox:
        return '未整理的记录与灵感。';
      case TaskFilter.today:
        return '今日专注清单。';
      case TaskFilter.tomorrow:
        return '提前安排明天。';
      case TaskFilter.next7:
        return '一周安排一览。';
      case TaskFilter.done:
        return '已完成任务与归档。';
      case TaskFilter.all:
        return '所有任务一屏查看。';
    }
  }
}
