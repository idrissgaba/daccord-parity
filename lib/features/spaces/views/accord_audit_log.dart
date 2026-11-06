import 'package:bonfire/theme/app_icons.dart';
import 'dart:async';
import 'package:bonfire/shared/components/async_state_views.dart';
import 'package:bonfire/shared/components/load_more_footer.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/responsive_dialog.dart';
import 'package:bonfire/shared/utils/self_loading_list.dart';
import 'package:bonfire/shared/utils/string_ext.dart';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/features/spaces/utils/message_time.dart';
import 'package:bonfire/features/spaces/views/accord_space_settings.dart';
import 'package:bonfire/shared/components/settings_controls.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the audit-log dialog for [spaceId], listing recent moderation/admin
/// actions. Caller is responsible for gating on the `view_audit_log` permission.
Future<void> showAccordAuditLog(
  BuildContext context, {
  required String spaceId,
}) {
  return showAccordSpaceSettings(
    context,
    spaceId: spaceId,
    page: SpaceSettingsPages.auditLog,
  );
}

const _pageSize = 25;

/// Server Settings › Audit Log: the log as a page — "Audit Log" with the
/// Filter by User / Filter by Action selects, one card per entry.
class AuditLogSettingsPage extends StatelessWidget {
  const AuditLogSettingsPage({super.key, required this.spaceId});

  final String spaceId;

  @override
  Widget build(BuildContext context) =>
      _AuditLogDialog(spaceId: spaceId, embedded: true);
}

class _AuditLogDialog extends ConsumerStatefulWidget {
  const _AuditLogDialog({required this.spaceId, this.embedded = false});

  final String spaceId;
  final bool embedded;

  @override
  ConsumerState<_AuditLogDialog> createState() => _AuditLogDialogState();
}

