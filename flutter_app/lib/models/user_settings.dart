class UserSettings {
  const UserSettings({
    required this.profile,
    required this.preferences,
    required this.notifications,
    required this.data,
    required this.advanced,
    required this.viewSettings,
    required this.calendarDefaultMode,
    required this.autoMigrateEnabled,
    required this.pushEnabled,
    required this.calendarSettings,
  });

  final UserProfileSettings profile;
  final UserPreferenceSettings preferences;
  final UserNotificationSettings notifications;
  final UserDataSettings data;
  final UserAdvancedSettings advanced;

  // Legacy / existing keys (keep for compatibility)
  final ViewSettings viewSettings;
  final String calendarDefaultMode; // day/week/month
  final bool autoMigrateEnabled;
  final bool pushEnabled;
  final CalendarSettings calendarSettings;

  factory UserSettings.defaults() {
    return const UserSettings(
      profile: UserProfileSettings(nickname: '', avatar: ''),
      preferences: UserPreferenceSettings(
        defaultView: 'inbox',
        undoEnabled: true,
        undoSeconds: 2,
        defaultSort: 'manual',
        theme: 'system',
        weekStart: 'monday',
        shortcutsEnabled: true,
        naturalLanguageEnabled: true,
        matrixScope: 'today',
        calendarTimelineDefaultHour: 8,
      ),
      notifications: UserNotificationSettings(
        enabled: false,
        leadMinutes: 0,
        quietStart: '22:00',
        quietEnd: '08:00',
        dueReminder: true,
        planStartReminder: true,
      ),
      data: UserDataSettings(
        backup: UserBackupSettings(
          enabled: false,
          frequency: 'weekly',
          keep: 10,
          location: 'server',
          serverPath: '',
        ),
        sync: UserSyncSettings(
          mode: 'server',
          conflictStrategy: 'latest',
        ),
        clearCompletedRetentionDays: 30,
      ),
      advanced: UserAdvancedSettings(
        nlpExperimental: false,
        lowEnergySortExperimental: false,
      ),
      viewSettings: ViewSettings(calendar: true, matrix: true, pomodoro: true),
      calendarDefaultMode: 'day',
      autoMigrateEnabled: true,
      pushEnabled: false,
      calendarSettings: CalendarSettings(
        showTime: true,
        showTags: true,
        showLunar: true,
        showHoliday: true,
        taskBlockShowStartTimeDay: true,
        taskBlockShowTagsDay: true,
        taskBlockShowStartTimeWeek: true,
        taskBlockShowTagsWeek: true,
        taskBlockShowStartTimeMonth: true,
        taskBlockShowTagsMonth: true,
      ),
    );
  }

  factory UserSettings.fromJson(Map<String, dynamic> json) {
    final defaults = UserSettings.defaults();
    return UserSettings(
      profile: UserProfileSettings.fromJson(_map(json['profile']),
          defaults: defaults.profile),
      preferences: UserPreferenceSettings.fromJson(_map(json['preferences']),
          defaults: defaults.preferences),
      notifications: UserNotificationSettings.fromJson(
          _map(json['notifications']),
          defaults: defaults.notifications),
      data: UserDataSettings.fromJson(_map(json['data']),
          defaults: defaults.data),
      advanced: UserAdvancedSettings.fromJson(_map(json['advanced']),
          defaults: defaults.advanced),
      viewSettings: ViewSettings.fromJson(_map(json['viewSettings']),
          defaults: defaults.viewSettings),
      calendarDefaultMode:
          (json['calendarDefaultMode'] ?? defaults.calendarDefaultMode)
              .toString(),
      autoMigrateEnabled:
          _parseBool(json['autoMigrateEnabled']) ?? defaults.autoMigrateEnabled,
      pushEnabled: _parseBool(json['pushEnabled']) ?? defaults.pushEnabled,
      calendarSettings: CalendarSettings.fromJson(
          _map(json['calendarSettings']),
          defaults: defaults.calendarSettings),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'profile': profile.toJson(),
      'preferences': preferences.toJson(),
      'notifications': notifications.toJson(),
      'data': data.toJson(),
      'advanced': advanced.toJson(),
      'viewSettings': viewSettings.toJson(),
      'calendarDefaultMode': calendarDefaultMode,
      'autoMigrateEnabled': autoMigrateEnabled,
      'pushEnabled': pushEnabled,
      'calendarSettings': calendarSettings.toJson(),
    };
  }

  UserSettings copyWith({
    UserProfileSettings? profile,
    UserPreferenceSettings? preferences,
    UserNotificationSettings? notifications,
    UserDataSettings? data,
    UserAdvancedSettings? advanced,
    ViewSettings? viewSettings,
    String? calendarDefaultMode,
    bool? autoMigrateEnabled,
    bool? pushEnabled,
    CalendarSettings? calendarSettings,
  }) {
    return UserSettings(
      profile: profile ?? this.profile,
      preferences: preferences ?? this.preferences,
      notifications: notifications ?? this.notifications,
      data: data ?? this.data,
      advanced: advanced ?? this.advanced,
      viewSettings: viewSettings ?? this.viewSettings,
      calendarDefaultMode: calendarDefaultMode ?? this.calendarDefaultMode,
      autoMigrateEnabled: autoMigrateEnabled ?? this.autoMigrateEnabled,
      pushEnabled: pushEnabled ?? this.pushEnabled,
      calendarSettings: calendarSettings ?? this.calendarSettings,
    );
  }
}

