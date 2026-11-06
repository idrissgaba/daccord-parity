import 'package:bonfire/theme/app_icons.dart';
import 'package:accordkit/accordkit.dart';
import 'package:bonfire/shared/utils/confirm_dialog.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/features/channels/controllers/accord_channels.dart';
import 'package:bonfire/features/channels/views/channel_permissions.dart';
import 'package:bonfire/features/spaces/views/accord_invites.dart';
import 'package:bonfire/features/spaces/views/accord_webhooks.dart';
import 'package:bonfire/features/spaces/views/space_settings_frame.dart';
import 'package:bonfire/shared/components/accord_dialog.dart';
import 'package:bonfire/shared/components/settings_controls.dart';
import 'package:bonfire/shared/components/unsaved_changes_bar.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'channel_management/settings_screen.dart';

/// The channel types a user can create from the UI. Categories group other
/// channels; the rest are leaf channels.
const _channelTypes = <({String value, String label, IconData icon})>[
  (value: 'text', label: 'Text', icon: AppIcons.tag),
  (value: 'voice', label: 'Voice', icon: AppIcons.volumeUp),
  (value: 'stage', label: 'Stage', icon: AppIcons.podcasts),
  (value: 'forum', label: 'Forum', icon: AppIcons.forum),
  (value: 'announcement', label: 'Announcement', icon: AppIcons.campaign),
  (value: 'arcade', label: 'Arcade', icon: AppIcons.sportsEsportsOutlined),
  (value: 'category', label: 'Category', icon: AppIcons.folder),
];

/// Channel types whose stored messages and rendering are identical, so an
/// existing channel may be switched between them retroactively without losing
/// data. Mirrors accordserver's `is_non_destructive_type_change`; the type
/// selector in edit mode is limited to this set.
const _textLikeTypes = <String>{'text', 'announcement'};

/// Slowmode (rate-limit per user) presets in seconds (0 = off). Mirrors the
/// reference client's channel edit dialog.
const _slowmodePresets = <({String label, int seconds})>[
  (label: 'Off', seconds: 0),
  (label: '5s', seconds: 5),
  (label: '10s', seconds: 10),
  (label: '30s', seconds: 30),
  (label: '1m', seconds: 60),
  (label: '5m', seconds: 300),
  (label: '15m', seconds: 900),
  (label: '1h', seconds: 3600),
  (label: '6h', seconds: 21600),
];

/// Opens the "create channel" dialog for [spaceId]. When [parentId] is set the
/// new channel is nested under that category by default.
Future<void> showCreateChannelDialog(
  BuildContext context, {
  required String spaceId,
  String? parentId,
  String initialType = 'text',
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ChannelEditorDialog(
      spaceId: spaceId,
      parentId: parentId,
      initialType: initialType,
    ),
  );
}

/// Opens Edit Channel for an existing [channel]: the reference client's
/// full-screen channel settings (Overview, Permissions, Invites,
/// Integrations, Delete Channel).
Future<void> showEditChannelDialog(
  BuildContext context, {
  required String spaceId,
  required AccordChannel channel,
}) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      settings: const RouteSettings(name: 'channel-settings'),
      transitionDuration: const Duration(milliseconds: 150),
      reverseTransitionDuration: const Duration(milliseconds: 100),
      pageBuilder: (_, _, _) =>
          ChannelSettingsScreen(spaceId: spaceId, channel: channel),
      transitionsBuilder: (_, animation, _, child) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween(begin: 1.04, end: 1.0).animate(animation),
          child: child,
        ),
      ),
    ),
  );
}

