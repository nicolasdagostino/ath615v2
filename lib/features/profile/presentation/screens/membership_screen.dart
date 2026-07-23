import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import 'package:intl/intl.dart';

Color _profileHubBackground(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? const Color(0xFF252525) : const Color(0xFFF1F2F4);
}

class MembershipScreen extends StatefulWidget {
  const MembershipScreen({super.key});

  @override
  State<MembershipScreen> createState() => _MembershipScreenState();
}

class _MembershipScreenState extends State<MembershipScreen> {
  static const int _membershipsPageSize = 5;

  List<Map<String, dynamic>> _memberships = [];
  bool _loading = true;
  int _visibleMembershipCount = _membershipsPageSize;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final membershipRows = await Supabase.instance.client
        .from('member_memberships')
        .select(
          'id, credits_remaining, starts_at, expires_at, status, is_active, '
          'created_at, membership_plans(name, plan_type, credits)',
        )
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    if (!mounted) return;

    setState(() {
      _memberships = List<Map<String, dynamic>>.from(membershipRows);
      _visibleMembershipCount = _membershipsPageSize;
      _loading = false;
    });
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    final date = DateTime.tryParse(raw)?.toLocal();
    if (date == null) return raw;
    return '${date.day}/${date.month}/${date.year}';
  }

  String _statusLabel(String? status) {
    switch (status) {
      case 'active':
        return appStrings.active;
      case 'scheduled':
        return appStrings.scheduled;
      case 'exhausted':
        return appStrings.exhausted;
      case 'expired':
        return appStrings.expired;
      case 'cancelled':
        return appStrings.cancelled;
      case 'replaced':
        return appStrings.replaced;
      default:
        return status ?? '-';
    }
  }

  IconData _statusIcon(String? status) {
    switch (status) {
      case 'active':
        return Icons.check_circle_rounded;
      case 'scheduled':
        return Icons.schedule_rounded;
      case 'exhausted':
        return Icons.inventory_2_rounded;
      case 'expired':
        return Icons.event_busy_rounded;
      case 'cancelled':
        return Icons.cancel_rounded;
      case 'replaced':
        return Icons.swap_horiz_rounded;
      default:
        return Icons.card_membership_rounded;
    }
  }

  Color _statusColor(BuildContext context, String? status) {
    switch (status) {
      case 'active':
        return const Color(0xFF2EAD68);
      case 'scheduled':
        return const Color(0xFF3A7BD5);
      case 'exhausted':
        return const Color(0xFFE09B2D);
      case 'expired':
      case 'cancelled':
      case 'replaced':
        return AppColors.textSecondary(context);
      default:
        return AppColors.accent;
    }
  }

  Map<String, dynamic> _planOf(Map<String, dynamic> membership) {
    final plan = membership['membership_plans'];
    return plan is Map ? Map<String, dynamic>.from(plan) : <String, dynamic>{};
  }

  String _planName(Map<String, dynamic> membership) {
    return _planOf(membership)['name']?.toString() ?? appStrings.plan;
  }

  String _formatClassDateTimeLong(String? value) {
    if (value == null || value.isEmpty) return '—';

    final dt = DateTime.tryParse(value);
    if (dt == null) return '—';

    return DateFormat('d MMM yyyy · HH:mm').format(dt.toLocal());
  }

  String _creditsLabel(Map<String, dynamic> membership) {
    final remaining = membership['credits_remaining'];
    if (remaining == null) return appStrings.unlimited;

    final planCredits = _planOf(membership)['credits'];
    if (planCredits == null) return remaining.toString();

    return '$remaining / $planCredits';
  }

  Future<void> _openMembershipDetails(Map<String, dynamic> membership) async {
    final status = membership['status']?.toString();

    final activity = await Supabase.instance.client
        .from('class_bookings')
        .select('id,status,classes(title,starts_at)')
        .eq('membership_id', membership['id'])
        .eq('status', 'attended')
        .order('created_at', ascending: false);

    if (!mounted) return;

    final rows = List<Map<String, dynamic>>.from(activity);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.fromLTRB(22, 16, 22, 28),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt(sheetContext),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: AppColors.border(sheetContext),
                width: 1,
              ),
              boxShadow: AppShadows.card(sheetContext),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border(sheetContext),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: _statusColor(
                          sheetContext,
                          status,
                        ).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Icon(
                        _statusIcon(status),
                        color: _statusColor(sheetContext, status),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _planName(membership),
                            style: _MembershipText.title.copyWith(
                              color: AppColors.textPrimary(sheetContext),
                              fontSize: 27,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            _statusLabel(status).toUpperCase(),
                            style: _MembershipText.sectionTitle.copyWith(
                              color: _statusColor(sheetContext, status),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _InfoRow(
                  label: appStrings.purchased,
                  value: _formatDate(membership['created_at']?.toString()),
                ),
                _InfoRow(
                  label: appStrings.starts,
                  value: _formatDate(membership['starts_at']?.toString()),
                ),
                _InfoRow(
                  label: appStrings.expires,
                  value: _formatDate(membership['expires_at']?.toString()),
                ),
                _InfoRow(
                  label: appStrings.credits,
                  value: _creditsLabel(membership),
                ),

                const SizedBox(height: 28),

                Text(
                  'CLASES ASISTIDAS',
                  style: _MembershipText.sectionTitle.copyWith(
                    color: AppColors.textSecondary(sheetContext),
                  ),
                ),

                const SizedBox(height: 14),

                if (rows.isEmpty)
                  Text(
                    'Todavía no hay clases asistidas con esta membresía.',
                    style: _MembershipText.body.copyWith(
                      color: AppColors.textSecondary(sheetContext),
                    ),
                  )
                else
                  ...rows.map((booking) {
                    final klass = booking['classes'] as Map<String, dynamic>?;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            klass?['title']?.toString() ??
                                appStrings.classFallback,
                            style: _MembershipText.body.copyWith(
                              color: AppColors.textPrimary(sheetContext),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                Icons.calendar_today_outlined,
                                size: 14,
                                color: AppColors.textSecondary(sheetContext),
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  _formatClassDateTimeLong(
                                    klass?['starts_at']?.toString(),
                                  ),
                                  style: _MembershipText.subtle.copyWith(
                                    color: AppColors.textSecondary(
                                      sheetContext,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Divider(
                            height: 1,
                            thickness: 0.5,
                            color: AppColors.border(sheetContext),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _profileHubBackground(context),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => context.pop(),
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 20,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    appStrings.membershipTitle,
                    style: _MembershipText.header.copyWith(
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                ],
              ),
            ),
            _MembershipMenuSection(
              children: [
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  _MembershipCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          appStrings.myMemberships.toUpperCase(),
                          style: _MembershipText.sectionTitle.copyWith(
                            color: AppColors.textPrimary(context),
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (_memberships.isEmpty) ...[
                          Text(
                            appStrings.noMembershipHistory,
                            style: _MembershipText.title.copyWith(
                              color: AppColors.textPrimary(context),
                              fontSize: 24,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            appStrings.choosePlanToBookClasses,
                            style: _MembershipText.body.copyWith(
                              color: AppColors.textSecondary(context),
                            ),
                          ),
                        ] else
                          ..._memberships.take(_visibleMembershipCount).map((
                            membership,
                          ) {
                            final status = membership['status']?.toString();

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () =>
                                      _openMembershipDetails(membership),
                                  borderRadius: BorderRadius.circular(16),
                                  child: Container(
                                    padding: const EdgeInsets.fromLTRB(
                                      14,
                                      14,
                                      12,
                                      14,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.surface(context),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: AppColors.border(context),
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 44,
                                          height: 44,
                                          decoration: BoxDecoration(
                                            color: _statusColor(
                                              context,
                                              status,
                                            ).withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                          child: Icon(
                                            _statusIcon(status),
                                            color: _statusColor(
                                              context,
                                              status,
                                            ),
                                            size: 22,
                                          ),
                                        ),
                                        const SizedBox(width: 13),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                _planName(membership),
                                                style: _MembershipText.title
                                                    .copyWith(
                                                      color:
                                                          AppColors.textPrimary(
                                                            context,
                                                          ),
                                                      fontSize: 20,
                                                    ),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                '${_formatDate(membership['starts_at']?.toString())}'
                                                ' — '
                                                '${_formatDate(membership['expires_at']?.toString())}',
                                                style: _MembershipText.subtle
                                                    .copyWith(
                                                      color:
                                                          AppColors.textSecondary(
                                                            context,
                                                          ),
                                                    ),
                                              ),
                                              const SizedBox(height: 5),
                                              Text(
                                                '${_statusLabel(status).toUpperCase()}'
                                                '  ·  '
                                                '${_creditsLabel(membership)}',
                                                style: _MembershipText
                                                    .sectionTitle
                                                    .copyWith(
                                                      color: _statusColor(
                                                        context,
                                                        status,
                                                      ),
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Icon(
                                          Icons.chevron_right_rounded,
                                          color: AppColors.textSecondary(
                                            context,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        if (_visibleMembershipCount < _memberships.length) ...[
                          const SizedBox(height: 2),
                          _MembershipSecondaryButton(
                            label: appStrings.showMore.toUpperCase(),
                            onPressed: () {
                              setState(() {
                                _visibleMembershipCount =
                                    (_visibleMembershipCount +
                                            _membershipsPageSize)
                                        .clamp(0, _memberships.length);
                              });
                            },
                          ),
                          const SizedBox(height: 14),
                        ] else
                          const SizedBox(height: 6),
                        _MembershipActionButton(
                          label: appStrings.getSubscription.toUpperCase(),
                          onPressed: () {
                            context.push('/available-memberships/subscription');
                          },
                        ),
                        const SizedBox(height: 10),
                        _MembershipActionButton(
                          label: appStrings.getDropIn.toUpperCase(),
                          onPressed: () {
                            context.push('/available-memberships/dropin');
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MembershipMenuSection extends StatelessWidget {
  const _MembershipMenuSection({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(
        minHeight: MediaQuery.of(context).size.height * 0.72,
      ),
      color: _profileHubBackground(context),
      padding: const EdgeInsets.fromLTRB(24, 34, 24, 72),
      child: Column(children: children),
    );
  }
}

class _MembershipSecondaryButton extends StatelessWidget {
  const _MembershipSecondaryButton({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary(context),
          side: BorderSide(color: AppColors.border(context), width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

class _MembershipActionButton extends StatelessWidget {
  const _MembershipActionButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

class _MembershipText {
  const _MembershipText._();

  static TextStyle header = GoogleFonts.barlowCondensed(
    fontSize: 22,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.3,
    color: Colors.white,
  );

  static TextStyle title = GoogleFonts.barlowCondensed(
    fontSize: 18,
    fontWeight: FontWeight.w800,
    color: Colors.white,
    letterSpacing: -0.3,
    height: 1.0,
  );

  static TextStyle sectionTitle = GoogleFonts.barlowCondensed(
    fontSize: 13,
    fontWeight: FontWeight.w800,
    color: Colors.white,
    letterSpacing: 0.8,
    height: 1.0,
  );

  static TextStyle body = GoogleFonts.barlowCondensed(
    color: Colors.white,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.0,
    height: 1.3,
  );

  static TextStyle subtle = GoogleFonts.barlowCondensed(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: const Color(0xFFABABAB),
    letterSpacing: 0.3,
    height: 1.0,
  );
}

class _MembershipCard extends StatelessWidget {
  const _MembershipCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border(context), width: 1),
        boxShadow: AppShadows.card(context),
      ),
      child: child,
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: _MembershipText.subtle.copyWith(
                color: AppColors.textSecondary(context),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: _MembershipText.body.copyWith(
              color: AppColors.textPrimary(context),
            ),
          ),
        ],
      ),
    );
  }
}