class UserProfileSettings {
  const UserProfileSettings({required this.nickname, required this.avatar});

  final String nickname;
  final String avatar; // emoji or short string

  factory UserProfileSettings.fromJson(Map<String, dynamic> json,
      {required UserProfileSettings defaults}) {
    return UserProfileSettings(
      nickname: (json['nickname'] ?? defaults.nickname).toString(),
      avatar: (json['avatar'] ?? defaults.avatar).toString(),
    );
  }

  Map<String, dynamic> toJson() => {'nickname': nickname, 'avatar': avatar};

  UserProfileSettings copyWith({String? nickname, String? avatar}) {
    return UserProfileSettings(
      nickname: nickname ?? this.nickname,
      avatar: avatar ?? this.avatar,
    );
  }
}

class UserPreferenceSettings {
  const UserPreferenceSettings({
    required this.defaultView,
    required this.undoEnabled,
    required this.undoSeconds,
    required this.defaultSort,
    required this.theme,
    required this.weekStart,
    required this.shortcutsEnabled,
    required this.naturalLanguageEnabled,
    required this.matrixScope,
    required this.calendarTimelineDefaultHour,
  });

  final String defaultView;
  final bool undoEnabled;
  final int undoSeconds;
  final String defaultSort;
  final String theme; // light/dark/system
  final String weekStart; // monday/sunday
  final bool shortcutsEnabled;
  final bool naturalLanguageEnabled;
  final String matrixScope; // today/3days/all
  final int calendarTimelineDefaultHour; // 0-23

  factory UserPreferenceSettings.fromJson(Map<String, dynamic> json,
      {required UserPreferenceSettings defaults}) {
    final scopeValue =
        (json['matrixScope'] ?? '').toString().trim().toLowerCase();
    final legacyTodayOnly = _parseBool(json['matrixTodayOnly']);
    final defaultScopeValue = defaults.matrixScope.trim().toLowerCase();
    final defaultScope = defaultScopeValue == 'today' ||
            defaultScopeValue == '3days' ||
            defaultScopeValue == 'all'
        ? defaultScopeValue
        : 'today';
    final scope =
        scopeValue == 'today' || scopeValue == '3days' || scopeValue == 'all'
            ? scopeValue
            : (legacyTodayOnly != null
                ? (legacyTodayOnly ? 'today' : 'all')
                : defaultScope);

    final timelineHour =
        _parseInt(json['calendarTimelineDefaultHour']) ??
            defaults.calendarTimelineDefaultHour;
    final safeTimelineHour = timelineHour.clamp(0, 23);
    return UserPreferenceSettings(
      defaultView: (json['defaultView'] ?? defaults.defaultView).toString(),
      undoEnabled: _parseBool(json['undoEnabled']) ?? defaults.undoEnabled,
      undoSeconds: _parseInt(json['undoSeconds']) ?? defaults.undoSeconds,
      defaultSort: (json['defaultSort'] ?? defaults.defaultSort).toString(),
      theme: (json['theme'] ?? defaults.theme).toString(),
      weekStart: (json['weekStart'] ?? defaults.weekStart).toString(),
      shortcutsEnabled:
          _parseBool(json['shortcutsEnabled']) ?? defaults.shortcutsEnabled,
      naturalLanguageEnabled: _parseBool(json['naturalLanguageEnabled']) ??
          defaults.naturalLanguageEnabled,
      matrixScope: scope,
      calendarTimelineDefaultHour: safeTimelineHour,
    );
  }

