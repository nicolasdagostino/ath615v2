import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_design_tokens.dart';
import 'app_keyboard_dismissible.dart';

const double appLargeFormSheetHeightFactor = 0.92;

Future<T?> showAppLargeFormSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: barrierDismissible,
    enableDrag: barrierDismissible,
    useSafeArea: false,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.52),
    builder: (sheetContext) {
      final media = MediaQuery.of(sheetContext);
      final availableHeight = media.size.height - media.viewInsets.bottom;

      return AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            height: availableHeight * appLargeFormSheetHeightFactor,
            width: double.infinity,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppRadii.sheet),
              ),
              child: Material(
                key: const ValueKey('app-large-form-sheet'),
                color: AppColors.background(sheetContext),
                child: MediaQuery.removePadding(
                  context: sheetContext,
                  removeTop: true,
                  child: AppKeyboardDismissible(child: builder(sheetContext)),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
