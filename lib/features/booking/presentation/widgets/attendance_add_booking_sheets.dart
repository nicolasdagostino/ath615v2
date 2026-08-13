import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/theme/app_typography.dart';
import '../booking_colors.dart';
import 'class_form_components.dart';

Future<Map<String, dynamic>?> showAttendanceAddMember({
  required BuildContext context,
  required SupabaseClient client,
  required String classId,
  required int bookingCount,
  required int capacity,
}) async {
  if (bookingCount >= capacity) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(appStrings.bookingClassFull)));
    return null;
  }

  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.46),
    builder: (_) => AttendanceAddMemberSheet(client: client, classId: classId),
  );
}

Future<Map<String, dynamic>?> showAttendanceAddGuest({
  required BuildContext context,
  required SupabaseClient client,
  required String classId,
  required int bookingCount,
  required int capacity,
}) async {
  if (capacity > 0 && bookingCount >= capacity) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(appStrings.bookingClassFull)));
    return null;
  }

  final guestName = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.46),
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
      ),
      child: const AttendanceAddGuestSheet(),
    ),
  );
  if (guestName == null || guestName.trim().isEmpty) return null;

  try {
    final inserted = await client
        .from('class_bookings')
        .insert({
          'class_id': classId,
          'user_id': null,
          'guest_name': guestName.trim(),
          'is_guest': true,
          'status': 'booked',
        })
        .select('id, user_id, status, created_at, guest_name, is_guest')
        .single();
    return Map<String, dynamic>.from(inserted);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appStrings.attendanceError(error))),
      );
    }
    return null;
  }
}

class AttendanceAddGuestSheet extends StatefulWidget {
  const AttendanceAddGuestSheet({super.key});

  @override
  State<AttendanceAddGuestSheet> createState() =>
      _AttendanceAddGuestSheetState();
}