class _AuditLogDialogState extends ConsumerState<_AuditLogDialog>
    with PaginatedListState<AccordAuditLogEntry, _AuditLogDialog> {
  String? _actionFilter; // null = all
  String _userQuery = '';
  String? _userFilter; // the page's Filter by User; null = all
  StreamSubscription<Map<String, dynamic>>? _liveSub;

  @override
  void initState() {
    super.initState(); // kicks off the mixin's initial load()
    _subscribeLive();
  }

  @override
  void dispose() {
    _liveSub?.cancel();
    super.dispose();
  }

  AccordClient? get _client => ref.accordClient;

  void _subscribeLive() {
    final client = _client;
    if (client == null) return;
    _liveSub = client.onAuditLogCreate.listen((data) {
      // The gateway may scope the event with a space id; only prepend ours.
      final spaceId = data['space_id']?.toString();
      if (spaceId != null && spaceId != widget.spaceId) return;
      final entry = AccordAuditLogEntry.fromJson(data);
      if (entry.id.isNotEmpty && items.any((e) => e.id == entry.id)) return;
      if (!mounted) return;
      setState(() => items.insert(0, entry));
    });
  }

  @override
  int get pageSize => _pageSize;

  @override
  bool get canLoad => _client != null;

  @override
  String? itemId(AccordAuditLogEntry item) => item.id;

  @override
  Future<RestResult> fetchPage({String? before}) => _client!.auditLogs.list(
    widget.spaceId,
    query: {'limit': _pageSize, if (before != null) 'before': before},
  );

  @override
  String loadError(RestResult result) => 'Failed to load audit log';

  @override
  String loadMoreError(RestResult result) => 'Failed to load more entries';

  /// The endpoint returns raw JSON; entries may be a bare list or wrapped under
  /// `entries`/`audit_log_entries`.
  @override
  List<AccordAuditLogEntry> parseItems(Object? data) {
    List<dynamic>? raw;
    if (data is List) {
      raw = data;
    } else if (data is Map) {
      raw = (data['entries'] ?? data['audit_log_entries']) as List<dynamic>?;
    }
    if (raw == null) return const [];
    return [
      for (final e in raw)
        if (e is Map<String, dynamic>) AccordAuditLogEntry.fromJson(e),
    ];
  }

  String _actionLabel(String actionType) =>
      actionType.isEmpty ? 'Action' : titleCaseFromToken(actionType);

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    final serverKey = ref.readActiveServerKey() ?? '';
    final members = ref.watch(
      accordMembersControllerProvider(serverKey, widget.spaceId),
    );
    final users = ref.watch(accordUsersControllerProvider(serverKey));
    final ensureUser = ref
        .read(accordUsersControllerProvider(serverKey).notifier)
        .ensure;

    // Distinct action types present, for the filter dropdown.
    final actionTypes = <String>{
      for (final e in items)
        if (e.actionType.isNotEmpty) e.actionType,
    }.toList()..sort();

    final query = _userQuery.trim().toLowerCase();
    final visible = items.where((e) {
      if (_actionFilter != null && e.actionType != _actionFilter) return false;
      if (query.isNotEmpty) {
        final actor = accordAuthorName(
          e.userId,
          members: members,
          users: users,
          ensure: ensureUser,
        ).toLowerCase();
        if (!actor.contains(query)) return false;
      }
      return true;
    }).toList();

    if (widget.embedded) {
      final actors = <String>{for (final e in items) e.userId}.toList();
      final rows = _userFilter == null
          ? visible
          : visible.where((e) => e.userId == _userFilter).toList();
      String actorOf(String id) => accordAuthorName(
        id,
        members: members,
        users: users,
        ensure: ensureUser,
      );
      Widget filter(String label, Widget select) => SizedBox(
        width: 222,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [SettingsFieldLabel(label), select],
        ),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Audit Log',
                    style: SettingsText.pageTitle(colors),
                  ),
                ),
              ),
              filter(
                'Filter by User',
                AccordSelect<String?>(
                  key: const Key('audit-filter-user'),
                  value: _userFilter,
                  options: [
                    const AccordSelectOption(null, 'All Users'),
                    for (final id in actors)
                      AccordSelectOption(id, actorOf(id)),
                  ],
                  onChanged: (v) => setState(() => _userFilter = v),
                ),
              ),
              const SizedBox(width: 16),
              filter(
                'Filter by Action',
                AccordSelect<String?>(
                  key: const Key('audit-filter-action'),
                  value: _actionFilter,
                  options: [
                    const AccordSelectOption(null, 'All Actions'),
                    for (final a in actionTypes)
                      AccordSelectOption(a, _actionLabel(a)),
                  ],
                  onChanged: (v) => setState(() => _actionFilter = v),
                ),
              ),
            ],
          ),
          const SettingsDivider(top: 20, bottom: 20),
          Expanded(
            child: error != null && items.isEmpty
                ? Center(child: Text(error!, style: theme.textTheme.bodyMedium))
                : loading
                ? const LoadingView()
                : rows.isEmpty
                ? Center(
                    child: Text(
                      'No logs yet',
                      style: SettingsText.description(colors),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 40),
                    itemCount: rows.length + (hasMore ? 1 : 0),
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      if (index >= rows.length) {
                        return LoadMoreFooter(
                          loading: loadingMore,
                          onPressed: loadMore,
                          padding: const EdgeInsets.all(12),
                        );
                      }
                      final entry = rows[index];
                      return _AuditRow(
                        actor: actorOf(entry.userId),
                        action: _actionLabel(entry.actionType),
                        reason: entry.reason,
                        when: entry.createdAt.isEmpty
                            ? null
                            : messageTimeFromIso(entry.createdAt),
                      );
                    },
                  ),
          ),
        ],
      );
    }
    return Dialog(
      child: ConstrainedBox(
        constraints: dialogConstraints(context, maxWidth: 520, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Icon(AppIcons.history, size: 18, color: colors.dirtyWhite),
                  const SizedBox(width: 8),
                  Text('Audit log', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: loading ? null : load,
                    icon: const Icon(AppIcons.refresh, size: 18),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(AppIcons.close, size: 18),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      initialValue: _actionFilter,
                      decoration: const InputDecoration(
                        labelText: 'Action',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('All actions'),
                        ),
                        for (final a in actionTypes)
                          DropdownMenuItem(
                            value: a,
                            child: Text(_actionLabel(a)),
                          ),
                      ],
                      onChanged: (v) => setState(() => _actionFilter = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(
                        labelText: 'User',
                        isDense: true,
                        prefixIcon: Icon(AppIcons.search, size: 18),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => setState(() => _userQuery = v),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: error != null && items.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Text(error!, style: theme.textTheme.bodyMedium),
                      ),
                    )
                  : loading
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: LoadingView(),
                    )
                  : visible.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Text(
                          'No matching entries',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(8),
                      itemCount: visible.length + (hasMore ? 1 : 0),
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        if (index >= visible.length) {
                          return LoadMoreFooter(
                            loading: loadingMore,
                            onPressed: loadMore,
                            padding: const EdgeInsets.all(12),
                          );
                        }
                        final entry = visible[index];
                        final actorName = accordAuthorName(
                          entry.userId,
                          members: members,
                          users: users,
                          ensure: ensureUser,
                        );
                        return ListTile(
                          leading: Icon(
                            AppIcons.bolt,
                            size: 18,
                            color: colors.gray,
                          ),
                          title: Text(
                            _actionLabel(entry.actionType),
                            style: theme.textTheme.titleSmall,
                          ),
                          subtitle: Text(
                            entry.reason.isEmpty
                                ? 'by $actorName'
                                : 'by $actorName — ${entry.reason}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One entry as the reference client's card: the action glyph, who did it,
/// what, and when.
class _AuditRow extends StatelessWidget {
  const _AuditRow({
    required this.actor,
    required this.action,
    required this.reason,
    required this.when,
  });

  final String actor;
  final String action;
  final String reason;
  final String? when;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.hairline),
      ),
      child: Row(
        children: [
          Icon(AppIcons.listAltOutlined, size: 20, color: colors.interactive),
          const SizedBox(width: 12),
          CircleAvatar(
            radius: 16,
            backgroundColor: colors.darkGray,
            child: Text(
              accordInitial(actor),
              style: TextStyle(color: colors.dirtyWhite, fontSize: 14),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: actor,
                        style: TextStyle(color: colors.dirtyWhite),
                      ),
                      TextSpan(text: ' ${action.toLowerCase()}'),
                      if (reason.isNotEmpty) TextSpan(text: ' — $reason'),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    height: 18 / 14,
                    color: colors.interactive,
                  ),
                ),
                if (when != null)
                  Text(
                    when!,
                    style: TextStyle(
                      fontSize: 12,
                      height: 16 / 12,
                      color: colors.gray,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
