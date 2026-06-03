import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AvailableMembershipsScreen extends StatefulWidget {
  const AvailableMembershipsScreen({
    super.key,
    required this.type,
  });

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
          .select('id, name, plan_type, credits')
          .eq('gym_id', gymId)
          .eq('is_active', true);

      final rows = _isSubscription
          ? await query.isFilter('credits', null).order('created_at')
          : await query.not('credits', 'is', null).order('credits');

      if (!mounted) return;

      setState(() {
        _plans = List<Map<String, dynamic>>.from(rows);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _showRequestMessage(String planName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isSubscription
              ? 'Contact your gym to activate $planName.'
              : 'Contact your gym to activate this drop-in package.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _isSubscription
        ? 'AVAILABLE SUBSCRIPTIONS'
        : 'AVAILABLE DROP-INS';

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF4F5F7),
        elevation: 0,
        title: Text(
          title,
          style: GoogleFonts.barlowCondensed(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
            color: const Color(0xFF111827),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _plans.isEmpty
              ? Center(
                  child: Text(
                    _isSubscription
                        ? 'No subscriptions available.'
                        : 'No drop-ins available.',
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

                    final subtitle = _isSubscription
                        ? 'Unlimited access'
                        : '$credits class ${credits == 1 ? 'credit' : 'credits'}';

                    final action = _isSubscription
                        ? 'REQUEST SUBSCRIPTION'
                        : 'REQUEST DROP-IN';

                    return Container(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name.toUpperCase(),
                              style: _AvailableMembershipText.title),
                          const SizedBox(height: 8),
                          Text(subtitle, style: _AvailableMembershipText.body),
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: FilledButton(
                              onPressed: () => _showRequestMessage(name),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFB59B6A),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
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
    );
  }
}

class _AvailableMembershipText {
  const _AvailableMembershipText._();

  static TextStyle title = GoogleFonts.barlowCondensed(
    fontSize: 22,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.2,
    color: const Color(0xFF111827),
  );

  static TextStyle body = GoogleFonts.barlowCondensed(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: const Color(0xFF384152),
    height: 1.2,
  );
}