  Map<String, dynamic> toJson() => {
        'defaultView': defaultView,
        'undoEnabled': undoEnabled,
        'undoSeconds': undoSeconds,
        'defaultSort': defaultSort,
        'theme': theme,
        'weekStart': weekStart,
        'shortcutsEnabled': shortcutsEnabled,
        'naturalLanguageEnabled': naturalLanguageEnabled,
        'matrixScope': matrixScope,
        'calendarTimelineDefaultHour': calendarTimelineDefaultHour,
      };

  UserPreferenceSettings copyWith({
    String? defaultView,
    bool? undoEnabled,
    int? undoSeconds,
    String? defaultSort,
    String? theme,
    String? weekStart,
    bool? shortcutsEnabled,
    bool? naturalLanguageEnabled,
    String? matrixScope,
    int? calendarTimelineDefaultHour,
  }) {
    return UserPreferenceSettings(
      defaultView: defaultView ?? this.defaultView,
      undoEnabled: undoEnabled ?? this.undoEnabled,
      undoSeconds: undoSeconds ?? this.undoSeconds,
      defaultSort: defaultSort ?? this.defaultSort,
      theme: theme ?? this.theme,
      weekStart: weekStart ?? this.weekStart,
      shortcutsEnabled: shortcutsEnabled ?? this.shortcutsEnabled,
      naturalLanguageEnabled:
          naturalLanguageEnabled ?? this.naturalLanguageEnabled,
      matrixScope: matrixScope ?? this.matrixScope,
      calendarTimelineDefaultHour:
          (calendarTimelineDefaultHour ?? this.calendarTimelineDefaultHour)
              .clamp(0, 23),
    );
  }
}

class UserNotificationSettings {
  const UserNotificationSettings({
    required this.enabled,
    required this.leadMinutes,
    required this.quietStart,
    required this.quietEnd,
    required this.dueReminder,
    required this.planStartReminder,
  });

  final bool enabled;
  final int leadMinutes;
  final String quietStart; // HH:mm
  final String quietEnd; // HH:mm
  final bool dueReminder;
  final bool planStartReminder;

  factory UserNotificationSettings.fromJson(
    Map<String, dynamic> json, {
    required UserNotificationSettings defaults,
  }) {
    final quietHours = _map(json['quietHours']);
    return UserNotificationSettings(
      enabled: _parseBool(json['enabled']) ?? defaults.enabled,
      leadMinutes: _parseInt(json['leadMinutes']) ?? defaults.leadMinutes,
      quietStart: (quietHours['start'] ?? defaults.quietStart).toString(),
      quietEnd: (quietHours['end'] ?? defaults.quietEnd).toString(),
      dueReminder: _parseBool(json['dueReminder']) ?? defaults.dueReminder,
      planStartReminder:
          _parseBool(json['planStartReminder']) ?? defaults.planStartReminder,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'leadMinutes': leadMinutes,
        'quietHours': {'start': quietStart, 'end': quietEnd},
        'dueReminder': dueReminder,
        'planStartReminder': planStartReminder,
      };

  UserNotificationSettings copyWith({
    bool? enabled,
    int? leadMinutes,
    String? quietStart,
    String? quietEnd,
    bool? dueReminder,
    bool? planStartReminder,
  }) {
    return UserNotificationSettings(
      enabled: enabled ?? this.enabled,
      leadMinutes: leadMinutes ?? this.leadMinutes,
      quietStart: quietStart ?? this.quietStart,
      quietEnd: quietEnd ?? this.quietEnd,
      dueReminder: dueReminder ?? this.dueReminder,
      planStartReminder: planStartReminder ?? this.planStartReminder,
    );
  }
}

class UserDataSettings {
  const UserDataSettings({
    required this.backup,
    required this.sync,
    required this.clearCompletedRetentionDays,
  });

  final UserBackupSettings backup;
  final UserSyncSettings sync;
  final int clearCompletedRetentionDays; // 30/90/-1

  factory UserDataSettings.fromJson(Map<String, dynamic> json,
      {required UserDataSettings defaults}) {
    return UserDataSettings(
      backup: UserBackupSettings.fromJson(_map(json['backup']),
          defaults: defaults.backup),
      sync: UserSyncSettings.fromJson(_map(json['sync']),
          defaults: defaults.sync),
      clearCompletedRetentionDays:
          _parseInt(json['clearCompletedRetentionDays']) ??
              defaults.clearCompletedRetentionDays,
    );
  }

  Map<String, dynamic> toJson() => {
        'backup': backup.toJson(),
        'sync': sync.toJson(),
        'clearCompletedRetentionDays': clearCompletedRetentionDays,
      };

