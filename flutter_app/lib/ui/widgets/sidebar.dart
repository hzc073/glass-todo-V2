import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/foundation.dart';

import '../../core/app_version.dart';
import '../app_theme.dart';
import '../workspace_view.dart';

class Sidebar extends StatelessWidget {
  const Sidebar({
    super.key,
    required this.appTitle,
    required this.selectedWorkspace,
    required this.workspaceCounts,
    required this.onWorkspaceSelect,
  });

  final String appTitle;
  final WorkspaceView selectedWorkspace;
  final Map<WorkspaceView, int> workspaceCounts;
  final ValueChanged<WorkspaceView> onWorkspaceSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.95),
        border: Border(
          right: BorderSide(color: Theme.of(context).colorScheme.outline, width: 1),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(18, 20, 12, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TitleBlock(appTitle: appTitle),
          const SizedBox(height: 18),
          Expanded(
            child: ListView(
              children: [
                const _SectionLabel(text: '导航'),
                const SizedBox(height: 8),
                ...WorkspaceView.values.map(
                  (view) => _WorkspaceItem(
                    view: view,
                    selected: selectedWorkspace == view,
                    count: workspaceCounts[view] ?? 0,
                    onTap: () => onWorkspaceSelect(view),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (kIsWeb)
            Text(
              AppVersion.web,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.inkSoft,
                    fontWeight: FontWeight.w600,
                  ),
            ),
        ],
      ),
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.appTitle});

  final String appTitle;

  @override
  Widget build(BuildContext context) {
    final titleStyle = GoogleFonts.fraunces(
      textStyle: Theme.of(context).textTheme.headlineMedium,
      fontWeight: FontWeight.w600,
      color: AppColors.ink,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [AppColors.accent, AppColors.accentCool],
          ).createShader(bounds),
          child: Text(appTitle, style: titleStyle.copyWith(color: Colors.white)),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: AppColors.inkSoft,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
          ),
    );
  }
}

class _WorkspaceItem extends StatelessWidget {
  const _WorkspaceItem({
    required this.view,
    required this.selected,
    required this.count,
    required this.onTap,
  });

  final WorkspaceView view;
  final bool selected;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final showCount = count > 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: selected
              ? const BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: AppColors.accent,
                      width: 3,
                    ),
                  ),
                )
              : null,
          child: Row(
            children: [
              Icon(
                view.icon,
                size: 17,
                color: selected ? AppColors.accentDeep : AppColors.inkSoft,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  view.label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: selected ? AppColors.accentDeep : AppColors.ink,
                      ),
                ),
              ),
              if (showCount) ...[
                const SizedBox(width: 8),
                Text(
                  count.toString(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: selected ? AppColors.accentDeep : AppColors.inkSoft,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