/// Confirms, then deletes [channel] from [spaceId]. Returns true when deleted.
/// Shared by the edit dialog and the channel/category context menus so the
/// confirmation copy and failure handling stay consistent. Shows a SnackBar on
/// failure (the edit dialog surfaces its own inline error and ignores this).
Future<bool> confirmAndDeleteChannel(
  BuildContext context,
  WidgetRef ref, {
  required String spaceId,
  required AccordChannel channel,
}) async {
  final isCategory = channel.type == 'category';
  final noun = isCategory ? 'category' : 'channel';
  final confirmed = await showConfirmDialog(
    context,
    title: 'Delete $noun',
    message: channel.type == 'arcade'
        ? 'Delete "${channel.name ?? channel.id}"? Current games will end. Installed games remain available in space settings.'
        : 'Delete "${channel.name ?? channel.id}"? This cannot be undone.',
    confirmLabel: 'Delete',
  );
  if (confirmed != true) return false;
  final client = ref.accordClient;
  if (client == null) return false;
  final ok = await ref
      .read(
        accordChannelsControllerProvider(
          ref.readActiveServerKey() ?? '',
          spaceId,
        ).notifier,
      )
      .deleteChannel(client, channel.id);
  if (!ok && context.mounted) {
    showInfoSnack(context, 'Failed to delete $noun');
  }
  return ok;
}

class _ChannelEditorDialog extends ConsumerStatefulWidget {
  const _ChannelEditorDialog({
    required this.spaceId,
    this.parentId,
    this.initialType = 'text',
  });

  final String spaceId;
  final String? parentId;
  final String initialType;

  @override
  ConsumerState<_ChannelEditorDialog> createState() =>
      _ChannelEditorDialogState();
}

class _ChannelEditorDialogState extends ConsumerState<_ChannelEditorDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _topic = TextEditingController();
  late String _type = widget.initialType;
  late String? _parentId = widget.parentId;
  bool _nsfw = false;
  int _rateLimit = 0;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _topic.dispose();
    super.dispose();
  }

  AccordClient? get _client => ref.accordClient;

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name is required');
      return;
    }
    final client = _client;
    if (client == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final controller = ref.read(
      accordChannelsControllerProvider(
        ref.readActiveServerKey() ?? '',
        widget.spaceId,
      ).notifier,
    );
    final topic = _topic.text.trim();
    final supportsModeration = _type != 'category' && _type != 'arcade';
    final data = <String, dynamic>{
      'name': name,
      'type': _type,
      if (topic.isNotEmpty) 'topic': topic,
      if (_parentId != null && _type != 'category') 'parent_id': _parentId,
      if (supportsModeration && _nsfw) 'nsfw': true,
      if (supportsModeration && _rateLimit > 0) 'rate_limit': _rateLimit,
    };
    final ok = await controller.createChannel(client, data) != null;
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).maybePop();
    } else {
      setState(() {
        _busy = false;
        _error = 'Failed to create channel';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Categories the new channel can be nested under (edit keeps the channel's
    // own category fixed for simplicity).
    final channels = ref.watch(
      accordChannelsControllerProvider(
        ref.readActiveServerKey() ?? '',
        widget.spaceId,
      ),
    );
    final canCreateArcade =
        channels != null && !channels.any((c) => c.type == 'arcade');
    final categories =
        channels?.where((c) => c.type == 'category').toList() ??
        const <AccordChannel>[];
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Create channel',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              _ChannelNameField(
                controller: _name,
                enabled: !_busy,
                onSubmitted: _submit,
              ),
              const SizedBox(height: 12),
              _CreateTypeSelector(
                  type: _type,
                  parentId: _parentId,
                  categories: categories,
                  allowArcade: canCreateArcade,
                  busy: _busy,
                  onTypeChanged: (v) => setState(() => _type = v ?? 'text'),
                  onParentChanged: (v) => setState(() => _parentId = v),
                ),
              if (_type != 'category')
                _ChannelTopicField(controller: _topic, enabled: !_busy),
              if (_type != 'category' && _type != 'arcade')
                _ChannelModerationFields(
                  nsfw: _nsfw,
                  rateLimit: _rateLimit,
                  busy: _busy,
                  onNsfwChanged: (v) => setState(() => _nsfw = v),
                  onRateLimitChanged: (v) =>
                      setState(() => _rateLimit = v ?? 0),
                ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall!.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              _EditorActionsRow(busy: _busy, onSubmit: _submit),
            ],
          ),
        ),
      ),
    );
  }
}

/// The channel name text field (autofocused; Enter submits).
class _ChannelNameField extends StatelessWidget {
  const _ChannelNameField({
    required this.controller,
    required this.enabled,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: true,
      enabled: enabled,
      decoration: const InputDecoration(
        labelText: 'Name',
        isDense: true,
        border: OutlineInputBorder(),
      ),
      onSubmitted: (_) => onSubmitted(),
    );
  }
}

