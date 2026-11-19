import 'package:material_ui/material_ui.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../i18n/i18n.dart';
import '../theme/app_theme.dart';

/// DOCKED bottom navigation bar: full-width, solid surface, hairline top
/// border. Five tabs — Home, Search, Manga, Library, Profile. Active tab:
/// orange icon + label + small gradient dot below the label. Inactive:
/// Linear icons in muted; active: Bold icons (`_copy` variants).
class BottomNavBar extends StatelessWidget {
  const BottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  static const List<_NavTab> _tabs = [
    _NavTab(
      labelKey: 'home.title',
      icon: Iconsax.home,
      activeIcon: Iconsax.home_copy,
    ),
    _NavTab(
      labelKey: 'common.search',
      icon: Iconsax.search_normal_copy,
      activeIcon: Iconsax.search_normal_copy,
    ),
    _NavTab(
      labelKey: 'manga.tab',
      icon: Iconsax.book,
      activeIcon: Iconsax.book_copy,
    ),
    _NavTab(
      labelKey: 'library.title',
      icon: Iconsax.bookmark,
      activeIcon: Iconsax.bookmark_copy,
    ),
    _NavTab(
      labelKey: 'profile.title',
      icon: Iconsax.user,
      activeIcon: Iconsax.user_copy,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      padding: EdgeInsets.only(
        top: 8,
        bottom: bottomPadding > 0 ? bottomPadding : 10,
      ),
      child: Row(
        children: [
          for (var i = 0; i < _tabs.length; i++)
            Expanded(child: _buildTab(context, i)),
        ],
      ),
    );
  }

  Widget _buildTab(BuildContext context, int index) {
    final palette = context.palette;
    final tab = _tabs[index];
    final active = index == currentIndex;
    final color = active ? AppColors.brand : palette.muted;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onTap(index),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(active ? tab.activeIcon : tab.icon, size: 24, color: color),
          const SizedBox(height: 4),
          Text(
            tr(context, tab.labelKey),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: active ? AppColors.primaryGradient : null,
              color: active ? null : Colors.transparent,
            ),
          ),
        ],
      ),
    );
  }
}

class _NavTab {
  const _NavTab({
    required this.labelKey,
    required this.icon,
    required this.activeIcon,
  });

  final String labelKey;
  final IconData icon;
  final IconData activeIcon;
}
