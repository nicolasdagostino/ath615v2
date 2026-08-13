import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_design_tokens.dart';

class AppSecondaryActionHeader extends StatelessWidget {
  const AppSecondaryActionHeader({
    super.key,
    required this.onBack,
    this.action,
    this.title,
  });

  final VoidCallback onBack;
  final Widget? action;
  final String? title;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 58,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenX),
          child: Row(
            children: [
              IconButton(
                key: const ValueKey('secondary-header-back'),
                constraints: const BoxConstraints.tightFor(
                  width: kMinInteractiveDimension,
                  height: kMinInteractiveDimension,
                ),
                onPressed: onBack,
                icon: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 19,
                  color: AppColors.textPrimary(context),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: kMinInteractiveDimension,
                height: kMinInteractiveDimension,
                child: action,
              ),
            ],
          ),
        ),
        if (title != null)
          IgnorePointer(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 76),
              child: Text(
                title!.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppColors.textPrimary(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
