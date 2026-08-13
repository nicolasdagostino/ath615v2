import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_design_tokens.dart';
import '../theme/app_typography.dart';

class AppWeekDateSelector extends StatelessWidget {
  const AppWeekDateSelector({
    super.key,
    required this.days,
    required this.selectedDay,
    required this.weekdayLabel,
    required this.onSelected,
    required this.accentColor,
    this.controller,
    this.itemWidth,
    this.itemSpacing = 0,
    this.itemKey,
    this.selectedKey = const ValueKey('app-selected-day'),
    this.physics,
  });

  final List<DateTime> days;
  final DateTime selectedDay;
  final String Function(DateTime day) weekdayLabel;
  final ValueChanged<DateTime> onSelected;
  final Color accentColor;
  final ScrollController? controller;
  final double? itemWidth;
  final double itemSpacing;
  final Key? Function(DateTime day)? itemKey;
  final Key selectedKey;
  final ScrollPhysics? physics;

  bool _selected(DateTime day) =>
      day.year == selectedDay.year &&
      day.month == selectedDay.month &&
      day.day == selectedDay.day;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const ValueKey('app-week-date-selector'),
    height: 72,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth - AppSpacing.screenX * 2;
        final width = itemWidth ?? availableWidth / 7;
        return ListView.separated(
          controller: controller,
          physics: physics,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenX),
          itemCount: days.length,
          separatorBuilder: (_, _) => SizedBox(width: itemSpacing),
          itemBuilder: (context, index) {
            final day = days[index];
            final selected = _selected(day);
            final label = weekdayLabel(day);
            return GestureDetector(
              key: itemKey?.call(day),
              behavior: HitTestBehavior.opaque,
              onTap: () => onSelected(day),
              child: Semantics(
                selected: selected,
                button: true,
                label: '$label ${day.day}',
                child: SizedBox(
                  width: width,
                  child: Column(
                    children: [
                      Text(
                        label,
                        style: AppTypography.helper(context).copyWith(
                          color: AppColors.textSecondary(context),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.55,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      AnimatedContainer(
                        key: selected ? selectedKey : null,
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected ? accentColor : Colors.transparent,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          day.day.toString(),
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: selected
                                    ? Colors.white
                                    : AppColors.textPrimary(context),
                                fontSize: 18,
                                fontWeight: selected
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                height: 1,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ),
  );
}
