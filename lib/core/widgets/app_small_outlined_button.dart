import 'package:flutter/material.dart';

class AppSmallOutlinedButton extends StatelessWidget {
  const AppSmallOutlinedButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final style = OutlinedButton.styleFrom(
      foregroundColor: const Color(0xFF111111),
      side: const BorderSide(color: Color(0xFF111111)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );

    if (icon != null) {
      return OutlinedButton.icon(
        onPressed: onPressed,
        style: style,
        icon: Icon(icon, size: 18),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      );
    }

    return OutlinedButton(
      onPressed: onPressed,
      style: style,
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}
