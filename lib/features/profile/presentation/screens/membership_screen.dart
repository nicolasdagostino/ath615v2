import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';

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
  Map<String, dynamic>? _membership;
  List<Map<String, dynamic>> _creditLogs = [];
  bool _loading = true;
  String _selectedTab = 'subscriptions';

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

    final membership = await Supabase.instance.client
        .from('member_memberships')
        .select(
          'id, credits_remaining, expires_at, membership_plans(name, plan_type)',
        )
        .eq('user_id', userId)
        .eq('is_active', true)
        .eq('status', 'active')
        .order('created_at', ascending: false)
        .maybeSingle();

    final logs = await Supabase.instance.client
        .from('membership_credit_logs')
        .select('amount, reason, created_at')
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(8);

    if (!mounted) return;

    setState(() {
      _membership = membership;
      _creditLogs = List<Map<String, dynamic>>.from(logs);
      _loading = false;
    });
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    final date = DateTime.tryParse(raw)?.toLocal();
    if (date == null) return raw;
    return '${date.day}/${date.month}/${date.year}';
  }

  String _creditReasonLabel(String reason) {
    if (reason == 'assigned') return appStrings.assigned;
    if (reason == 'booked') return appStrings.booked;
    if (reason == 'cancelled') return appStrings.cancelled;
    return reason;
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
                else
                  _MembershipCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          appStrings.membershipTitle.toUpperCase(),
                          style: _MembershipText.sectionTitle.copyWith(
                            color: AppColors.textPrimary(context),
                          ),
                        ),
                        const SizedBox(height: 14),

                        Row(
                          children: [
                            Expanded(
                              child: _MembershipTabChip(
                                label: appStrings.subscriptions.toUpperCase(),
                                selected: _selectedTab == 'subscriptions',
                                onTap: () {
                                  setState(() {
                                    _selectedTab = 'subscriptions';
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _MembershipTabChip(
                                label: appStrings.dropIns.toUpperCase(),
                                selected: _selectedTab == 'dropins',
                                onTap: () {
                                  setState(() {
                                    _selectedTab = 'dropins';
                                  });
                                },
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 18),
                        if (_selectedTab == 'subscriptions') ...[
                          Text(
                            appStrings.mySubscription.toUpperCase(),
                            style: _MembershipText.sectionTitle.copyWith(
                              color: AppColors.textPrimary(context),
                            ),
                          ),
                          const SizedBox(height: 14),
                          if (_membership == null ||
                              _membership?['credits_remaining'] != null)
                            Text(
                              appStrings.noActiveSubscription,
                              style: _MembershipText.body.copyWith(
                                color: AppColors.textPrimary(context),
                              ),
                            )
                          else ...[
                            _InfoRow(
                              label: appStrings.activePlan,
                              value:
                                  '${(_membership?['membership_plans'] as Map?)?['name'] ?? appStrings.plan}',
                            ),
                            _InfoRow(
                              label: appStrings.expires,
                              value: _formatDate(
                                _membership?['expires_at']?.toString(),
                              ),
                            ),
                          ],
                          const SizedBox(height: 18),
                          _MembershipActionButton(
                            label: appStrings.getSubscription.toUpperCase(),
                            onPressed: () {
                              context.push(
                                '/available-memberships/subscription',
                              );
                            },
                          ),
                        ] else ...[
                          Text(
                            appStrings.myDropIns.toUpperCase(),
                            style: _MembershipText.sectionTitle.copyWith(
                              color: AppColors.textPrimary(context),
                            ),
                          ),
                          const SizedBox(height: 14),
                          if (_membership == null ||
                              _membership?['credits_remaining'] == null)
                            Text(
                              appStrings.noActiveDropIns,
                              style: _MembershipText.body.copyWith(
                                color: AppColors.textPrimary(context),
                              ),
                            )
                          else ...[
                            _InfoRow(
                              label: appStrings.credits,
                              value:
                                  '${_membership?['credits_remaining'] ?? appStrings.unlimited}',
                            ),
                            _InfoRow(
                              label: appStrings.expires,
                              value: _formatDate(
                                _membership?['expires_at']?.toString(),
                              ),
                            ),
                          ],
                          const SizedBox(height: 18),
                          _MembershipActionButton(
                            label: appStrings.getDropIn.toUpperCase(),
                            onPressed: () {
                              context.push('/available-memberships/dropin');
                            },
                          ),
                          const SizedBox(height: 22),
                          Text(
                            appStrings.creditHistory.toUpperCase(),
                            style: _MembershipText.sectionTitle.copyWith(
                              color: AppColors.textPrimary(context),
                            ),
                          ),
                          const SizedBox(height: 14),
                          if (_creditLogs.isEmpty)
                            Text(
                              appStrings.noCreditHistory,
                              style: _MembershipText.subtle.copyWith(
                                color: AppColors.textSecondary(context),
                              ),
                            )
                          else ...[
                            Row(
                              children: [
                                Expanded(
                                  child: _CreditSummaryChip(
                                    label: appStrings.assigned,
                                    value: _creditLogs
                                        .where(
                                          (log) => log['reason'] == 'assigned',
                                        )
                                        .fold<int>(
                                          0,
                                          (sum, log) =>
                                              sum +
                                              ((log['amount'] as num?) ?? 0)
                                                  .toInt(),
                                        )
                                        .toString(),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _CreditSummaryChip(
                                    label: appStrings.booked,
                                    value: _creditLogs
                                        .where(
                                          (log) => log['reason'] == 'booked',
                                        )
                                        .length
                                        .toString(),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _CreditSummaryChip(
                                    label: appStrings.cancelled,
                                    value: _creditLogs
                                        .where(
                                          (log) => log['reason'] == 'cancelled',
                                        )
                                        .length
                                        .toString(),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Text(
                              appStrings.creditHistory.toUpperCase(),
                              style: _MembershipText.sectionTitle.copyWith(
                                color: AppColors.textPrimary(context),
                              ),
                            ),
                            const SizedBox(height: 14),
                            ..._creditLogs.take(5).map((log) {
                              final amount = ((log['amount'] as num?) ?? 0)
                                  .toInt();

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Container(
                                  padding: const EdgeInsets.fromLTRB(
                                    14,
                                    12,
                                    14,
                                    12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.surface(context),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          _creditReasonLabel(
                                            log['reason']?.toString() ?? '',
                                          ),
                                          style: _MembershipText.title.copyWith(
                                            color: AppColors.textPrimary(
                                              context,
                                            ),
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '${amount > 0 ? '+' : ''}$amount',
                                        style: _MembershipText.title.copyWith(
                                          color: AppColors.textPrimary(context),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        _formatDate(
                                          log['created_at']?.toString(),
                                        ),
                                        style: _MembershipText.subtle.copyWith(
                                          color: AppColors.textSecondary(
                                            context,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                          ],
                        ],
                      ],
                    ),
                  ),
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

class _MembershipTabChip extends StatelessWidget {
  const _MembershipTabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : AppColors.surfaceAlt(context),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.border(context),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.barlowCondensed(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: selected
                ? AppColors.background(context)
                : AppColors.textSecondary(context),
            height: 1,
          ),
        ),
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

class _CreditSummaryChip extends StatelessWidget {
  const _CreditSummaryChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border(context), width: 1),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: _MembershipText.title.copyWith(
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label.toUpperCase(),
            style: _MembershipText.subtle.copyWith(
              color: AppColors.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }
}