class _AttendanceAddGuestSheetState extends State<AttendanceAddGuestSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.background(context),
    borderRadius: const BorderRadius.vertical(
      top: Radius.circular(AppRadii.sheet),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        BookingClassFormHeader(
          title: appStrings.addGuest,
          onClose: () => Navigator.of(context).pop(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenX,
            AppSpacing.md,
            AppSpacing.screenX,
            AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BookingClassSectionLabel(
                label: appStrings.guestName.toUpperCase(),
              ),
              const SizedBox(height: AppSpacing.xs),
              TextField(
                key: const ValueKey('attendance-guest-name'),
                controller: _controller,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
                decoration: bookingClassInput(
                  context,
                  icon: Icons.person_outline_rounded,
                  hintText: appStrings.guestName,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              BookingClassSubmitButton(
                label: appStrings.addGuest,
                loading: false,
                enabled: _controller.text.trim().isNotEmpty,
                onPressed: () =>
                    Navigator.of(context).pop(_controller.text.trim()),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class AttendanceAddMemberSheet extends StatefulWidget {
  const AttendanceAddMemberSheet({
    super.key,
    required this.client,
    required this.classId,
    this.membersLoader,
    this.memberAdder,
  });

  final SupabaseClient? client;
  final String classId;
  final Future<List<Map<String, dynamic>>> Function(String query)?
  membersLoader;
  final Future<Map<String, dynamic>> Function(String userId)? memberAdder;

  @override
  State<AttendanceAddMemberSheet> createState() =>
      _AttendanceAddMemberSheetState();
}

class _AttendanceAddMemberSheetState extends State<AttendanceAddMemberSheet> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _members = [];
  bool _loading = true;
  String? _addingUserId;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _loadMembers('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _loadMembers(value);
    });
  }

  Future<void> _loadMembers(String query) async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final loader = widget.membersLoader;
      final rows = loader != null
          ? await loader(query.trim())
          : List<Map<String, dynamic>>.from(
              await widget.client!.rpc(
                    'search_members_available_for_class',
                    params: {
                      'p_class_id': widget.classId,
                      'p_query': query.trim(),
                    },
                  )
                  as List,
            );
      if (!mounted) return;
      setState(() {
        _members = rows;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _addMember(Map<String, dynamic> member) async {
    final userId = member['user_id']?.toString();
    if (userId == null || _addingUserId != null) return;
    setState(() {
      _addingUserId = userId;
      _error = null;
    });
    try {
      final adder = widget.memberAdder;
      final booking = adder != null
          ? await adder(userId)
          : List<Map<String, dynamic>>.from(
              await widget.client!.rpc(
                    'admin_add_member_to_class',
                    params: {'p_class_id': widget.classId, 'p_user_id': userId},
                  )
                  as List,
            ).first;
      if (!mounted) return;
      Navigator.of(context).pop({'booking': booking, 'member': member});
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _addingUserId = null;
        _error = error;
      });
    }
  }

  String _membershipLabel(Map<String, dynamic> member) {
    final planName =
        member['plan_name']?.toString() ?? appStrings.membershipTitle;
    final credits = member['credits_remaining'] as int?;
    return credits == null
        ? planName
        : '$planName · ${appStrings.creditsLeft(credits)}';
  }

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.background(context),
    borderRadius: const BorderRadius.vertical(
      top: Radius.circular(AppRadii.sheet),
    ),
    clipBehavior: Clip.antiAlias,
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.86,
      child: Column(
        children: [
          BookingClassFormHeader(
            title: appStrings.addMember,
            onClose: () => Navigator.of(context).pop(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenX,
              AppSpacing.sm,
              AppSpacing.screenX,
              AppSpacing.md,
            ),
            child: TextField(
              key: const ValueKey('attendance-member-search'),
              controller: _searchController,
              autofocus: true,
              onChanged: _onSearchChanged,
              decoration: bookingClassInput(
                context,
                icon: Icons.search_rounded,
                hintText: appStrings.searchMembers,
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenX,
                0,
                AppSpacing.screenX,
                AppSpacing.sm,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  appStrings.attendanceError(_error!),
                  style: AppTypography.error(context),
                ),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: BookingColors.primary,
                    ),
                  )
                : _members.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.screenX),
                      child: Text(
                        appStrings.noAvailableMembers,
                        textAlign: TextAlign.center,
                        style: AppTypography.bodySecondary(context),
                      ),
                    ),
                  )
                : ListView.separated(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.screenX,
                    ),
                    itemCount: _members.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: AppColors.border(context)),
                    itemBuilder: (context, index) {
                      final member = _members[index];
                      final userId = member['user_id']?.toString();
                      final name = member['full_name']?.toString().trim();
                      final email = member['email']?.toString().trim();
                      final displayName = name?.isNotEmpty == true
                          ? name!
                          : email?.isNotEmpty == true
                          ? email!
                          : appStrings.member;
                      final adding = _addingUserId == userId;
                      return _MemberRow(
                        name: displayName,
                        metadata: _membershipLabel(member),
                        avatarUrl: member['avatar_url']?.toString(),
                        selected: adding,
                        onTap: adding ? null : () => _addMember(member),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
  );
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.name,
    required this.metadata,
    required this.avatarUrl,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final String metadata;
  final String? avatarUrl;
  final bool selected;
  final VoidCallback? onTap;

  String get initials => name
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .map((part) => part[0].toUpperCase())
      .join();

  @override
  Widget build(BuildContext context) {
    final hasAvatar = avatarUrl?.trim().isNotEmpty == true;
    return Material(
      color: selected
          ? BookingColors.primary.withValues(alpha: 0.08)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Row(
            children: [
              CircleAvatar(
                radius: 19,
                backgroundColor: AppColors.surfaceAlt(context),
                foregroundImage: hasAvatar ? NetworkImage(avatarUrl!) : null,
                child: hasAvatar
                    ? null
                    : Text(
                        initials.isEmpty ? 'M' : initials,
                        style: AppTypography.buttonLabel(
                          context,
                        ).copyWith(color: BookingColors.primary),
                      ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.body(
                        context,
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      metadata,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.helper(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (selected)
                const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: BookingColors.primary,
                  ),
                )
              else
                const Icon(
                  Icons.add_circle_outline_rounded,
                  color: BookingColors.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
