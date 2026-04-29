import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/widgets/app_button.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _inviteEmail = TextEditingController();
  final _search = TextEditingController();

  bool _loading = false;
  bool _loadingMembers = true;
  List<Map<String, dynamic>> _members = [];

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    setState(() => _loadingMembers = true);

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final myProfile = await Supabase.instance.client
          .from('profiles')
          .select('gym_id')
          .eq('id', user.id)
          .single();

      final gymId = myProfile['gym_id'];

      final data = await Supabase.instance.client
          .from('profiles')
          .select(
            'id, full_name, email, role, gym_id, birth_date, is_active, created_at',
          )
          .eq('gym_id', gymId)
          .neq('role', 'owner')
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() => _members = List<Map<String, dynamic>>.from(data));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Load members error: $e')));
    } finally {
      if (mounted) setState(() => _loadingMembers = false);
    }
  }

  Future<void> _inviteAthlete() async {
    setState(() => _loading = true);

    try {
      await Supabase.instance.client.functions.invoke(
        'admin-invite-athlete',
        body: {'email': _inviteEmail.text.trim()},
      );

      if (!mounted) return;

      _inviteEmail.clear();

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Athlete invitation sent')));

      await _loadMembers();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Invite athlete error: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredMembers {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _members;

    return _members.where((m) {
      final name = (m['full_name'] ?? '').toString().toLowerCase();
      final email = (m['email'] ?? '').toString().toLowerCase();
      return name.contains(q) || email.contains(q);
    }).toList();
  }

  void _openMember(Map<String, dynamic> member) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) {
        final email = (member['email'] ?? '-').toString();
        final name = (member['full_name'] ?? email).toString();
        final role = (member['role'] ?? '-').toString();
        final active = member['is_active'] == true;
        final birthDate = member['birth_date']?.toString() ?? 'Not set';

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(email),
                const SizedBox(height: 24),
                _DetailRow(label: 'Role', value: role),
                _DetailRow(
                  label: 'Status',
                  value: active ? 'Active' : 'Inactive',
                ),
                _DetailRow(label: 'Birth date', value: birthDate),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final members = _filteredMembers;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(onPressed: _loadMembers, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Invite athlete',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          const Text('Send an invitation email to a new athlete.'),
          const SizedBox(height: 20),
          TextField(
            controller: _inviteEmail,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Athlete email'),
          ),
          const SizedBox(height: 16),
          AppButton(
            label: 'Invite athlete',
            loading: _loading,
            onPressed: _inviteAthlete,
          ),
          const SizedBox(height: 34),
          const Text(
            'Members',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Search member',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 16),
          if (_loadingMembers)
            const Center(child: CircularProgressIndicator())
          else if (members.isEmpty)
            const Text('No members found.')
          else
            ...members.map(
              (member) =>
                  _MemberTile(member: member, onTap: () => _openMember(member)),
            ),
        ],
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.member, required this.onTap});

  final Map<String, dynamic> member;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final email = (member['email'] ?? '-').toString();
    final name = (member['full_name'] ?? email).toString();
    final role = (member['role'] ?? '-').toString();
    final active = member['is_active'] == true;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        onTap: onTap,
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text('$email\n${active ? 'Active' : 'Inactive'} · $role'),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
