import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_design_tokens.dart';
import 'app_keyboard_dismissible.dart';

const double appLargeFormSheetHeightFactor = 0.92;
const Duration appLargeFormSheetKeyboardAnimationDuration = Duration(
  milliseconds: 180,
);

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
      final targetKeyboardInset = media.viewInsets.bottom;

      return TweenAnimationBuilder<double>(
        tween: Tween<double>(end: targetKeyboardInset),
        duration: appLargeFormSheetKeyboardAnimationDuration,
        curve: Curves.easeOut,
        builder: (context, keyboardInsetAnimated, _) {
          final availableHeight = (media.size.height - keyboardInsetAnimated)
              .clamp(0.0, media.size.height)
              .toDouble();

          return Padding(
            padding: EdgeInsets.only(bottom: keyboardInsetAnimated),
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
                      child: AppKeyboardDismissible(
                        child: builder(sheetContext),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );
}
