import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_design_tokens.dart';
import '../theme/app_typography.dart';

class AppWeekDateSelector extends StatefulWidget {
  const AppWeekDateSelector({
    super.key,
    required this.days,
    required this.selectedDay,
    required this.weekdayLabel,
    required this.onSelected,
    required this.accentColor,
    this.today,
    this.itemSpacing = 0,
    this.itemKey,
    this.selectedKey = const ValueKey('app-selected-day'),
    this.physics,
    this.onVisibleWeekChanged,
  });

  final List<DateTime> days;
  final DateTime selectedDay;
  final DateTime? today;
  final String Function(DateTime day) weekdayLabel;
  final ValueChanged<DateTime> onSelected;
  final Color accentColor;
  final double itemSpacing;
  final Key? Function(DateTime day)? itemKey;
  final Key selectedKey;
  final ScrollPhysics? physics;
  final ValueChanged<DateTime>? onVisibleWeekChanged;

  @override
  State<AppWeekDateSelector> createState() => _AppWeekDateSelectorState();
}

class _AppWeekDateSelectorState extends State<AppWeekDateSelector> {
  late PageController _controller;

  int get _pageCount => (widget.days.length / 7).ceil();

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  int _pageFor(DateTime date) {
    final index = widget.days.indexWhere((day) => _sameDay(day, date));
    return index < 0 ? 0 : index ~/ 7;
  }

  @override
  void initState() {
    super.initState();
    _controller = PageController(initialPage: _pageFor(widget.selectedDay));
  }

  @override
  void didUpdateWidget(covariant AppWeekDateSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    final daysChanged =
        oldWidget.days.length != widget.days.length ||
        (oldWidget.days.isNotEmpty &&
            widget.days.isNotEmpty &&
            !_sameDay(oldWidget.days.first, widget.days.first));
    final selectionChanged = !_sameDay(
      oldWidget.selectedDay,
      widget.selectedDay,
    );
    if (!daysChanged && !selectionChanged) return;

    final page = _pageFor(widget.selectedDay);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      _controller.animateToPage(
        page,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final today = widget.today ?? DateTime.now();
    return SizedBox(
      key: const ValueKey('app-week-date-selector'),
      height: 72,
      child: PageView.builder(
        key: const ValueKey('app-week-date-pages'),
        controller: _controller,
        physics: widget.physics ?? const PageScrollPhysics(),
        itemCount: _pageCount,
        onPageChanged: (page) {
          final index = page * 7;
          if (index < widget.days.length) {
            widget.onVisibleWeekChanged?.call(widget.days[index]);
          }
        },
        itemBuilder: (context, page) {
          final start = page * 7;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenX),
            child: Row(
              children: List.generate(7, (slot) {
                final index = start + slot;
                if (index >= widget.days.length) {
                  return const Expanded(child: SizedBox.shrink());
                }
                final day = widget.days[index];
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: slot == 6 ? 0 : widget.itemSpacing,
                    ),
                    child: _DayItem(
                      key: widget.itemKey?.call(day),
                      day: day,
                      label: widget.weekdayLabel(day),
                      selected: _sameDay(day, widget.selectedDay),
                      today: _sameDay(day, today),
                      accentColor: widget.accentColor,
                      selectedKey: widget.selectedKey,
                      onTap: () => widget.onSelected(day),
                    ),
                  ),
                );
              }),
            ),
          );
        },
      ),
    );
  }
}

class _DayItem extends StatelessWidget {
  const _DayItem({
    super.key,
    required this.day,
    required this.label,
    required this.selected,
    required this.today,
    required this.accentColor,
    required this.selectedKey,
    required this.onTap,
  });

  final DateTime day;
  final String label;
  final bool selected;
  final bool today;
  final Color accentColor;
  final Key selectedKey;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Semantics(
      selected: selected,
      button: true,
      label: '$label ${day.day}',
      child: Column(
        children: [
          Text(
            label,
            style: AppTypography.helper(context).copyWith(
              color: AppColors.textSecondary(context),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.55,
              height: 1,
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
              border: !selected && today
                  ? Border.all(color: AppColors.border(context), width: 1)
                  : null,
            ),
            child: Text(
              day.day.toString(),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: selected ? Colors.white : AppColors.textPrimary(context),
                fontSize: 18,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
