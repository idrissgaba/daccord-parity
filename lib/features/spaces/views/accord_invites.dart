import 'package:bonfire/theme/app_icons.dart';
import 'package:accordkit/accordkit.dart';
import 'package:bonfire/shared/components/async_state_views.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/responsive_dialog.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/shared/utils/self_loading_list.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/spaces/views/space_settings_frame.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/shared/components/accord_dialog.dart';
import 'package:bonfire/shared/components/settings_controls.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the invite-management dialog for [spaceId]: lists active invites,
/// creates new ones, and revokes existing ones.
Future<void> showAccordInvites(
  BuildContext context, {
  required String spaceId,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _InvitesDialog(spaceId: spaceId),
  );
}

/// The shareable link for invite [code] on the server at [baseUrl], or the
/// bare code when the server is unknown.
String accordInviteLink(String? baseUrl, String code) =>
    baseUrl == null ? code : '$baseUrl/invite/$code';

/// Preset invite expirations, mapped to `max_age` seconds (0 = never).
const _expiryPresets = <({String label, int seconds})>[
  (label: '30 minutes', seconds: 1800),
  (label: '1 hour', seconds: 3600),
  (label: '1 day', seconds: 86400),
  (label: '7 days', seconds: 604800),
  (label: 'Never', seconds: 0),
];

/// Preset max-use limits, mapped to the `max_uses` count (0 = unlimited).
const _maxUsesPresets = <({String label, int uses})>[
  (label: 'No limit', uses: 0),
  (label: '1 use', uses: 1),
  (label: '5 uses', uses: 5),
  (label: '10 uses', uses: 10),
  (label: '25 uses', uses: 25),
  (label: '50 uses', uses: 50),
  (label: '100 uses', uses: 100),
];

/// Server Settings › Invites: the active links as the reference client's
/// page — "No active invite links" or a table (Inviter, Invite Code, Uses,
/// Expires), and "Create Invite Link" (whose settings open in a dialog).
class InvitesSettingsPage extends StatelessWidget {
  const InvitesSettingsPage({super.key, required this.spaceId, this.channelId});

  final String spaceId;

  /// Edit Channel › Invites: only that channel's links.
  final String? channelId;

  @override
  Widget build(BuildContext context) =>
      _InvitesDialog(spaceId: spaceId, embedded: true, channelId: channelId);
}

class _InvitesDialog extends ConsumerStatefulWidget {
  const _InvitesDialog({
    required this.spaceId,
    this.embedded = false,
    this.channelId,
  });

  final String spaceId;
  final bool embedded;
  final String? channelId;

  @override
  ConsumerState<_InvitesDialog> createState() => _InvitesDialogState();
}

