import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_detail_header.dart';
import '../../data/owner_requests_repository.dart';

String requestTypeLabel(String v) => switch (v) {
  'demo' => 'Demos',
  'support' => appStrings.pick('Support', 'Soporte'),
  'other' => appStrings.pick('Other', 'Otras'),
  'new' => appStrings.pick('New', 'Nuevas'),
  _ => appStrings.pick('All', 'Todas'),
};
String requestStatusLabel(String s) => switch (s) {
  'in_progress' => appStrings.pick('In progress', 'En curso'),
  'resolved' => appStrings.pick('Resolved', 'Resuelta'),
  'closed' => appStrings.pick('Closed', 'Cerrada'),
  'contacted' => appStrings.pick('Contacted', 'Contactada'),
  'demo_scheduled' => appStrings.pick('Demo scheduled', 'Demo agendada'),
  'won' => appStrings.pick('Won', 'Ganada'),
  'lost' => appStrings.pick('Lost', 'Perdida'),
  _ => appStrings.pick('New', 'Nueva'),
};
String requestDetailLabel(String key) => switch (key) {
  'full_name' => appStrings.pick('Name', 'Nombre'),
  'email' => 'Email',
  'gym_name' => appStrings.pick('Gym', 'Gimnasio'),
  'created_at' => appStrings.pick('Date', 'Fecha'),
  'locale' => appStrings.pick('Language', 'Idioma'),
  'phone' => appStrings.pick('Phone', 'Teléfono'),
  'approx_member_count' => appStrings.pick(
    'Approximate members',
    'Miembros aproximados',
  ),
  'message' => appStrings.pick('Message', 'Mensaje'),
  'issue_type' => appStrings.pick('Issue type', 'Tipo de problema'),
  'screen_name' => appStrings.pick('Screen', 'Pantalla'),
  'description' => appStrings.pick('Description', 'Descripción'),
  'app_version' => appStrings.pick('App version', 'Versión de la app'),
  'build_number' => 'Build',
  'platform' => appStrings.pick('Platform', 'Plataforma'),
  'os_version' => appStrings.pick('OS version', 'Versión del SO'),
  'subject' => appStrings.pick('Subject', 'Asunto'),
  _ => key,
};
String supportIssueLabel(String value) => switch (value) {
  'login' => appStrings.pick('Login', 'Inicio de sesión'),
  'booking' => appStrings.pick('Bookings', 'Reservas'),
  'memberships' => appStrings.pick('Memberships', 'Membresías'),
  'workouts' => appStrings.pick('Workouts / WOD', 'Entrenamientos / WOD'),
  'notifications' => appStrings.pick('Notifications', 'Notificaciones'),
  'profile' => appStrings.pick('Profile', 'Perfil'),
  'administration' => appStrings.pick('Administration', 'Administración'),
  _ => appStrings.pick('Other', 'Otro'),
};

class OwnerRequestsScreen extends StatefulWidget {
  const OwnerRequestsScreen({super.key, this.repository});
  final OwnerRequestsDataSource? repository;
  @override
  State<OwnerRequestsScreen> createState() => _OwnerRequestsScreenState();
}

