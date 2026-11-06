part of '../channel_management.dart';

/// The pages of Edit Channel, in the reference client's order.
abstract final class _ChannelPages {
  static const overview = 'overview';
  static const permissions = 'permissions';
  static const invites = 'invites';
  static const integrations = 'integrations';
  static const delete = 'delete';
}

/// The reference client's Edit Channel: full screen on [SpaceSettingsFrame]
/// — "# name  Category" over Overview, Permissions, Invites, Integrations,
/// then Delete Channel. Overview is a draft saved through the
/// unsaved-changes bar; leaving it with pending edits only warns.
class ChannelSettingsScreen extends ConsumerStatefulWidget {
  const ChannelSettingsScreen({
    super.key,
    required this.spaceId,
    required this.channel,
  });

  final String spaceId;
  final AccordChannel channel;

  @override
  ConsumerState<ChannelSettingsScreen> createState() =>
      _ChannelSettingsScreenState();
}

class _ChannelSettingsScreenState extends ConsumerState<ChannelSettingsScreen> {
  final UnsavedChangesController _unsaved = UnsavedChangesController();
  String _page = _ChannelPages.overview;
  late AccordChannel _saved = widget.channel;
  late final TextEditingController _name = TextEditingController();
  late final TextEditingController _topic = TextEditingController();
  late String _type;
  late bool _nsfw;
  late int _rateLimit;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _seed();
    _name.addListener(_changed);
    _topic.addListener(_changed);
  }

  @override
  void dispose() {
    _name.dispose();
    _topic.dispose();
    _unsaved.dispose();
    super.dispose();
  }

  void _seed() {
    _name.text = _saved.name ?? '';
    _topic.text = _saved.topic ?? '';
    _type = _saved.type;
    _nsfw = _saved.nsfw;
    _rateLimit = _saved.rateLimitSeconds;
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  bool get _isCategory => _saved.type == 'category';

  bool get _dirty =>
      _name.text != (_saved.name ?? '') ||
      _topic.text != (_saved.topic ?? '') ||
      _type != _saved.type ||
      _nsfw != _saved.nsfw ||
      _rateLimit != _saved.rateLimitSeconds;

  void _select(String key) {
    if (key == _ChannelPages.delete) {
      _delete();
      return;
    }
    if (key == _page || !_unsaved.attemptLeave()) return;
    setState(() => _page = key);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name is required');
      return;
    }
    final client = ref.accordClient;
    if (client == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final topic = _topic.text.trim();
    final supportsModeration = _type != 'category' && _type != 'arcade';
    final data = <String, dynamic>{
      'name': name,
      if (!_isCategory) 'topic': topic.isEmpty ? null : topic,
      if (_textLikeTypes.contains(_saved.type) &&
          _textLikeTypes.contains(_type) &&
          _type != _saved.type)
        'type': _type,
      if (supportsModeration) 'nsfw': _nsfw,
      if (supportsModeration) 'rate_limit': _rateLimit,
    };
    final controller = ref.read(
      accordChannelsControllerProvider(
        ref.readActiveServerKey() ?? '',
        widget.spaceId,
      ).notifier,
    );
    final ok = await controller.updateChannel(client, _saved.id, data);
    if (!mounted) return;
    final fresh = ref
        .read(
          accordChannelsControllerProvider(
            ref.readActiveServerKey() ?? '',
            widget.spaceId,
          ),
        )
        ?.firstWhereOrNull((c) => c.id == _saved.id);
    setState(() {
      _busy = false;
      if (ok) {
        _saved = fresh ?? _saved;
        _seed();
      } else {
        _error = 'Failed to save channel';
      }
    });
  }

  /// "Delete Channel": the reference client's confirmation, then the
  /// settings close.
  Future<void> _delete() async {
    final client = ref.accordClient;
    if (client == null) return;
    final noun = _isCategory ? 'Category' : 'Channel';
    final label = _isCategory ? _saved.name ?? '' : '#${_saved.name ?? ''}';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AccordDialog(
        title: 'Delete $noun',
        subtitle: _saved.type == 'arcade'
            ? 'Are you sure you want to delete $label? Current games will '
                  'end. Installed games remain available in space settings.'
            : 'Are you sure you want to delete $label? This cannot be '
                  'undone.',
        primaryLabel: 'Delete $noun',
        tone: AccordDialogTone.danger,
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final ok = await ref
        .read(
          accordChannelsControllerProvider(
            ref.readActiveServerKey() ?? '',
            widget.spaceId,
          ).notifier,
        )
        .deleteChannel(client, _saved.id);
    if (!mounted) return;
    if (ok) {
      _unsaved.dirty = false;
      Navigator.of(context).pop();
    } else {
      setState(() {
        _busy = false;
        _error = 'Failed to delete channel';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final channels = ref.watch(
      accordChannelsControllerProvider(
        ref.readActiveServerKey() ?? '',
        widget.spaceId,
      ),
    );
    final category = channels?.firstWhereOrNull((c) => c.id == _saved.parentId);
    final dirty = _dirty;
    if (dirty != _unsaved.dirty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _unsaved.dirty = _dirty;
      });
    }
    final IconData? glyph = switch (_saved.type) {
      'voice' || 'stage' => AppIcons.volumeUp,
      'category' => null,
      _ => AppIcons.tag,
    };
    final groups = [
      SpaceSettingsGroup(
        items: [
          const SpaceSettingsItem(
            key: _ChannelPages.overview,
            label: 'Overview',
          ),
          const SpaceSettingsItem(
            key: _ChannelPages.permissions,
            label: 'Permissions',
          ),
          if (!_isCategory) ...const [
            SpaceSettingsItem(key: _ChannelPages.invites, label: 'Invites'),
            SpaceSettingsItem(
              key: _ChannelPages.integrations,
              label: 'Integrations',
            ),
          ],
        ],
      ),
      SpaceSettingsGroup(
        items: [
          SpaceSettingsItem(
            key: _ChannelPages.delete,
            label: _isCategory ? 'Delete Category' : 'Delete Channel',
            danger: true,
            trailingIcon: AppIcons.deleteOutline,
          ),
        ],
      ),
    ];
    final header = Text.rich(
      TextSpan(
        children: [
          if (glyph != null)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Icon(glyph, size: 14, color: colors.gray),
              ),
            ),
          TextSpan(
            text: _saved.name ?? '',
            style: TextStyle(color: colors.gray),
          ),
          if (category != null)
            TextSpan(
              text: '  ${category.name ?? ''}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: colors.dirtyWhite,
              ),
            ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 18 / 14,
      ),
    );
    final Widget body = switch (_page) {
      _ChannelPages.permissions => _ChannelPermissionsPage(
        spaceId: widget.spaceId,
        channel: _saved,
      ),
      _ChannelPages.invites => InvitesSettingsPage(
        spaceId: widget.spaceId,
        channelId: _saved.id,
      ),
      _ChannelPages.integrations => WebhooksSettingsPage(
        spaceId: widget.spaceId,
        channelId: _saved.id,
      ),
      _ => _ChannelOverviewPage(
        channel: _saved,
        name: _name,
        topic: _topic,
        type: _type,
        nsfw: _nsfw,
        rateLimit: _rateLimit,
        error: _error,
        onType: (v) => setState(() => _type = v),
        onNsfw: (v) => setState(() => _nsfw = v),
        onRateLimit: (v) => setState(() => _rateLimit = v),
      ),
    };
    return UnsavedChangesPopGuard(
      controller: _unsaved,
      child: UnsavedChangesScope(
        controller: _unsaved,
        child: SpaceSettingsFrame(
          spaceName: _saved.name ?? '',
          header: header,
          groups: groups,
          selected: _page,
          onSelect: _select,
          overlay: _page == _ChannelPages.overview
              ? ListenableBuilder(
                  listenable: _unsaved,
                  builder: (context, _) => UnsavedChangesBar(
                    visible: dirty,
                    warning: _unsaved.warning,
                    shakes: _unsaved.shakes,
                    saving: _busy,
                    onReset: () => setState(_seed),
                    onSave: _save,
                  ),
                )
              : null,
          child: KeyedSubtree(
            key: ValueKey('channel-page-$_page'),
            child: body,
          ),
        ),
      ),
    );
  }
}

/// Edit Channel › Overview: Channel Name, Channel Topic (with the 1024
/// counter), Slowmode, Content Visibility and, for text-like channels, the
/// type.
class _ChannelOverviewPage extends StatelessWidget {
  const _ChannelOverviewPage({
    required this.channel,
    required this.name,
    required this.topic,
    required this.type,
    required this.nsfw,
    required this.rateLimit,
    required this.error,
    required this.onType,
    required this.onNsfw,
    required this.onRateLimit,
  });

  final AccordChannel channel;
  final TextEditingController name;
  final TextEditingController topic;
  final String type;
  final bool nsfw;
  final int rateLimit;
  final String? error;
  final ValueChanged<String> onType;
  final ValueChanged<bool> onNsfw;
  final ValueChanged<int> onRateLimit;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final leaf = channel.type != 'category';
    final moderated = leaf && channel.type != 'arcade';
    Widget field(
      TextEditingController controller, {
      int lines = 1,
      int? max,
      bool bare = false,
    }) => Container(
      constraints: BoxConstraints(minHeight: lines == 1 ? 40 : 200),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
      decoration: bare ? null : settingsFieldDecoration(colors),
      child: TextField(
        controller: controller,
        minLines: lines,
        maxLines: lines == 1 ? 1 : 10,
        maxLength: max,
        cursorColor: colors.dirtyWhite,
        style: TextStyle(
          fontSize: 16,
          height: 20 / 16,
          color: colors.dirtyWhite,
        ),
        decoration: InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          counterText: '',
          hintText: lines == 1
              ? null
              : 'Let everyone know how to use this channel!',
          hintStyle: TextStyle(fontSize: 16, color: colors.gray),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsPageHeader(title: 'Overview', bottom: 24),
        SettingsFieldLabel(leaf ? 'Channel Name' : 'Category Name'),
        KeyedSubtree(key: const Key('channel-name'), child: field(name)),
        if (leaf) ...[
          const SizedBox(height: 28),
          const SettingsFieldLabel('Channel Topic'),
          Stack(
            children: [
              Container(
                decoration: settingsFieldDecoration(colors),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _FormatToolbar(controller: topic),
                    KeyedSubtree(
                      key: const Key('channel-topic'),
                      child: field(topic, lines: 8, max: 1024, bare: true),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 12,
                bottom: 8,
                child: ListenableBuilder(
                  listenable: topic,
                  builder: (context, _) => Text(
                    '${1024 - topic.text.length}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: colors.dirtyWhite,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
        if (moderated) ...[
          const SizedBox(height: 28),
          const SettingsFieldLabel('Slowmode'),
          AccordSelect<int>(
            key: const Key('channel-slowmode'),
            value: rateLimit,
            options: [
              for (final p in _slowmodePresets)
                AccordSelectOption(p.seconds, p.label),
              if (!_slowmodePresets.any((p) => p.seconds == rateLimit))
                AccordSelectOption(rateLimit, 'Custom (${rateLimit}s)'),
            ],
            onChanged: onRateLimit,
          ),
          const SizedBox(height: 8),
          Text(
            'Members will be restricted to sending one message per this '
            'interval, unless they have the Manage Messages permission.',
            style: TextStyle(
              fontSize: 12,
              height: 16 / 12,
              color: colors.interactive,
            ),
          ),
          const SizedBox(height: 38),
          const SettingsFieldLabel('Content Visibility'),
          AccordRadioRow(
            key: const Key('channel-visibility-default'),
            label: 'Default',
            description: 'Channel content is always visible.',
            selected: !nsfw,
            onTap: () => onNsfw(false),
          ),
          const SizedBox(height: 12),
          AccordRadioRow(
            key: const Key('channel-visibility-age-restricted'),
            label: 'Age-Restricted Channel',
            description:
                'Users will need to confirm that they are of over the legal '
                'age to view the content in this channel.',
            selected: nsfw,
            onTap: () => onNsfw(true),
          ),
        ],
        if (_textLikeTypes.contains(channel.type)) ...[
          const SizedBox(height: 28),
          const SettingsFieldLabel('Channel Type'),
          AccordSelect<String>(
            key: const Key('channel-type'),
            value: type,
            options: [
              for (final t in _channelTypes)
                if (_textLikeTypes.contains(t.value))
                  AccordSelectOption(t.value, t.label),
            ],
            onChanged: onType,
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: 16),
          Text(error!, style: TextStyle(color: colors.red)),
        ],
        const SizedBox(height: 100),
      ],
    );
  }
}

/// Edit Channel › Permissions: "Channel Permissions" and the advanced
/// role/member editor (the per-channel overwrite dialog).
class _ChannelPermissionsPage extends StatelessWidget {
  const _ChannelPermissionsPage({required this.spaceId, required this.channel});

  final String spaceId;
  final AccordChannel channel;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsPageHeader(
          title: 'Channel Permissions',
          description:
              'Use permissions to customise who can do what in this channel.',
          bottom: 16,
        ),
        if (channel.parentId != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: colors.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.hairline),
            ),
            child: Row(
              children: [
                Icon(AppIcons.refresh, size: 20, color: colors.yellow),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Overrides set here apply on top of the category.',
                    style: SettingsText.body(colors),
                  ),
                ),
              ],
            ),
          ),
        const SettingsDivider(top: 32, bottom: 24),
        SettingsLinkCard(
          key: const Key('channel-advanced-permissions'),
          icon: AppIcons.lockOutline,
          title: 'Advanced permissions',
          description:
              'Allow or deny each permission for a role or a member in this '
              'channel.',
          onTap: () => showChannelPermissionsDialog(
            context,
            spaceId: spaceId,
            channel: channel,
          ),
        ),
      ],
    );
  }
}

