import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';

class MemberFilterChip extends StatelessWidget {
  const MemberFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      selected: selected,
      label: Text(
        label.toUpperCase(),
        style: GoogleFonts.barlowCondensed(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: selected ? Colors.white : AppColors.textSecondary(context),
          height: 1,
        ),
      ),
      selectedColor: AppColors.textPrimary(context),
      backgroundColor: AppColors.surfaceAlt(context),
      side: selected
          ? const BorderSide(color: AppColors.accent, width: 0.8)
          : BorderSide.none,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.input),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      onSelected: (_) => onTap(),
    );
  }
}
