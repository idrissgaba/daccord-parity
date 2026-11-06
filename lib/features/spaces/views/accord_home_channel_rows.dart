part of 'accord_home.dart';

/// A muted channel's name and glyph: `#96979E` at 50 % opacity, as measured
/// on the reference client.
const Color _kMutedChannelTint = Color(0x8096979E);

/// Height of a channel row's link (its list item adds a 1 px margin above and
/// below), its corner radius, and its horizontal inset in the column.
const double _kChannelRowHeight = 32;
const double _kChannelRowRadius = 8;
const double _kChannelRowInset = 8;

/// A category row for the static list and the drag list alike: the inline
/// "add channel" affordance is wired only for managers of a real space.
_CategoryHeader _categoryHeader(
  BuildContext context,
  AccordChannel category, {
  required String? spaceId,
  required bool canManageChannels,
  required bool collapsed,
  required VoidCallback onToggle,
}) => _CategoryHeader(
  category: category,
  spaceId: spaceId,
  canManageChannels: canManageChannels,
  collapsed: collapsed,
  onToggle: onToggle,
  onAdd: canManageChannels && spaceId != null
      ? () => showCreateChannelDialog(
          context,
          spaceId: spaceId,
          parentId: category.id,
        )
      : null,
);

/// A channel row for the static list and the drag list alike; the settings
/// affordance follows `manage_channels`, the invite one `create_invites`.
_ChannelTile _channelTile(
  BuildContext context,
  AccordChannel channel, {
  required String? spaceId,
  required bool selected,
  required bool canManageChannels,
  required bool canInvite,
  required VoidCallback onTap,
}) => _ChannelTile(
  channel: channel,
  spaceId: spaceId,
  selected: selected,
  canManageChannels: canManageChannels,
  onTap: onTap,
  onEdit: canManageChannels && spaceId != null
      ? () => showEditChannelDialog(context, spaceId: spaceId, channel: channel)
      : null,
  onInvite: canInvite && spaceId != null
      ? () => showAccordInvites(context, spaceId: spaceId)
      : null,
);

/// A category: its name in small caps-less 14 px grey with a caret that turns
/// to point right while collapsed, and a "+" (create channel) on hover for
/// managers. 16 px of air above, as in other chat apps.
class _CategoryHeader extends ConsumerStatefulWidget {
  const _CategoryHeader({
    required this.category,
    required this.spaceId,
    required this.canManageChannels,
    required this.collapsed,
    required this.onToggle,
    this.onAdd,
  });

  final AccordChannel category;
  final String? spaceId;
  final bool canManageChannels;
  final bool collapsed;
  final VoidCallback onToggle;
  final VoidCallback? onAdd;

  @override
  ConsumerState<_CategoryHeader> createState() => _CategoryHeaderState();
}

class _CategoryHeaderState extends ConsumerState<_CategoryHeader> {
  bool _hovered = false;

