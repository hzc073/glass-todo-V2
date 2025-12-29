enum TaskFilter {
  today,
  next7,
  inbox,
  done,
}

extension TaskFilterLabel on TaskFilter {
  String get label {
    switch (this) {
      case TaskFilter.today:
        return '今天';
      case TaskFilter.next7:
        return '本周';
      case TaskFilter.inbox:
        return '收集箱';
      case TaskFilter.done:
        return '已完成';
    }
  }

  String get description {
    switch (this) {
      case TaskFilter.today:
        return '今日专注清单。';
      case TaskFilter.next7:
        return '本周安排一览。';
      case TaskFilter.inbox:
        return '未整理的记录与灵感。';
      case TaskFilter.done:
        return '已完成任务与归档。';
    }
  }
}
