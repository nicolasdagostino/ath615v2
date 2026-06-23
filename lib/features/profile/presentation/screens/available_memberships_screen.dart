import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';

Color _profileHubBackground(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? const Color(0xFF252525) : const Color(0xFFF1F2F4);
}

class AvailableMembershipsScreen extends StatefulWidget {
  const AvailableMembershipsScreen({super.key, required this.type});

  final String type;

  @override
  State<AvailableMembershipsScreen> createState() =>
      _AvailableMembershipsScreenState();
}

class _AvailableMembershipsScreenState
    extends State<AvailableMembershipsScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _plans = [];

  bool get _isSubscription => widget.type == 'subscription';

  @override
  void initState() {
    super.initState();
    _loadPlans();
  }

  Future<void> _loadPlans() async {
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;

      if (userId == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final profile = await client
          .from('profiles')
          .select('gym_id')
          .eq('id', userId)
          .single();

      final gymId = profile['gym_id']?.toString();

      if (gymId == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final query = client
          .from('membership_plans')
          .select('id, name, plan_type, credits, price, currency')
          .eq('gym_id', gymId)
          .eq('is_active', true);

      final rows = _isSubscription
          ? await query.isFilter('credits', null).order('created_at')
          : await query.not('credits', 'is', null).order('credits');

      if (!mounted) return;

      final plans = List<Map<String, dynamic>>.from(rows)
          .where((p) => (p['name']?.toString().toLowerCase() ?? '') != 'staff')
          .toList();

      setState(() {
        _plans = plans;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<bool> _confirmRequest() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: SafeArea(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
              decoration: BoxDecoration(
                color: AppColors.surface(context),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border(context), width: 1),
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  Text(
                    appStrings.requestMembershipTitle.toUpperCase(),
                    style: _AvailableMembershipText.title,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    appStrings.requestMembershipConfirm,
                    style: _AvailableMembershipText.body,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 54,
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(sheetContext, false),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.textPrimary(context),
                              side: BorderSide(
                                color: AppColors.border(context),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Text(appStrings.cancel.toUpperCase()),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 54,
                          child: FilledButton(
                            onPressed: () => Navigator.pop(sheetContext, true),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              foregroundColor: AppColors.textPrimary(context),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Text(appStrings.request.toUpperCase()),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    return result == true;
  }

  Future<void> _requestPlan(Map<String, dynamic> plan) async {
    final confirmed = await _confirmRequest();

    if (!confirmed) return;

    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;

      if (userId == null) return;

      final profile = await client
          .from('profiles')
          .select('gym_id')
          .eq('id', userId)
          .single();

      final existing = await client
          .from('membership_requests')
          .select('id')
          .eq('user_id', userId)
          .eq('plan_id', plan['id'])
          .eq('status', 'pending')
          .maybeSingle();

      if (existing != null) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(appStrings.membershipRequestAlreadySent)),
        );
        return;
      }

      await client.from('membership_requests').insert({
        'user_id': userId,
        'gym_id': profile['gym_id'],
        'plan_id': plan['id'],
        'status': 'pending',
      });

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.membershipRequestSent)));
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appStrings.membershipRequestError(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _isSubscription
        ? appStrings.availableSubscriptions.toUpperCase()
        : appStrings.availableDropIns.toUpperCase();

    return Scaffold(
      backgroundColor: _profileHubBackground(context),
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 18, 24, 18),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: AppColors.accent,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: GoogleFonts.barlowCondensed(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Container(
              width: double.infinity,
              color: _profileHubBackground(context),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _plans.isEmpty
                  ? Center(
                      child: Text(
                        _isSubscription
                            ? appStrings.noSubscriptionsAvailable
                            : appStrings.noDropInsAvailable,
                        style: _AvailableMembershipText.body,
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
                      itemCount: _plans.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 14),
                      itemBuilder: (context, index) {
                        final plan = _plans[index];
                        final name = plan['name']?.toString() ?? 'Plan';
                        final credits = plan['credits'];
                        final price = plan['price'];

                        final subtitle = _isSubscription
                            ? appStrings.unlimitedAccess
                            : credits == 1
                            ? appStrings.classCredit(credits)
                            : appStrings.classCredits(credits);

                        final action = _isSubscription
                            ? appStrings.requestSubscription.toUpperCase()
                            : appStrings.requestDropIn.toUpperCase();

                        return Container(
                          padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceAlt(context),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AppColors.border(context),
                              width: 1,
                            ),
                            boxShadow: AppShadows.card(context),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name.toUpperCase(),
                                style: _AvailableMembershipText.title,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                price == null
                                    ? appStrings.priceComingSoon.toUpperCase()
                                    : '€$price',
                                style: _AvailableMembershipText.price,
                              ),
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.surface(context),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: AppColors.border(context),
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  subtitle.toUpperCase(),
                                  style: _AvailableMembershipText.body.copyWith(
                                    color: AppColors.accent,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.7,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              SizedBox(
                                width: double.infinity,
                                height: 52,
                                child: FilledButton(
                                  onPressed: () => _requestPlan(plan),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.accent,
                                    foregroundColor: AppColors.background(
                                      context,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  child: Text(action),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AvailableMembershipText {
  const _AvailableMembershipText._();

  static TextStyle title = GoogleFonts.barlowCondensed(
    fontSize: 22,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.2,
    color: Colors.white,
  );

  static TextStyle price = GoogleFonts.barlowCondensed(
    fontSize: 30,
    fontWeight: FontWeight.w800,
    color: AppColors.accent,
    height: 1,
  );

  static TextStyle body = GoogleFonts.barlowCondensed(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: const Color(0xFFABABAB),
    height: 1.2,
  );
}
