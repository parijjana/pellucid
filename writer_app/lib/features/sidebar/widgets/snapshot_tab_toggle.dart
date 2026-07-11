// Description: Low-contrast Cloud/Local segmented toggle for SnapshotManagementDialog.

import 'package:flutter/material.dart';
import '../../editor/providers/theme_provider.dart';
import 'snapshot_tab.dart';

class SnapshotTabToggle extends StatelessWidget {
  final SnapshotTab activeTab;
  final WriterTheme theme;
  final ValueChanged<SnapshotTab> onChanged;

  const SnapshotTabToggle({
    super.key,
    required this.activeTab,
    required this.theme,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: theme.foregroundColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.foregroundColor.withValues(alpha: 0.08)),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          _TabSegment(
            label: 'Cloud',
            icon: Icons.cloud_outlined,
            isActive: activeTab == SnapshotTab.cloud,
            theme: theme,
            onTap: () => onChanged(SnapshotTab.cloud),
          ),
          _TabSegment(
            label: 'Local',
            icon: Icons.save_outlined,
            isActive: activeTab == SnapshotTab.local,
            theme: theme,
            onTap: () => onChanged(SnapshotTab.local),
          ),
        ],
      ),
    );
  }
}

class _TabSegment extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final WriterTheme theme;
  final VoidCallback onTap;

  const _TabSegment({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isActive ? theme.foregroundColor.withValues(alpha: 0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: theme.foregroundColor.withValues(alpha: isActive ? 0.8 : 0.35)),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: theme.foregroundColor.withValues(alpha: isActive ? 0.9 : 0.35),
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