/// Create mode: the channel-type dropdown plus (for leaf channels, when
/// categories exist) the parent-category picker, with their trailing spacers.
class _CreateTypeSelector extends StatelessWidget {
  const _CreateTypeSelector({
    required this.type,
    required this.parentId,
    required this.categories,
    required this.allowArcade,
    required this.busy,
    required this.onTypeChanged,
    required this.onParentChanged,
  });

  final String type;
  final String? parentId;
  final List<AccordChannel> categories;
  final bool allowArcade;
  final bool busy;
  final ValueChanged<String?> onTypeChanged;
  final ValueChanged<String?> onParentChanged;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: type,
          decoration: const InputDecoration(
            labelText: 'Type',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          items: [
            for (final t in _channelTypes.where(
              (t) => t.value != 'arcade' || allowArcade,
            ))
              DropdownMenuItem(
                value: t.value,
                child: Row(
                  children: [
                    Icon(t.icon, size: 16, color: colors.dirtyWhite),
                    const SizedBox(width: 8),
                    Text(t.label),
                  ],
                ),
              ),
          ],
          onChanged: busy ? null : onTypeChanged,
        ),
        const SizedBox(height: 12),
        if (type != 'category' && categories.isNotEmpty)
          DropdownButtonFormField<String?>(
            initialValue: parentId,
            decoration: const InputDecoration(
              labelText: 'Category',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('None')),
              for (final c in categories)
                DropdownMenuItem(value: c.id, child: Text(c.name ?? c.id)),
            ],
            onChanged: busy ? null : onParentChanged,
          ),
        if (type != 'category' && categories.isNotEmpty)
          const SizedBox(height: 12),
      ],
    );
  }
}

/// Edit mode: the type switcher limited to non-destructive (text-like) types,
/// with its trailing spacer.
/// The optional topic text field (leaf channels only).
class _ChannelTopicField extends StatelessWidget {
  const _ChannelTopicField({required this.controller, required this.enabled});

  final TextEditingController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      minLines: 1,
      maxLines: 3,
      decoration: const InputDecoration(
        labelText: 'Topic (optional)',
        isDense: true,
        border: OutlineInputBorder(),
      ),
    );
  }
}

/// Moderation block (leaf channels only): NSFW toggle plus the slowmode
/// preset picker, with the spacers around them.
class _ChannelModerationFields extends StatelessWidget {
  const _ChannelModerationFields({
    required this.nsfw,
    required this.rateLimit,
    required this.busy,
    required this.onNsfwChanged,
    required this.onRateLimitChanged,
  });

  final bool nsfw;
  final int rateLimit;
  final bool busy;
  final ValueChanged<bool> onNsfwChanged;
  final ValueChanged<int?> onRateLimitChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        SwitchListTile(
          value: nsfw,
          onChanged: busy ? null : onNsfwChanged,
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Age-restricted (NSFW)'),
          subtitle: Text(
            'Users must confirm before viewing',
            style: theme.textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          initialValue: rateLimit,
          decoration: const InputDecoration(
            labelText: 'Slowmode',
            helperText:
                'One message per user per interval; moderators are '
                'exempt',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          items: [
            for (final p in _slowmodePresets)
              DropdownMenuItem(value: p.seconds, child: Text(p.label)),
            // A value set elsewhere (the API, another client) that isn't a
            // preset: show it as-is rather than as "Off", which would
            // silently turn slowmode off on the next save.
            if (!_slowmodePresets.any((p) => p.seconds == rateLimit))
              DropdownMenuItem(
                value: rateLimit,
                child: Text('Custom (${rateLimit}s)'),
              ),
          ],
          onChanged: busy ? null : onRateLimitChanged,
        ),
      ],
    );
  }
}

/// Bottom action row: Cancel and Create.
class _EditorActionsRow extends StatelessWidget {
  const _EditorActionsRow({required this.busy, required this.onSubmit});

  final bool busy;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Spacer(),
        TextButton(
          onPressed: busy ? null : () => Navigator.of(context).maybePop(),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: busy ? null : onSubmit,
          child: const Text('Create'),
        ),
      ],
    );
  }
}
