import 'package:flutter/material.dart';
import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_admin_actions.dart';
import '../../domain/member_coach_capability.dart';

class MemberListRow extends StatelessWidget {
  const MemberListRow({
    super.key,
    required this.member,
    required this.onTap,
    required this.onMore,
  });

  final Map<String, dynamic> member;
  final VoidCallback onTap;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final email = (member['email'] ?? '-').toString();
    final name = (member['full_name'] ?? email).toString();
    final role = (member['role'] ?? '-').toString();
    final active = member['is_active'] == true;
    final status =
        (member['invitation_status'] ?? (active ? 'active' : 'disabled'))
            .toString();
    final statusLabel = status == 'pending'
        ? appStrings.pending
        : active
        ? appStrings.active
        : appStrings.inactive;
    final roleLabel = role == 'athlete'
        ? appStrings.athleteRole
        : role == 'coach'
        ? appStrings.coach
        : role == 'admin'
        ? appStrings.adminRole
        : role;
    final capabilities = <String>[
      roleLabel,
      if (memberHasCoachCapability(member) && role != 'coach') appStrings.coach,
    ];
    final membershipName = member['membership_name']?.toString();
    final creditsRemaining = member['credits_remaining'];
    final membershipLabel = membershipName == null || membershipName.isEmpty
        ? null
        : creditsRemaining == null
        ? '$membershipName · ${appStrings.unlimited}'
        : '$membershipName · ${appStrings.creditsCompact(creditsRemaining is num ? creditsRemaining.toInt() : int.tryParse(creditsRemaining.toString()) ?? 0)}';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 88),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.border(context), width: 0.8),
            ),
          ),
          child: Row(
            children: [
              _MemberListAvatar(
                name: name,
                avatarUrl: member['avatar_url']?.toString(),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.itemTitle(context),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.helper(context),
                    ),
                    if (membershipLabel != null) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        membershipLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.helper(context).copyWith(
                          color: AppColors.textPrimary(context),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xxs),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: active
                                ? AppColors.success
                                : AppColors.textSecondary(context),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Flexible(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: statusLabel),
                                for (final capability in capabilities) ...[
                                  const TextSpan(text: ' · '),
                                  TextSpan(
                                    text: capability,
                                    style: TextStyle(
                                      color: capability == appStrings.coach
                                          ? AppColors.primary
                                          : AppColors.textSecondary(context),
                                      fontWeight: capability == appStrings.coach
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.helper(context),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              AppOutlinedAdminButton(
                tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
                icon: Icons.edit_outlined,
                accentColor: AppColors.primary,
                onPressed: onMore,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemberListAvatar extends StatelessWidget {
  const _MemberListAvatar({required this.name, required this.avatarUrl});

  final String name;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final hasAvatar = avatarUrl != null && avatarUrl!.trim().isNotEmpty;

    return ClipOval(
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        color: AppColors.textPrimary(context),
        child: hasAvatar
            ? Image.network(
                avatarUrl!,
                width: 44,
                height: 44,
                fit: BoxFit.cover,
              )
            : Text(
                name.trim().isEmpty ? 'A' : name.trim()[0].toUpperCase(),
                style: AppTypography.itemTitle(context).copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}
