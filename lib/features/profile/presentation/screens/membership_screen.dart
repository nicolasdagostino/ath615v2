import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/strings/app_strings.dart';

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
      backgroundColor: const Color(0xFFF4F5F7),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                ),
                const SizedBox(width: 8),
                Text(appStrings.membershipTitle, style: _MembershipText.header),
              ],
            ),
            const SizedBox(height: 20),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else
              _MembershipCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appStrings.membershipTitle.toUpperCase(),
                      style: _MembershipText.sectionTitle,
                    ),
                    const SizedBox(height: 14),

                    SizedBox(
                      height: 48,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          ChoiceChip(
                            selected: _selectedTab == 'subscriptions',
                            label: Text(
                              'SUBSCRIPTIONS',
                              style: GoogleFonts.barlowCondensed(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                                color: _selectedTab == 'subscriptions'
                                    ? Colors.white
                                    : const Color(0xFF8F96A3),
                                height: 1.0,
                              ),
                            ),
                            selectedColor: const Color(0xFFB59B6A),
                            backgroundColor: Colors.white,
                            side: BorderSide.none,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                            ),
                            onSelected: (_) {
                              setState(() {
                                _selectedTab = 'subscriptions';
                              });
                            },
                          ),
                          const SizedBox(width: 10),
                          ChoiceChip(
                            selected: _selectedTab == 'dropins',
                            label: Text(
                              'DROP-INS',
                              style: GoogleFonts.barlowCondensed(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                                color: _selectedTab == 'dropins'
                                    ? Colors.white
                                    : const Color(0xFF8F96A3),
                                height: 1.0,
                              ),
                            ),
                            selectedColor: const Color(0xFFB59B6A),
                            backgroundColor: Colors.white,
                            side: BorderSide.none,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                            ),
                            onSelected: (_) {
                              setState(() {
                                _selectedTab = 'dropins';
                              });
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),
                    if (_selectedTab == 'subscriptions') ...[
                      Text('MY SUBSCRIPTION', style: _MembershipText.sectionTitle),
                      const SizedBox(height: 14),
                      if (_membership == null ||
                          _membership?['credits_remaining'] != null)
                        Text(
                          'You have no active subscription.',
                          style: _MembershipText.body,
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
                        label: 'GET SUBSCRIPTION',
                        onPressed: () {
                          context.push(
                            '/available-memberships/subscription',
                          );
                        },
                      ),
                    ] else ...[
                      Text('MY DROP-INS', style: _MembershipText.sectionTitle),
                      const SizedBox(height: 14),
                      if (_membership == null ||
                          _membership?['credits_remaining'] == null)
                        Text(
                          'You have no active drop-ins.',
                          style: _MembershipText.body,
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
                        label: 'GET DROP-IN',
                        onPressed: () {
                          context.push(
                            '/available-memberships/dropin',
                          );
                        },
                      ),
                      const SizedBox(height: 22),
                      Text(
                        appStrings.creditHistory.toUpperCase(),
                        style: _MembershipText.sectionTitle,
                      ),
                      const SizedBox(height: 14),
                      if (_creditLogs.isEmpty)
                        Text(
                          appStrings.noCreditHistory,
                          style: _MembershipText.subtle,
                        )
                      else ...[
                      Row(
                        children: [
                          Expanded(
                            child: _CreditSummaryChip(
                              label: appStrings.assigned,
                              value: _creditLogs
                                  .where((log) => log['reason'] == 'assigned')
                                  .fold<int>(
                                    0,
                                    (sum, log) =>
                                        sum +
                                        ((log['amount'] as num?) ?? 0).toInt(),
                                  )
                                  .toString(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _CreditSummaryChip(
                              label: appStrings.booked,
                              value: _creditLogs
                                  .where((log) => log['reason'] == 'booked')
                                  .length
                                  .toString(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _CreditSummaryChip(
                              label: appStrings.cancelled,
                              value: _creditLogs
                                  .where((log) => log['reason'] == 'cancelled')
                                  .length
                                  .toString(),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'MEMBERSHIP HISTORY',
                        style: _MembershipText.sectionTitle,
                      ),
                      const SizedBox(height: 14),
                      ..._creditLogs.take(5).map((log) {
                        final amount = ((log['amount'] as num?) ?? 0).toInt();

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF7F8FA),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _creditReasonLabel(
                                      log['reason']?.toString() ?? '',
                                    ),
                                    style: _MembershipText.title,
                                  ),
                                ),
                                Text(
                                  '${amount > 0 ? '+' : ''}$amount',
                                  style: _MembershipText.title,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  _formatDate(log['created_at']?.toString()),
                                  style: _MembershipText.subtle,
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
      ),
    );
  }
}



class _MembershipActionButton extends StatelessWidget {
  const _MembershipActionButton({
    required this.label,
    required this.onPressed,
  });

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
          backgroundColor: const Color(0xFFB59B6A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
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
    fontSize: 30,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.3,
    color: const Color(0xFF111827),
  );

  static TextStyle title = GoogleFonts.barlowCondensed(
    fontSize: 18,
    fontWeight: FontWeight.w800,
    color: const Color(0xFF0E0E11),
    letterSpacing: -0.3,
    height: 1.0,
  );

  static TextStyle sectionTitle = GoogleFonts.barlowCondensed(
    fontSize: 13,
    fontWeight: FontWeight.w800,
    color: const Color(0xFF0E0E11),
    letterSpacing: 0.8,
    height: 1.0,
  );

  static TextStyle body = GoogleFonts.barlowCondensed(
    color: const Color(0xFF384152),
    fontSize: 16,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.0,
    height: 1.3,
  );

  static TextStyle subtle = GoogleFonts.barlowCondensed(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: const Color(0xFF8F96A3),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
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
            child: Text(label.toUpperCase(), style: _MembershipText.subtle),
          ),
          const SizedBox(width: 12),
          Text(value, style: _MembershipText.body),
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
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Text(value, style: _MembershipText.title),
          const SizedBox(height: 4),
          Text(label.toUpperCase(), style: _MembershipText.subtle),
        ],
      ),
    );
  }
}
