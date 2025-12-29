import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../models/user_settings.dart';
import '../ui/workspace_view.dart';
import 'android_shell.dart';
import 'desktop_shell.dart';

class ShellRouter extends StatelessWidget {
  const ShellRouter({
    super.key,
    required this.appTitle,
    required this.username,
    required this.apiClient,
    required this.userSettings,
    required this.timeTrackingOngoingNotificationEnabled,
    required this.onLogout,
    required this.onOpenSettings,
  });

  final String appTitle;
  final String username;
  final ApiClient apiClient;
  final UserSettings userSettings;
  final bool timeTrackingOngoingNotificationEnabled;
  final VoidCallback onLogout;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final initialWorkspace =
        _workspaceForDefaultView(userSettings.preferences.defaultView);

    // Web: keep it simple for now (use desktop shell).
    if (kIsWeb) {
      return DesktopShell(
        appTitle: appTitle,
        username: username,
        apiClient: apiClient,
        userSettings: userSettings,
        timeTrackingOngoingNotificationEnabled:
            timeTrackingOngoingNotificationEnabled,
        onLogout: onLogout,
        onOpenSettings: onOpenSettings,
        initialWorkspace: initialWorkspace,
      );
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidShell(
        appTitle: appTitle,
        username: username,
        apiClient: apiClient,
        userSettings: userSettings,
        timeTrackingOngoingNotificationEnabled:
            timeTrackingOngoingNotificationEnabled,
        onLogout: onLogout,
        onOpenSettings: onOpenSettings,
        initialWorkspace: initialWorkspace,
      );
    }

    return DesktopShell(
      appTitle: appTitle,
      username: username,
      apiClient: apiClient,
      userSettings: userSettings,
      timeTrackingOngoingNotificationEnabled: timeTrackingOngoingNotificationEnabled,
      onLogout: onLogout,
      onOpenSettings: onOpenSettings,
      initialWorkspace: initialWorkspace,
    );
  }
}

WorkspaceView _workspaceForDefaultView(String raw) {
  switch (raw.trim()) {
    case 'matrix':
      return WorkspaceView.matrix;
    case 'calendar':
      return WorkspaceView.calendar;
    case 'timeTracking':
      return WorkspaceView.timeTracking;
    case 'pomodoro':
      return WorkspaceView.pomodoro;
    case 'stats':
      return WorkspaceView.stats;
    default:
      return WorkspaceView.tasks;
  }
}