/// The topic's formatting toolbar: wraps the selection (or inserts a pair)
/// in the markdown for bold, italic, underline, strikethrough or spoiler.
class _FormatToolbar extends StatelessWidget {
  const _FormatToolbar({required this.controller});

  final TextEditingController controller;

  void _wrap(String marker) {
    final value = controller.value;
    final sel = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    final picked = sel.textInside(value.text);
    final text = value.text.replaceRange(
      sel.start,
      sel.end,
      '$marker$picked$marker',
    );
    controller.value = TextEditingValue(
      text: text,
      selection: picked.isEmpty
          ? TextSelection.collapsed(offset: sel.start + marker.length)
          : TextSelection(
              baseOffset: sel.start + marker.length,
              extentOffset: sel.start + marker.length + picked.length,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    Widget button(IconData icon, String tip, String marker) => Tooltip(
      message: tip,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () => _wrap(marker),
        child: SizedBox.square(
          dimension: 28,
          child: Icon(icon, size: 18, color: colors.interactive),
        ),
      ),
    );
    return Container(
      key: const Key('channel-topic-toolbar'),
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      color: const Color(0xFF94949C).withValues(alpha: 0.12),
      child: Row(
        children: [
          button(AppIcons.formatBold, 'Bold', '**'),
          button(AppIcons.formatItalic, 'Italic', '*'),
          button(AppIcons.formatUnderline, 'Underline', '__'),
          button(AppIcons.formatStrikethrough, 'Strikethrough', '~~'),
          Container(
            width: 1,
            height: 16,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            color: colors.hairline,
          ),
          button(AppIcons.visibility, 'Spoiler', '||'),
        ],
      ),
    );
  }
}