  UserDataSettings copyWith({
    UserBackupSettings? backup,
    UserSyncSettings? sync,
    int? clearCompletedRetentionDays,
  }) {
    return UserDataSettings(
      backup: backup ?? this.backup,
      sync: sync ?? this.sync,
      clearCompletedRetentionDays:
          clearCompletedRetentionDays ?? this.clearCompletedRetentionDays,
    );
  }
}

class UserBackupSettings {
  const UserBackupSettings({
    required this.enabled,
    required this.frequency,
    required this.keep,
    required this.location,
    required this.serverPath,
  });

  final bool enabled;
  final String frequency; // daily/weekly
  final int keep;
  final String location; // local/server
  final String serverPath;

  factory UserBackupSettings.fromJson(Map<String, dynamic> json,
      {required UserBackupSettings defaults}) {
    return UserBackupSettings(
      enabled: _parseBool(json['enabled']) ?? defaults.enabled,
      frequency: (json['frequency'] ?? defaults.frequency).toString(),
      keep: _parseInt(json['keep']) ?? defaults.keep,
      location: (json['location'] ?? defaults.location).toString(),
      serverPath: (json['serverPath'] ?? defaults.serverPath).toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'frequency': frequency,
        'keep': keep,
        'location': location,
        'serverPath': serverPath,
      };

  UserBackupSettings copyWith({
    bool? enabled,
    String? frequency,
    int? keep,
    String? location,
    String? serverPath,
  }) {
    return UserBackupSettings(
      enabled: enabled ?? this.enabled,
      frequency: frequency ?? this.frequency,
      keep: keep ?? this.keep,
      location: location ?? this.location,
      serverPath: serverPath ?? this.serverPath,
    );
  }
}

class UserSyncSettings {
  const UserSyncSettings({
    required this.mode,
    required this.conflictStrategy,
  });

  final String mode; // local/server
  final String conflictStrategy; // latest/manual/duplicate

  factory UserSyncSettings.fromJson(Map<String, dynamic> json,
      {required UserSyncSettings defaults}) {
    return UserSyncSettings(
      mode: (json['mode'] ?? defaults.mode).toString(),
      conflictStrategy:
          (json['conflictStrategy'] ?? defaults.conflictStrategy).toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'mode': mode,
        'conflictStrategy': conflictStrategy,
      };

  UserSyncSettings copyWith({String? mode, String? conflictStrategy}) {
    return UserSyncSettings(
      mode: mode ?? this.mode,
      conflictStrategy: conflictStrategy ?? this.conflictStrategy,
    );
  }
}

class UserAdvancedSettings {
  const UserAdvancedSettings({
    required this.nlpExperimental,
    required this.lowEnergySortExperimental,
  });

  final bool nlpExperimental;
  final bool lowEnergySortExperimental;

  factory UserAdvancedSettings.fromJson(Map<String, dynamic> json,
      {required UserAdvancedSettings defaults}) {
    return UserAdvancedSettings(
      nlpExperimental:
          _parseBool(json['nlpExperimental']) ?? defaults.nlpExperimental,
      lowEnergySortExperimental:
          _parseBool(json['lowEnergySortExperimental']) ??
              defaults.lowEnergySortExperimental,
    );
  }

  Map<String, dynamic> toJson() => {
        'nlpExperimental': nlpExperimental,
        'lowEnergySortExperimental': lowEnergySortExperimental,
      };

  UserAdvancedSettings copyWith(
      {bool? nlpExperimental, bool? lowEnergySortExperimental}) {
    return UserAdvancedSettings(
      nlpExperimental: nlpExperimental ?? this.nlpExperimental,
      lowEnergySortExperimental:
          lowEnergySortExperimental ?? this.lowEnergySortExperimental,
    );
  }
}

class ViewSettings {
  const ViewSettings(
      {required this.calendar, required this.matrix, required this.pomodoro});

  final bool calendar;
  final bool matrix;
  final bool pomodoro;

  factory ViewSettings.fromJson(Map<String, dynamic> json,
      {required ViewSettings defaults}) {
    return ViewSettings(
      calendar: _parseBool(json['calendar']) ?? defaults.calendar,
      matrix: _parseBool(json['matrix']) ?? defaults.matrix,
      pomodoro: _parseBool(json['pomodoro']) ?? defaults.pomodoro,
    );
  }