class _InvitesDialogState extends ConsumerState<_InvitesDialog>
    with SelfLoadingListState<AccordInvite, _InvitesDialog> {
  bool _creating = false;
  int _expirySeconds = 86400;
  int _maxUses = 0;
  bool _temporary = false;
  String _query = '';
  final Set<String> _selected = {};

  AccordClient? get _client => ref.accordClient;

  String? get _baseUrl => ref.read(
    accordAuthProvider.select(
      (s) => s is AccordAuthLoggedIn ? s.session.server.baseUrl : null,
    ),
  );

  @override
  bool get canLoad => _client != null;

  @override
  Future<(List<AccordInvite>? items, String? error)> fetchItems() async {
    final result = await _client!.invites.listSpace(widget.spaceId);
    final data = result.data;
    return (
      result.ok && data is List
          ? data.whereType<AccordInvite>().toList()
          : const <AccordInvite>[],
      result.ok ? null : 'Failed to load invites',
    );
  }

  Future<void> _create() async {
    final client = _client;
    if (client == null) return;
    setState(() {
      _creating = true;
      error = null;
    });
    final result = await client.invites.createSpace(
      widget.spaceId,
      data: {
        'max_age': _expirySeconds,
        'max_uses': _maxUses,
        'temporary': _temporary,
      },
    );
    if (!mounted) return;
    if (result.ok) {
      await load();
      if (!mounted) return;
      setState(() => _creating = false);
    } else {
      setState(() {
        _creating = false;
        error = 'Failed to create invite';
      });
    }
  }

  Future<void> _revoke(AccordInvite invite) async {
    final client = _client;
    if (client == null) return;
    final result = await client.invites.delete(invite.code);
    if (!mounted) return;
    if (result.ok) {
      setState(
        () => items = items?.where((i) => i.code != invite.code).toList(),
      );
    } else {
      setState(() => error = 'Failed to revoke invite');
    }
  }

  /// Revokes every selected invite, then clears the selection.
  Future<void> _revokeSelected() async {
    final client = _client;
    if (client == null || _selected.isEmpty) return;
    final codes = _selected.toList();
    for (final code in codes) {
      final result = await client.invites.delete(code);
      if (result.ok) {
        items = items?.where((i) => i.code != code).toList();
      }
    }
    if (!mounted) return;
    setState(() => _selected.clear());
  }

  Future<void> _copy(AccordInvite invite) async {
    await Clipboard.setData(
      ClipboardData(text: accordInviteLink(_baseUrl, invite.code)),
    );
    if (!mounted) return;
    showInfoSnack(context, 'Invite link copied');
  }

  String _usesLabel(AccordInvite invite) {
    final max = invite.maxUses;
    final maxInt = asInt(max);
    if (maxInt <= 0) return '${invite.uses} uses';
    return '${invite.uses}/$maxInt uses';
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    final channelId = widget.channelId;
    final invites = channelId == null
        ? items
        : items?.where((i) => i.channelId == channelId).toList();
    if (widget.embedded) return _page(context, invites);
    return Dialog(
      child: ConstrainedBox(
        constraints: dialogConstraints(context, maxWidth: 480, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Icon(AppIcons.personAdd, size: 18, color: colors.dirtyWhite),
                  const SizedBox(width: 8),
                  Text('Invite people', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(AppIcons.close, size: 18),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _expirySeconds,
                      decoration: const InputDecoration(
                        labelText: 'Expire after',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final p in _expiryPresets)
                          DropdownMenuItem(
                            value: p.seconds,
                            child: Text(p.label),
                          ),
                      ],
                      onChanged: _creating
                          ? null
                          : (v) => setState(() => _expirySeconds = v ?? 86400),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _maxUses,
                      decoration: const InputDecoration(
                        labelText: 'Max uses',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final p in _maxUsesPresets)
                          DropdownMenuItem(value: p.uses, child: Text(p.label)),
                      ],
                      onChanged: _creating
                          ? null
                          : (v) => setState(() => _maxUses = v ?? 0),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: CheckboxListTile(
                      value: _temporary,
                      onChanged: _creating
                          ? null
                          : (v) => setState(() => _temporary = v ?? false),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                      title: const Text('Temporary membership'),
                      subtitle: Text(
                        'Kicked on disconnect unless given a role',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _creating ? null : _create,
                    icon: const Icon(AppIcons.add, size: 18),
                    label: const Text('Create'),
                  ),
                ],
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  error!,
                  style: theme.textTheme.bodySmall!.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            const Divider(height: 1),
            if (invites != null && invites.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        onChanged: (v) =>
                            setState(() => _query = v.trim().toLowerCase()),
                        decoration: InputDecoration(
                          isDense: true,
                          prefixIcon: Icon(
                            AppIcons.search,
                            size: 18,
                            color: colors.gray,
                          ),
                          hintText: 'Search invites',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    if (_selected.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: _revokeSelected,
                        icon: Icon(
                          AppIcons.deleteSweepOutlined,
                          size: 18,
                          color: theme.colorScheme.error,
                        ),
                        label: Text(
                          'Revoke ${_selected.length}',
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            Flexible(
              child: invites == null
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: LoadingView(),
                    )
                  : invites.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Text(
                          'No active invites',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    )
                  : Builder(
                      builder: (context) {
                        final filtered = _query.isEmpty
                            ? invites
                            : invites
                                  .where(
                                    (i) =>
                                        i.code.toLowerCase().contains(_query),
                                  )
                                  .toList();
                        if (filtered.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.all(32),
                            child: Center(
                              child: Text(
                                'No matches',
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          );
                        }
                        return ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.all(8),
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final invite = filtered[index];
                            final selected = _selected.contains(invite.code);
                            return ListTile(
                              leading: Checkbox(
                                value: selected,
                                onChanged: (v) => setState(() {
                                  if (v ?? false) {
                                    _selected.add(invite.code);
                                  } else {
                                    _selected.remove(invite.code);
                                  }
                                }),
                              ),
                              title: Text(
                                ref.watch(
                                      settingsControllerProvider.select(
                                        (s) => s.streamerMode,
                                      ),
                                    )
                                    ? '••••••••'
                                    : invite.code,
                                style: theme.textTheme.titleSmall,
                              ),
                              subtitle: Text(
                                _usesLabel(invite),
                                style: theme.textTheme.bodySmall,
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Copy link',
                                    onPressed: () => _copy(invite),
                                    icon: const Icon(AppIcons.copy, size: 18),
                                  ),
                                  IconButton(
                                    tooltip: 'Revoke',
                                    onPressed: () => _revoke(invite),
                                    icon: Icon(
                                      AppIcons.deleteOutline,
                                      size: 18,
                                      color: theme.colorScheme.error,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// "Create Invite Link": the link settings in a dialog, then the link.
  Future<void> _createFromPage() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AccordDialog(
          title: 'Invite link settings',
          primaryLabel: 'Generate a New Link',
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SettingsFieldLabel('Expire After'),
              AccordSelect<int>(
                key: const Key('invite-expiry'),
                value: _expirySeconds,
                options: [
                  for (final p in _expiryPresets)
                    AccordSelectOption(p.seconds, p.label),
                ],
                onChanged: (v) => setLocal(() => _expirySeconds = v),
              ),
              const SizedBox(height: 20),
              const SettingsFieldLabel('Max Number of Uses'),
              AccordSelect<int>(
                key: const Key('invite-max-uses'),
                value: _maxUses,
                options: [
                  for (final p in _maxUsesPresets)
                    AccordSelectOption(p.uses, p.label),
                ],
                onChanged: (v) => setLocal(() => _maxUses = v),
              ),
              const SizedBox(height: 20),
              SettingsSwitchRow(
                label: 'Grant temporary membership',
                description:
                    'Temporary members are kicked when they disconnect '
                    'unless a role has been assigned.',
                value: _temporary,
                onChanged: (v) => setLocal(() => _temporary = v),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok == true && mounted) await _create();
  }

  Widget _page(BuildContext context, List<AccordInvite>? invites) {
    final colors = BonfireThemeExtension.of(context);
    final streamer = ref.watch(
      settingsControllerProvider.select((s) => s.streamerMode),
    );
    final head = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      height: 16 / 12,
      color: colors.interactive,
    );
    Widget columns(List<Widget> cells) => Row(
      children: [
        Expanded(flex: 3, child: cells[0]),
        Expanded(flex: 3, child: cells[1]),
        Expanded(flex: 1, child: cells[2]),
        Expanded(flex: 2, child: cells[3]),
        const SizedBox(width: 32),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsPageHeader(
          title: 'Invites',
          description: widget.channelId == null
              ? 'Create an invite link that anyone can use to join, or invite '
                    'friends directly.'
              : "Here's a list of all active invite links. You can revoke any "
                    'one or create one.',
          bottom: 24,
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                invites == null || invites.isEmpty
                    ? 'No active invite links'
                    : 'Active Invite Links',
                style: SettingsText.description(colors).copyWith(
                  fontSize: invites == null || invites.isEmpty ? 14 : 12,
                ),
              ),
            ),
            AccordButton(
              key: const Key('invites-create'),
              label: 'Create Invite Link',
              onPressed: _creating ? null : _createFromPage,
            ),
          ],
        ),
        if (error != null) ...[
          const SizedBox(height: 8),
          Text(error!, style: TextStyle(color: colors.red, fontSize: 14)),
        ],
        if (invites != null && invites.isNotEmpty) ...[
          const SizedBox(height: 20),
          columns([
            Text('INVITER', style: head),
            Text('INVITE CODE', style: head),
            Text('USES', style: head),
            Text('EXPIRES', style: head),
          ]),
          const SizedBox(height: 8),
          for (final invite in invites)
            _InviteRow(
              key: Key('invite-${invite.code}'),
              cells: columns,
              inviter: invite.inviterId == null
                  ? 'Unknown'
                  : accordAuthorName(
                      invite.inviterId!,
                      members: ref.watch(
                        accordMembersControllerProvider(
                          ref.watchActiveServerKey() ?? '',
                          widget.spaceId,
                        ),
                      ),
                      users: ref.watch(
                        accordUsersControllerProvider(
                          ref.watchActiveServerKey() ?? '',
                        ),
                      ),
                    ),
              code: streamer ? '••••••••' : invite.code,
              uses: '${invite.uses}',
              expires: _expiresLabel(invite),
              onCopy: () => _copy(invite),
              onRevoke: () => _revoke(invite),
            ),
        ],
      ],
    );
  }

  String _expiresLabel(AccordInvite invite) {
    final raw = invite.expiresAt?.toString();
    final at = raw == null ? null : DateTime.tryParse(raw)?.toLocal();
    if (at == null) return '∞';
    final left = at.difference(DateTime.now());
    if (left.isNegative) return 'Expired';
    if (left.inDays >= 1) return '${left.inDays}d ${left.inHours % 24}h';
    if (left.inHours >= 1) return '${left.inHours}h ${left.inMinutes % 60}m';
    return '${left.inMinutes}m';
  }
}

/// One invite in the table; Copy and the revoke ✕ show on hover.
class _InviteRow extends StatefulWidget {
  const _InviteRow({
    super.key,
    required this.cells,
    required this.inviter,
    required this.code,
    required this.uses,
    required this.expires,
    required this.onCopy,
    required this.onRevoke,
  });

  final Widget Function(List<Widget>) cells;
  final String inviter;
  final String code;
  final String uses;
  final String expires;
  final VoidCallback onCopy;
  final VoidCallback onRevoke;

  @override
  State<_InviteRow> createState() => _InviteRowState();
}

class _InviteRowState extends State<_InviteRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final text = TextStyle(fontSize: 14, height: 18 / 14, color: colors.dirtyWhite);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onCopy,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: _hover ? colors.hover : Colors.transparent,
            border: Border(top: BorderSide(color: colors.hairline)),
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              widget.cells([
                Text(widget.inviter, style: text, overflow: TextOverflow.ellipsis),
                Text(widget.code, style: text),
                Text(widget.uses, style: text),
                Text(widget.expires, style: text),
              ]),
              if (_hover)
                Positioned(
                  right: 0,
                  child: Tooltip(
                    message: 'Revoke Invite',
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: widget.onRevoke,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          AppIcons.close,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