class _OwnerRequestsScreenState extends State<OwnerRequestsScreen> {
  String filter = 'all';
  Map<String, dynamic>? data;
  bool loading = true;
  OwnerRequestsDataSource get repo =>
      widget.repository ?? OwnerRequestsRepository(Supabase.instance.client);
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      final d = await repo.list(filter);
      if (mounted) setState(() => data = d);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Widget kpi(String type, dynamic value) => Container(
    key: ValueKey('requests-kpi-$type'),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      border: Border.all(color: AppColors.primary),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      children: [
        Text(
          '${value ?? 0}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        Text(requestTypeLabel(type)),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final counts = Map<String, dynamic>.from(data?['counts'] as Map? ?? {});
    final items = List<Map<String, dynamic>>.from(
      data?['items'] as List? ?? [],
    );
    return Scaffold(
      body: Column(
        children: [
          AppDetailHeader(
            title: appStrings.pick('Requests', 'Solicitudes'),
            onBack: context.pop,
            leadingColor: AppColors.primary,
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: load,
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.screenX),
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      kpi('new', counts['new']),
                      kpi('demo', counts['demo']),
                      kpi('support', counts['support']),
                      kpi('other', counts['other']),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: ['all', 'demo', 'support', 'other', 'new']
                          .map(
                            (f) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                key: ValueKey('requests-filter-$f'),
                                label: Text(requestTypeLabel(f)),
                                selected: filter == f,
                                onSelected: (_) {
                                  filter = f;
                                  load();
                                },
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (loading)
                    const Center(child: CircularProgressIndicator())
                  else
                    ...items.map(
                      (r) => Card(
                        child: ListTile(
                          key: ValueKey(
                            'owner-request-${r['type']}-${r['id']}',
                          ),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => OwnerRequestDetailScreen(
                                type: r['type'].toString(),
                                id: r['id'].toString(),
                                repository: repo,
                              ),
                            ),
                          ),
                          title: Text(
                            '${requestTypeLabel(r['type'].toString())} · ${r['full_name']}',
                          ),
                          subtitle: Text(
                            '${r['gym_name'] ?? ''}\n${r['email']} · ${r['created_at']}',
                          ),
                          isThreeLine: true,
                          trailing: Text(
                            requestStatusLabel(r['status'].toString()),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class OwnerRequestDetailScreen extends StatefulWidget {
  const OwnerRequestDetailScreen({
    super.key,
    required this.type,
    required this.id,
    required this.repository,
  });
  final String type, id;
  final OwnerRequestsDataSource repository;
  @override
  State<OwnerRequestDetailScreen> createState() =>
      _OwnerRequestDetailScreenState();
}

class _OwnerRequestDetailScreenState extends State<OwnerRequestDetailScreen> {
  Map<String, dynamic>? row;
  final notes = TextEditingController();
  String? status, attachmentUrl;
  bool loading = true;
  List<String> get statuses => widget.type == 'demo'
      ? ['new', 'contacted', 'demo_scheduled', 'won', 'lost']
      : ['new', 'in_progress', 'resolved', 'closed'];
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    notes.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final r = await widget.repository.detail(widget.type, widget.id);
    String? url;
    if (r['attachment_path'] != null) {
      url = await widget.repository.signedAttachment(
        r['attachment_path'].toString(),
      );
    }
    if (mounted) {
      setState(() {
        row = r;
        status = r['status'].toString();
        notes.text = r['owner_notes']?.toString() ?? '';
        attachmentUrl = url;
        loading = false;
      });
    }
  }

  Future<void> save() async {
    await widget.repository.update(widget.type, widget.id, status!, notes.text);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            appStrings.pick('Request updated', 'Solicitud actualizada'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        AppDetailHeader(
          title: requestTypeLabel(widget.type),
          onBack: context.pop,
          leadingColor: AppColors.primary,
        ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(AppSpacing.screenX),
                  children: [
                    for (final key in [
                      'full_name',
                      'email',
                      'gym_name',
                      'created_at',
                      'locale',
                      'phone',
                      'approx_member_count',
                      'message',
                      'issue_type',
                      'screen_name',
                      'description',
                      'app_version',
                      'build_number',
                      'platform',
                      'os_version',
                      'subject',
                    ])
                      if (row![key] != null)
                        ListTile(
                          title: Text(requestDetailLabel(key).toUpperCase()),
                          subtitle: Text(
                            key == 'issue_type'
                                ? supportIssueLabel(row![key].toString())
                                : row![key].toString(),
                          ),
                        ),
                    Wrap(
                      children: [
                        if (row!['email'] != null)
                          TextButton.icon(
                            onPressed: () => launchUrl(
                              Uri(
                                scheme: 'mailto',
                                path: row!['email'].toString(),
                              ),
                            ),
                            icon: const Icon(Icons.email_outlined),
                            label: const Text('Email'),
                          ),
                        if (row!['phone'] != null)
                          TextButton.icon(
                            onPressed: () => launchUrl(
                              Uri(
                                scheme: 'tel',
                                path: row!['phone'].toString(),
                              ),
                            ),
                            icon: const Icon(Icons.phone),
                            label: Text(appStrings.pick('Call', 'Llamar')),
                          ),
                      ],
                    ),
                    if (attachmentUrl != null)
                      Image.network(
                        attachmentUrl!,
                        key: const ValueKey('owner-support-attachment'),
                      ),
                    DropdownButtonFormField<String>(
                      key: const ValueKey('owner-request-status'),
                      initialValue: status,
                      items: statuses
                          .map(
                            (s) => DropdownMenuItem(
                              value: s,
                              child: Text(requestStatusLabel(s)),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => status = v),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('owner-request-notes'),
                      controller: notes,
                      maxLength: 4000,
                      maxLines: 5,
                      decoration: InputDecoration(
                        labelText: appStrings.pick(
                          'Internal notes',
                          'Notas internas',
                        ),
                      ),
                    ),
                    FilledButton(
                      key: const ValueKey('owner-request-save'),
                      onPressed: save,
                      child: Text(appStrings.pick('SAVE', 'GUARDAR')),
                    ),
                  ],
                ),
        ),
      ],
    ),
  );
}