  void _showMenu([Offset? position]) {
    final id = widget.spaceId;
    if (id == null) return;
    showCategoryContextMenu(
      context,
      ref,
      category: widget.category,
      spaceId: id,
      canManageChannels: widget.canManageChannels,
      collapsed: widget.collapsed,
      onToggle: widget.onToggle,
      globalPosition: position,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final tint = _hovered ? colors.dirtyWhite : colors.gray;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          _kChannelRowInset,
          16,
          _kChannelRowInset,
          0,
        ),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onToggle,
                onLongPress: () => _showMenu(),
                onSecondaryTapUp: (d) => _showMenu(d.globalPosition),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 0, 3),
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          widget.category.name ?? '',
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium!
                              .copyWith(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: tint,
                              ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      AnimatedRotation(
                        turns: widget.collapsed ? -0.25 : 0,
                        duration: const Duration(milliseconds: 150),
                        child: Icon(
                          AppIcons.expandMore,
                          key: const Key('category-caret'),
                          size: 12,
                          color: tint,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (widget.onAdd != null)
              Opacity(
                opacity: _hovered ? 1 : 0,
                child: Tooltip(
                  message: 'Create Channel',
                  child: InkWell(
                    key: const Key('category-add-channel'),
                    onTap: _hovered ? widget.onAdd : null,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 8, 3),
                      child: Icon(AppIcons.add, size: 16, color: tint),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChannelTile extends ConsumerStatefulWidget {
  const _ChannelTile({
    required this.channel,
    required this.spaceId,
    required this.selected,
    required this.canManageChannels,
    required this.onTap,
    this.onEdit,
    this.onInvite,
  });

  final AccordChannel channel;
  final String? spaceId;
  final bool selected;
  final bool canManageChannels;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onInvite;

  @override
  ConsumerState<_ChannelTile> createState() => _ChannelTileState();
}

class _ChannelTileState extends ConsumerState<_ChannelTile> {
  bool _hovered = false;

  /// When this row was last clicked, for the double-click-to-join fast path
  /// (see [isVoiceDoubleTap]). Per-tile, so clicking two rows in quick
  /// succession can't be mistaken for a double-click.
  DateTime? _lastTapAt;

  bool get _isVoice => isVoiceChannelType(widget.channel.type);

  bool get _connectedHere =>
      ref.read(voiceControllerProvider).channelId == widget.channel.id;

  /// Explicitly connects to this voice channel. Selecting the channel never
  /// does this on touch (#202) — only the row's double-tap, its context menu,
  /// and the lobby's Join button do; on desktop a single click joins.
  void _joinVoice() {
    final spaceId = widget.spaceId;
    if (!_isVoice || spaceId == null || _connectedHere) return;
    ref.read(voiceControllerProvider.notifier).join(widget.channel.id, spaceId);
  }

  /// Selects the channel; a second click inside the double-click window joins it
  /// instead of re-selecting (the first click already opened the tab).
  ///
  /// On desktop a single click on a voice channel joins it and stays on the
  /// channel being read; once connected, clicking the row opens the call
  /// view — as in other chat apps. Touch keeps select-then-join so a
  /// scroll's stray tap can't put someone on air (#202).
  void _handleTap() {
    final now = DateTime.now();
    if (_isVoice && shouldUseDesktopLayout(context)) {
      _lastTapAt = null;
      if (_connectedHere) {
        widget.onTap();
      } else {
        _joinVoice();
      }
      return;
    }
    if (_isVoice && isVoiceDoubleTap(_lastTapAt, now)) {
      _lastTapAt = null;
      _joinVoice();
      return;
    }
    _lastTapAt = now;
    widget.onTap();
  }

  void _showMenu([Offset? position]) {
    final spaceId = widget.spaceId;
    if (spaceId == null) return;
    final connected = _connectedHere;
    showChannelContextMenu(
      context,
      ref,
      channel: widget.channel,
      spaceId: spaceId,
      canManageChannels: widget.canManageChannels,
      canInvite: widget.onInvite != null,
      globalPosition: position,
      onOpenChat: widget.onTap,
      touchLeadingEntries: [
        if (_isVoice && !connected)
          AccordMenuEntry(
            label: 'Join Voice',
            icon: AppIcons.call,
            onSelected: _joinVoice,
          ),
        if (_isVoice && connected)
          AccordMenuEntry(
            label: 'Disconnect',
            icon: AppIcons.callEnd,
            destructive: true,
            onSelected: () =>
                ref.read(voiceControllerProvider.notifier).leave(),
          ),
        if (_isVoice) const AccordMenuEntry.divider(),
      ],
    );
  }

  /// Sets or clears the voice channel's status (its topic), from the line
  /// under its name.
  Future<void> _editStatus() async {
    final spaceId = widget.spaceId;
    final client = ref.accordClient;
    if (spaceId == null || client == null) return;
    final status = await showTextPromptDialog(
      context,
      title: 'Channel status',
      hintText: 'What is happening in this channel?',
      initial: widget.channel.topic ?? '',
      resetLabel: (widget.channel.topic ?? '').isEmpty ? null : 'Clear',
    );
    if (status == null || !mounted) return;
    await ref
        .read(
          accordChannelsControllerProvider(
            ref.readActiveServerKey() ?? '',
            spaceId,
          ).notifier,
        )
        .updateChannel(client, widget.channel.id, {'topic': status.trim()});
  }

  IconData get _glyph {
    switch (widget.channel.type) {
      case 'voice':
        return AppIcons.volumeUp;
      case 'stage':
        return AppIcons.podcasts;
      case 'forum':
        return AppIcons.forum;
      case 'announcement':
        return AppIcons.campaign;
      case 'arcade':
        return AppIcons.sportsEsportsOutlined;
      default:
        return AppIcons.tag;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    final channel = widget.channel;
    final isVoice = isVoiceChannelType(channel.type);
    final enabled =
        isVoice ||
        channel.type == 'arcade' ||
        channel.type == 'text' ||
        channel.type == 'forum' ||
        channel.type == 'announcement';
    final activeKey = ref.watch(
      connectionsControllerProvider.select((s) => s.activeKey),
    );
    // A channel set to `nothing` is silenced outright: no pill, no badge, no
    // bright name (its unread state is kept, so restoring the level restores
    // the indicator). A muted *space* still shows unread inside itself — that
    // mute only suppresses the rail roll-up. A muted channel (or one in a
    // muted category) is dimmed and loses its pill, but keeps its mentions.
    final mutedIds = activeKey == null
        ? const <String>{}
        : ref.watch(mutedChannelsControllerProvider(activeKey)).value ??
              const <String>{};
    final muted =
        mutedIds.contains(channel.id) ||
        (channel.parentId != null && mutedIds.contains(channel.parentId));
    final level = activeKey == null
        ? null
        : ref.watch(
            settingsControllerProvider.select(
              (s) => s.channelNotificationLevel(activeKey, channel.id),
            ),
          );
    final channelLevels = {if (level != null) channel.id: level};
    final (unread: isUnread, :mentions) = activeKey == null
        ? (unread: false, mentions: 0)
        : ref.watch(
            readStateControllerProvider(activeKey).select(
              (readState) => (
                unread: readState.isUnreadVisible(
                  channel.id,
                  channelLevels: channelLevels,
                  mutedChannels: {if (muted) channel.id},
                ),
                mentions: readState.visibleMentionCount(
                  channel.id,
                  channelLevels: channelLevels,
                ),
              ),
            ),
          );
    final unread = isUnread && !widget.selected;

    final connectedHere =
        isVoice &&
        ref.watch(
          voiceControllerProvider.select((v) => v.channelId == channel.id),
        );
    final voiceCount = isVoice
        ? ref.watch(
            voiceStatesControllerProvider(
              ref.readActiveServerKey() ?? '',
            ).select((cache) => voiceUserCount(cache, channel.id)),
          )
        : 0;

    // Rest: grey name and glyph. Unread: white name, lighter glyph. Selected:
    // both white. Hover: lighter grey. Muted: a mid grey at half opacity (the
    // reference client's `#96979E` at 50 %), selected or not.
    final bright = widget.selected || unread;
    final tint = !enabled
        ? colors.gray.withValues(alpha: 0.6)
        : muted && !widget.selected
        ? _kMutedChannelTint
        : bright
        ? colors.dirtyWhite
        : _hovered
        ? colors.dirtyWhite.withValues(alpha: 0.85)
        : colors.gray;
    final glyphTint = unread && !widget.selected && !muted
        ? colors.interactive
        : tint;

    // Desktop: the action icons show on hover and on the selected row; touch
    // has no hover, so they stay on the selected row only.
    final showActions = _hovered || widget.selected;
    final status = isVoice ? (channel.topic ?? '').trim() : '';
    final canSetStatus = isVoice && widget.onEdit != null;
    final showStatusLine = status.isNotEmpty || (canSetStatus && _hovered);

    final tileRow = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          _kChannelRowInset,
          1,
          _kChannelRowInset,
          1,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Material(
              color: widget.selected
                  ? colors.selection
                  : _hovered
                  ? colors.hover
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(_kChannelRowRadius),
              child: InkWell(
                borderRadius: BorderRadius.circular(_kChannelRowRadius),
                onTap: enabled ? _handleTap : null,
                onLongPress: () => _showMenu(),
                onSecondaryTapUp: (d) => _showMenu(d.globalPosition),
                hoverColor: Colors.transparent,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: _kChannelRowHeight,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        Icon(
                          _glyph,
                          size: 20,
                          color: connectedHere ? colors.green : glyphTint,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                channel.name ?? channel.id,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyLarge!.copyWith(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: tint,
                                ),
                              ),
                              if (showStatusLine)
                                GestureDetector(
                                  key: const Key('voice-channel-status'),
                                  onTap: canSetStatus ? _editStatus : null,
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            status.isEmpty
                                                ? 'Set a channel status'
                                                : status,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.bodySmall!
                                                .copyWith(
                                                  fontSize: 12,
                                                  color: colors.gray,
                                                ),
                                          ),
                                        ),
                                        if (canSetStatus) ...[
                                          const SizedBox(width: 4),
                                          Icon(
                                            AppIcons.edit,
                                            size: 10,
                                            color: colors.gray,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (channel.type == 'arcade' &&
                            activeKey != null &&
                            widget.spaceId != null)
                          ArcadeActivityBadge(
                            serverKey: activeKey,
                            spaceId: widget.spaceId!,
                            channelId: channel.id,
                          )
                        else if (isVoice &&
                            voiceOccupancyLabel(
                                  voiceCount,
                                  channel.userLimit,
                                ) !=
                                null &&
                            !showActions)
                          Text(
                            voiceOccupancyLabel(voiceCount, channel.userLimit)!,
                            key: const Key('voice-channel-occupancy'),
                            style: theme.textTheme.bodySmall!.copyWith(
                              fontSize: 12,
                              color: colors.gray,
                            ),
                          )
                        else if (mentions > 0)
                          _MentionBadge(count: mentions),
                        if (showActions) ...[
                          if (isVoice)
                            _RowAction(
                              key: const Key('channel-row-open-chat'),
                              tooltip: 'Open Chat',
                              icon: AppIcons.chatBubble,
                              onTap: widget.onTap,
                            ),
                          if (widget.onInvite != null)
                            _RowAction(
                              key: const Key('channel-row-invite'),
                              tooltip: isVoice
                                  ? 'Invite to Voice'
                                  : 'Create Invite',
                              icon: AppIcons.personAdd,
                              onTap: widget.onInvite!,
                            ),
                          if (widget.onEdit != null)
                            _RowAction(
                              key: const Key('channel-row-settings'),
                              tooltip: 'Edit Channel',
                              icon: AppIcons.settings,
                              onTap: widget.onEdit!,
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // The unread pill on the column's edge.
            if (unread)
              Positioned(
                left: -_kChannelRowInset,
                top: (_kChannelRowHeight - 8) / 2,
                child: Container(
                  key: const Key('channel-unread-pill'),
                  width: 4,
                  height: 8,
                  decoration: BoxDecoration(
                    color: colors.dirtyWhite,
                    borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(4),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    if (!isVoice) return tileRow;
    final voiceTile = OnboardingAnchor(
      anchor: OnboardingAnchorId.voiceChannel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tileRow,
          VoiceParticipantList(
            channelId: channel.id,
            spaceId: widget.spaceId,
            onOpenChannel: widget.onTap,
            namesHidden: ref.watch(
              settingsControllerProvider.select(
                (s) => s.hidesVoiceNames(
                  ref.readActiveServerKey() ?? '',
                  channel.id,
                ),
              ),
            ),
          ),
          if (connectedHere && widget.onInvite != null)
            _InviteToVoiceRow(onTap: widget.onInvite!),
        ],
      ),
    );
    final spaceId = widget.spaceId;
    if (spaceId == null) return voiceTile;
    // Drop target for a moderator dragging a participant across channels.
    return DragTarget<VoiceMoveDrag>(
      onWillAcceptWithDetails: (details) =>
          details.data.canDropOn(spaceId, channel.id),
      onAcceptWithDetails: (details) =>
          moveVoiceParticipant(context, ref, details.data, channel.id),
      builder: (context, candidates, _) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_kChannelRowRadius),
          border: candidates.isEmpty
              ? null
              : Border.all(color: colors.green, width: 1.5),
        ),
        child: voiceTile,
      ),
    );
  }
}

/// The "Invite to Voice" row under the participants of the channel we are
/// connected to: a grey round invite glyph, the label and a chevron.
class _InviteToVoiceRow extends StatelessWidget {
  const _InviteToVoiceRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        _kChannelRowInset,
        1,
        _kChannelRowInset,
        1,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(_kChannelRowRadius),
        child: InkWell(
          key: const Key('voice-invite-row'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(_kChannelRowRadius),
          hoverColor: colors.hover,
          child: SizedBox(
            height: 32,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 8, 0),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: colors.hover,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      AppIcons.personAdd,
                      size: 14,
                      color: colors.gray,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Invite to Voice',
                      style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: colors.gray,
                      ),
                    ),
                  ),
                  Icon(AppIcons.chevronRight, size: 14, color: colors.gray),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A 16 px action icon at the end of a channel row (invite, settings, chat).
class _RowAction extends StatelessWidget {
  const _RowAction({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Tooltip(
        message: tooltip,
        child: _Hover(
          builder: (hovered) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Icon(
              icon,
              size: 16,
              color: hovered ? colors.dirtyWhite : colors.interactive,
            ),
          ),
        ),
      ),
    );
  }
}

/// Red pill rendering the mention count for a channel (or rolled up across a
/// space's channels in the rail). Caps at "99+". [ring] punches the badge out
/// of the surface it overlaps (the rail tile).
class _MentionBadge extends StatelessWidget {
  const _MentionBadge({required this.count, this.ring});

  final int count;
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    final text = count > 99 ? '99+' : count.toString();
    final badge = Container(
      constraints: const BoxConstraints(minWidth: 16),
      height: 16,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: kMentionBadgeColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          height: 1,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    if (ring == null) return badge;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: ring,
        borderRadius: BorderRadius.circular(10),
      ),
      child: badge,
    );
  }
}