  Map<String, dynamic> toJson() => {
        'calendar': calendar,
        'matrix': matrix,
        'pomodoro': pomodoro,
      };
}

class CalendarSettings {
  const CalendarSettings({
    required this.showTime,
    required this.showTags,
    required this.showLunar,
    required this.showHoliday,
    required this.taskBlockShowStartTimeDay,
    required this.taskBlockShowTagsDay,
    required this.taskBlockShowStartTimeWeek,
    required this.taskBlockShowTagsWeek,
    required this.taskBlockShowStartTimeMonth,
    required this.taskBlockShowTagsMonth,
  });

  final bool showTime;
  final bool showTags;
  final bool showLunar;
  final bool showHoliday;
  final bool taskBlockShowStartTimeDay;
  final bool taskBlockShowTagsDay;
  final bool taskBlockShowStartTimeWeek;
  final bool taskBlockShowTagsWeek;
  final bool taskBlockShowStartTimeMonth;
  final bool taskBlockShowTagsMonth;

  factory CalendarSettings.fromJson(Map<String, dynamic> json,
      {required CalendarSettings defaults}) {
    final showTime = _parseBool(json['showTime']) ?? defaults.showTime;
    final showTags = _parseBool(json['showTags']) ?? defaults.showTags;
    return CalendarSettings(
      showTime: showTime,
      showTags: showTags,
      showLunar: _parseBool(json['showLunar']) ?? defaults.showLunar,
      showHoliday: _parseBool(json['showHoliday']) ?? defaults.showHoliday,
      taskBlockShowStartTimeDay:
          _parseBool(json['taskBlockShowStartTimeDay']) ?? showTime,
      taskBlockShowTagsDay:
          _parseBool(json['taskBlockShowTagsDay']) ?? showTags,
      taskBlockShowStartTimeWeek:
          _parseBool(json['taskBlockShowStartTimeWeek']) ?? showTime,
      taskBlockShowTagsWeek:
          _parseBool(json['taskBlockShowTagsWeek']) ?? showTags,
      taskBlockShowStartTimeMonth:
          _parseBool(json['taskBlockShowStartTimeMonth']) ?? showTime,
      taskBlockShowTagsMonth:
          _parseBool(json['taskBlockShowTagsMonth']) ?? showTags,
    );
  }

  Map<String, dynamic> toJson() => {
        'showTime': showTime,
        'showTags': showTags,
        'showLunar': showLunar,
        'showHoliday': showHoliday,
        'taskBlockShowStartTimeDay': taskBlockShowStartTimeDay,
        'taskBlockShowTagsDay': taskBlockShowTagsDay,
        'taskBlockShowStartTimeWeek': taskBlockShowStartTimeWeek,
        'taskBlockShowTagsWeek': taskBlockShowTagsWeek,
        'taskBlockShowStartTimeMonth': taskBlockShowStartTimeMonth,
        'taskBlockShowTagsMonth': taskBlockShowTagsMonth,
      };

  CalendarSettings copyWith({
    bool? showTime,
    bool? showTags,
    bool? showLunar,
    bool? showHoliday,
    bool? taskBlockShowStartTimeDay,
    bool? taskBlockShowTagsDay,
    bool? taskBlockShowStartTimeWeek,
    bool? taskBlockShowTagsWeek,
    bool? taskBlockShowStartTimeMonth,
    bool? taskBlockShowTagsMonth,
  }) {
    return CalendarSettings(
      showTime: showTime ?? this.showTime,
      showTags: showTags ?? this.showTags,
      showLunar: showLunar ?? this.showLunar,
      showHoliday: showHoliday ?? this.showHoliday,
      taskBlockShowStartTimeDay:
          taskBlockShowStartTimeDay ?? this.taskBlockShowStartTimeDay,
      taskBlockShowTagsDay: taskBlockShowTagsDay ?? this.taskBlockShowTagsDay,
      taskBlockShowStartTimeWeek:
          taskBlockShowStartTimeWeek ?? this.taskBlockShowStartTimeWeek,
      taskBlockShowTagsWeek:
          taskBlockShowTagsWeek ?? this.taskBlockShowTagsWeek,
      taskBlockShowStartTimeMonth:
          taskBlockShowStartTimeMonth ?? this.taskBlockShowStartTimeMonth,
      taskBlockShowTagsMonth:
          taskBlockShowTagsMonth ?? this.taskBlockShowTagsMonth,
    );
  }
}

Map<String, dynamic> _map(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  return <String, dynamic>{};
}

bool? _parseBool(dynamic value) {
  if (value == null) return null;
  if (value is bool) return value;
  if (value is num) return value != 0;
  final raw = value.toString().trim().toLowerCase();
  if (raw == 'true' || raw == '1') return true;
  if (raw == 'false' || raw == '0') return false;
  return null;
}

int? _parseInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}
