import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../models/user_settings.dart';
import '../ui/task_page.dart';
import '../ui/widgets/decorative_background.dart';
import '../ui/workspace_view.dart';

class AndroidShell extends StatefulWidget {
  const AndroidShell({
    super.key,
    required this.appTitle,
    required this.username,
    required this.apiClient,
    required this.userSettings,
    required this.onLogout,
    required this.onOpenSettings,
    required this.initialWorkspace,
  });

  final String appTitle;
  final String username;
  final ApiClient apiClient;
  final UserSettings userSettings;
  final VoidCallback onLogout;
  final VoidCallback onOpenSettings;
  final WorkspaceView initialWorkspace;

  @override
  State<AndroidShell> createState() => _AndroidShellState();
}

class _AndroidShellState extends State<AndroidShell> {
  static const List<WorkspaceView> _tabs = [
    WorkspaceView.tasks,
    WorkspaceView.matrix,
    WorkspaceView.timeTracking,
    WorkspaceView.calendar,
    WorkspaceView.pomodoro,
    WorkspaceView.stats,
  ];

  late WorkspaceView _workspace = widget.initialWorkspace;

  @override
  Widget build(BuildContext context) {
    final currentIndex = _tabs.indexOf(_workspace);

    return Stack(
      children: [
        const DecorativeBackground(),
        SafeArea(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: TaskPage(
              appTitle: widget.appTitle,
              username: widget.username,
              apiClient: widget.apiClient,
              userSettings: widget.userSettings,
              onLogout: widget.onLogout,
              onOpenSettings: widget.onOpenSettings,
              workspace: _workspace,
            ),
            bottomNavigationBar: BottomNavigationBar(
              type: BottomNavigationBarType.fixed,
              currentIndex: currentIndex < 0 ? 0 : currentIndex,
              onTap: (index) => setState(() => _workspace = _tabs[index]),
              items: _tabs
                  .map(
                    (view) => BottomNavigationBarItem(
                      icon: Icon(view.icon),
                      label: view.label,
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ],
    );
  }
}
