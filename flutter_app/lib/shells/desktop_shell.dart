import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../models/user_settings.dart';
import '../ui/task_page.dart';
import '../ui/widgets/decorative_background.dart';
import '../ui/widgets/sidebar.dart';
import '../ui/workspace_view.dart';

class DesktopShell extends StatefulWidget {
  const DesktopShell({
    super.key,
    required this.appTitle,
    required this.username,
    required this.apiClient,
    required this.userSettings,
    required this.timeTrackingOngoingNotificationEnabled,
    required this.onLogout,
    required this.onOpenSettings,
    required this.initialWorkspace,
  });

  final String appTitle;
  final String username;
  final ApiClient apiClient;
  final UserSettings userSettings;
  final bool timeTrackingOngoingNotificationEnabled;
  final VoidCallback onLogout;
  final VoidCallback onOpenSettings;
  final WorkspaceView initialWorkspace;

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  late WorkspaceView _workspace = widget.initialWorkspace;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth >= 960;

    final navigation = Sidebar(
      appTitle: widget.appTitle,
      selectedWorkspace: _workspace,
      workspaceCounts: const <WorkspaceView, int>{},
      onWorkspaceSelect: (view) => setState(() => _workspace = view),
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
                      borderRadius: BorderRadius.zero,
                    ),
                    child: Sidebar(
                      appTitle: widget.appTitle,
                      selectedWorkspace: _workspace,
                      workspaceCounts: const <WorkspaceView, int>{},
                      onWorkspaceSelect: (view) {
                        setState(() => _workspace = view);
                        Navigator.of(context).maybePop();
                      },
                    ),
                  ),
            body: Row(
              children: [
                if (isWide) SizedBox(width: 260, child: navigation),
                Expanded(
                  child: TaskPage(
                    appTitle: widget.appTitle,
                    username: widget.username,
                    apiClient: widget.apiClient,
                    userSettings: widget.userSettings,
                    timeTrackingOngoingNotificationEnabled:
                        widget.timeTrackingOngoingNotificationEnabled,
                    onLogout: widget.onLogout,
                    onOpenSettings: widget.onOpenSettings,
                    workspace: _workspace,
                    onOpenNavigation:
                        isWide ? null : () => _scaffoldKey.currentState?.openDrawer(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
