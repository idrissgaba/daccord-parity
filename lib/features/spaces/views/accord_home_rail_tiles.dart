part of 'accord_home.dart';

/// Side of a rail tile.
const double _kRailTileSize = 40;

/// Gap between rail tiles (the pitch is the tile plus this gap); the
/// insertion gaps between items provide it.
const double _kRailGap = 8;

/// Corner radius of a tile at rest (a circle) and once hovered or selected (a
/// rounded square).
const double _kRailRestRadius = _kRailTileSize / 2;
const double _kRailActiveRadius = 12;

/// Payload carried while dragging a rail item, so a drop target can tell a
/// space drag (reorder / move between folders) from a folder drag (reorder the
/// whole folder) without overloading a bare id string.
sealed class _RailDrag {
  const _RailDrag();
}

class _SpaceDrag extends _RailDrag {
  const _SpaceDrag(this.spaceId);
  final String spaceId;
}

class _FolderDrag extends _RailDrag {
  const _FolderDrag(this.folderId);
  final String folderId;
}

/// A drop zone occupying the track between two rail items, so a space or folder
/// can be inserted *at* that position (e.g. between a space and a folder)
/// instead of only onto an icon. Grows and shows an insertion bar while a
/// compatible drag hovers it. At rest it is the 8 px gap between tiles.
class _InsertionGap extends StatelessWidget {
  const _InsertionGap({required this.onDropSpace, required this.onDropFolder});

  /// A space [spaceId] was dropped in this gap: place it here as a standalone
  /// rail entry (pulled out of any folder it was in).
  final ValueChanged<String> onDropSpace;

  /// A folder [folderId] was dropped in this gap: move the whole folder here.
  final ValueChanged<String> onDropFolder;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return DragTarget<_RailDrag>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (d) {
        switch (d.data) {
          case _SpaceDrag(:final spaceId):
            onDropSpace(spaceId);
          case _FolderDrag(:final folderId):
            onDropFolder(folderId);
        }
      },
      builder: (context, candidate, _) {
        final active = candidate.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: active ? 24 : _kRailGap,
          alignment: Alignment.center,
          child: active
              ? Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                )
              : null,
        );
      },
    );
  }
}

/// A space icon that can be dragged to reorder (drop in the gaps between tiles)
/// or to group: dropping another space *onto* it merges the two into a new
/// folder, and dropping a folder onto it reorders that folder before this
/// space.
class _DraggableSpace extends StatelessWidget {
  const _DraggableSpace({
    required this.space,
    required this.cdnUrl,
    required this.selected,
    required this.onTap,
    required this.onMergeSpace,
    required this.onDropFolderBefore,
    required this.onMenu,
    required this.entityKey,
    this.serverKey = '',
  });

  final AccordSpace space;
  final String? cdnUrl;
  final bool selected;
  final VoidCallback onTap;

  /// A space [spaceId] was dropped *onto* this tile: group the two into a new
  /// folder (drop between tiles to reorder instead).
  final ValueChanged<String> onMergeSpace;

  /// A folder [folderId] was dropped on this tile: move the whole folder before
  /// this space.
  final ValueChanged<String> onDropFolderBefore;

  /// Open the space's management menu: anchored at [position] (desktop
  /// right-click) or as a sheet when it is null (touch long-press).
  final void Function(Offset? position) onMenu;
  final String serverKey;
  final String entityKey;

  @override
  Widget build(BuildContext context) {
    final icon = _SpaceIcon(
      space: space,
      selected: selected,
      cdnUrl: cdnUrl,
      serverKey: serverKey,
      onTap: onTap,
    );
    return DragTarget<_RailDrag>(
      onWillAcceptWithDetails: (d) => switch (d.data) {
        _SpaceDrag(:final spaceId) => spaceId != entityKey,
        _FolderDrag() => true,
      },
      onAcceptWithDetails: (d) {
        switch (d.data) {
          case _SpaceDrag(:final spaceId):
            onMergeSpace(spaceId);
          case _FolderDrag(:final folderId):
            onDropFolderBefore(folderId);
        }
      },
      builder: (context, candidate, _) => Opacity(
        opacity: candidate.isNotEmpty ? 0.5 : 1,
        child: RailDraggable<_RailDrag>(
          data: _SpaceDrag(entityKey),
          tooltip: space.name,
          feedback: Material(
            color: Colors.transparent,
            child: _SpaceIcon(
              space: space,
              selected: false,
              cdnUrl: cdnUrl,
              serverKey: serverKey,
              onTap: () {},
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.3, child: icon),
          // Drag drives reorder / grouping; the management menu (new folder,
          // move/remove, leave) opens via long-press on touch and right-click on
          // desktop so it stays reachable everywhere.
          onMenu: onMenu,
          child: icon,
        ),
      ),
    );
  }
}

/// The unread / mention roll-up of one space on [serverKey], filtered by the
/// user's mute settings so the rail agrees with the notification gate.
({bool unread, int mentions}) _watchSpaceBadges(
  WidgetRef ref,
  String serverKey,
  String spaceId,
) {
  final spaceMuted = ref.watch(
    settingsControllerProvider.select(
      (s) => s.isSpaceMuted(serverKey, spaceId),
    ),
  );
  // `channelNotificationsFor` builds a fresh map, so the stored map is watched
  // instead.
  ref.watch(settingsControllerProvider.select((s) => s.channelNotifications));
  final channelLevels = ref
      .read(settingsControllerProvider)
      .channelNotificationsFor(serverKey);
  return ref.watch(
    readStateControllerProvider(serverKey).select(
      (readState) => (
        unread: readState.spaceShowsUnread(
          spaceId,
          spaceMuted: spaceMuted,
          channelLevels: channelLevels,
        ),
        mentions: readState.visibleMentionsInSpace(
          spaceId,
          spaceMuted: spaceMuted,
          channelLevels: channelLevels,
        ),
      ),
    ),
  );
}

class _SpaceIcon extends ConsumerWidget {
  const _SpaceIcon({
    required this.space,
    required this.selected,
    required this.cdnUrl,
    required this.onTap,
    this.serverKey = '',
  });

  final AccordSpace space;
  final bool selected;
  final String? cdnUrl;

  /// Null where the icon is shown for identification only (the hidden-servers
  /// sheet, whose row action is its own "Unhide" button) — a no-op `onTap`
  /// would present the icon as interactive when it isn't (#306).
  final VoidCallback? onTap;

  /// The connection that owns this space, so the unread badge reads that
  /// server's read state (snowflakes collide across servers).
  final String serverKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    // Only the slices that matter are watched, so an unrelated settings write
    // (a draft keystroke) or another space's read state can't rebuild every
    // rail icon.
    final (:unread, :mentions) = _watchSpaceBadges(ref, serverKey, space.id);
    final hasUnread = !selected && unread;
    // Dim the icon while its server's gateway is down, so an unreachable space
    // reads as offline rather than just unselected.
    final unreachable =
        serverKey.isNotEmpty &&
        (ref
                .watch(
                  connectionsControllerProvider.select(
                    (s) => s.connectionFor(serverKey)?.status,
                  ),
                )
                ?.isUnreachable ??
            false);
    // The green speaker badge of the space whose voice channel we are in.
    final inVoiceHere = ref.watch(
      voiceControllerProvider.select(
        (v) => v.isConnected && v.spaceId == space.id,
      ),
    );
    // No tooltip here: in the rail, [RailDraggable] owns the name tooltip (its
    // long-press trigger must not compete with the drag / menu gesture), and
    // the other host — the hidden-servers sheet — prints the name beside it.
    return _RailTile(
      selected: selected,
      unread: hasUnread,
      mentions: mentions,
      voice: inVoiceHere,
      onTap: onTap,
      activeColor: colors.primary,
      restColor: colors.background,
      builder: (hovered) => Opacity(
        opacity: unreachable ? 0.4 : 1.0,
        child: _SpaceIconImage(space: space, cdnUrl: cdnUrl),
      ),
    );
  }
}

/// The common rail tile: a 40 px square that is a circle at rest and a rounded
/// square once hovered or selected (150 ms), with the white pill on the rail's
/// edge saying unread (short), hovered (medium) or selected (tall), and the
/// red mention badge punched out of the bottom-right corner.
class _RailTile extends StatelessWidget {
  const _RailTile({
    required this.selected,
    required this.unread,
    required this.mentions,
    required this.onTap,
    required this.activeColor,
    required this.restColor,
    required this.builder,
    this.alwaysSquare = false,
    this.voice = false,
    this.foregroundColor,
    this.activeForegroundColor,
  });

  final bool selected;
  final bool unread;
  final int mentions;

  /// We are in a voice channel of this space: a green speaker badge on the
  /// tile's top-right corner.
  final bool voice;
  final VoidCallback? onTap;

  /// Background once hovered or selected, and at rest.
  final Color activeColor;
  final Color restColor;

  /// A rounded square at rest too (folders), instead of a circle.
  final bool alwaysSquare;

  /// Icon tint at rest / when active, for icon tiles; null leaves the child
  /// to pick its own.
  final Color? foregroundColor;
  final Color? activeForegroundColor;

  final Widget Function(bool hovered) builder;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Center(
      child: _Hover(
        builder: (hovered) {
          final active = selected || hovered;
          final radius = BorderRadius.circular(
            active || alwaysSquare ? _kRailActiveRadius : _kRailRestRadius,
          );
          final pillHeight = selected
              ? 40.0
              : hovered
              ? 20.0
              : unread
              ? 8.0
              : 0.0;
          final tint = active
              ? (activeForegroundColor ?? foregroundColor)
              : foregroundColor;
          return GestureDetector(
            onTap: onTap,
            child: MouseRegion(
              cursor: onTap == null
                  ? MouseCursor.defer
                  : SystemMouseCursors.click,
              child: SizedBox(
                width: _kRailTileSize,
                height: _kRailTileSize,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // The pill sits on the rail's left edge, 16 px left of
                    // the tile, 4 px wide.
                    Positioned(
                      left: -16,
                      top: (_kRailTileSize - pillHeight) / 2,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 4,
                        height: pillHeight,
                        decoration: BoxDecoration(
                          color: colors.dirtyWhite,
                          borderRadius: const BorderRadius.horizontal(
                            right: Radius.circular(4),
                          ),
                        ),
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: _kRailTileSize,
                      height: _kRailTileSize,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: active ? activeColor : restColor,
                        borderRadius: radius,
                      ),
                      alignment: Alignment.center,
                      child: tint == null
                          ? builder(hovered)
                          : IconTheme.merge(
                              data: IconThemeData(color: tint),
                              child: builder(hovered),
                            ),
                    ),
                    if (mentions > 0)
                      Positioned(
                        right: -4,
                        bottom: -4,
                        child: _MentionBadge(
                          count: mentions,
                          ring: colors.foreground,
                        ),
                      ),
                    if (voice)
                      Positioned(
                        right: -4,
                        top: -4,
                        child: Container(
                          key: const Key('rail-voice-badge'),
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: colors.foreground,
                            shape: BoxShape.circle,
                          ),
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: colors.green,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              AppIcons.volumeUp,
                              size: 10,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Rebuilds [builder] with whether the pointer is over it.
class _Hover extends StatefulWidget {
  const _Hover({required this.builder});

  final Widget Function(bool hovered) builder;

  @override
  State<_Hover> createState() => _HoverState();
}

class _HoverState extends State<_Hover> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: widget.builder(_hovered),
  );
}

/// Image and initials shared by ordinary rail tiles and folder miniatures.
/// Interaction, clipping, selection, and unread badges belong to the host tile.
class _SpaceIconImage extends StatelessWidget {
  const _SpaceIconImage({
    required this.space,
    required this.cdnUrl,
    this.size = _kRailTileSize,
  });

  final AccordSpace space;
  final String? cdnUrl;
  final double size;

  String get _initials => accordSpaceInitials(space.name);

  @override
  Widget build(BuildContext context) {
    final iconUrl = accordSpaceIconUrl(space, cdnUrl);
    final fallback = Center(
      child: Text(
        _initials,
        style: Theme.of(context).textTheme.titleSmall!.copyWith(
          color: Colors.white,
          fontSize: size < _kRailTileSize ? size / 2 : 15,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
    return SizedBox.square(
      dimension: size,
      child: iconUrl == null
          ? fallback
          : CachedNetworkImage(
              imageUrl: iconUrl,
              width: size,
              height: size,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
              placeholder: (_, _) => fallback,
              errorWidget: (_, _, _) => fallback,
            ),
    );
  }
}

/// A utility tile of the rail (home, add a server, discover, download): a
/// translucent grey circle with one icon at rest, a tinted rounded square once
/// hovered, with the tile name in a tooltip to its right. Backs the DM,
/// add-server, discover, download and hidden-servers affordances below.
class _RailIconTile extends StatelessWidget {
  const _RailIconTile({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.iconSize = 20,
    this.selected = false,
    this.hasUnread = false,
    this.mentionCount = 0,
    this.activeColor,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final double iconSize;
  final bool selected;
  final bool hasUnread;
  final int mentionCount;

  /// Hover / selection fill; defaults to the accent.
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return RailTooltip(
      message: tooltip,
      child: _RailTile(
        selected: selected,
        unread: hasUnread,
        mentions: mentionCount,
        onTap: onTap,
        activeColor: activeColor ?? colors.primary,
        restColor: colors.interactive.withValues(alpha: 0.12),
        foregroundColor: colors.dirtyWhite,
        activeForegroundColor: Colors.white,
        builder: (_) => Icon(icon, size: iconSize),
      ),
    );
  }
}

/// The Direct Messages affordance pinned at the top of the rail, styled as a
/// space-icon tile (the "home" button of other chat apps). Opens the
/// DM/friends view; selected while no space is.
class _DirectMessagesButton extends ConsumerWidget {
  const _DirectMessagesButton({required this.onTap, required this.selected});

  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connections = ref.watch(
      connectionsControllerProvider.select((state) => state.connections),
    );
    // The stored map, not a per-server copy, so other settings writes don't
    // rebuild this tile.
    ref.watch(settingsControllerProvider.select((s) => s.channelNotifications));
    final settings = ref.read(settingsControllerProvider);
    var hasUnread = false;
    var mentions = 0;
    for (final connection in connections) {
      final levels = settings.channelNotificationsFor(connection.key);
      final summary = ref.watch(
        readStateControllerProvider(connection.key).select((snapshot) {
          var unread = false;
          var count = 0;
          for (final entry in snapshot.entries.values) {
            if (entry.spaceId != null ||
                !UnreadIndicatorGate.countsTowardSpace(
                  spaceMuted: false,
                  channelLevel: levels[entry.channelId],
                )) {
              continue;
            }
            unread = true;
            count += entry.mentions;
          }
          return (hasUnread: unread, mentions: count);
        }),
      );
      hasUnread = hasUnread || summary.hasUnread;
      mentions += summary.mentions;
    }
    return _RailIconTile(
      key: const Key('rail-direct-messages'),
      tooltip: 'Direct Messages',
      icon: AppIcons.chatBubble,
      iconSize: 24,
      selected: selected,
      hasUnread: hasUnread,
      mentionCount: mentions,
      onTap: onTap,
    );
  }
}

/// The "Add a Server" (+) affordance at the foot of the rail's space list.
class _AddServerButton extends StatelessWidget {
  const _AddServerButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _RailIconTile(
    key: const Key('rail-add-server'),
    tooltip: 'Add a Server',
    icon: AppIcons.add,
    activeColor: BonfireThemeExtension.of(context).green,
    onTap: onTap,
  );
}

/// The "Discover" (compass) affordance, below "+".
class _ExploreButton extends StatelessWidget {
  const _ExploreButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _RailIconTile(
    key: const Key('rail-explore'),
    tooltip: 'Discover',
    icon: AppIcons.explore,
    activeColor: BonfireThemeExtension.of(context).green,
    onTap: onTap,
  );
}

/// The "Download Apps" affordance, below "Discover": opens the releases page
/// of this build's distribution.
class _DownloadAppsButton extends StatelessWidget {
  const _DownloadAppsButton();

  @override
  Widget build(BuildContext context) => _RailIconTile(
    key: const Key('rail-download-apps'),
    tooltip: 'Download Apps',
    icon: AppIcons.download,
    activeColor: BonfireThemeExtension.of(context).green,
    onTap: () => launchUrl(
      Uri.parse('https://github.com/$kUpdateRepo/releases'),
      mode: LaunchMode.externalApplication,
    ),
  );
}

/// A small affordance at the foot of the rail showing how many servers are
/// hidden; tapping it opens the restore sheet.
class _HiddenServersButton extends StatelessWidget {
  const _HiddenServersButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _RailIconTile(
    tooltip: '$count hidden ${count == 1 ? 'server' : 'servers'}',
    icon: AppIcons.visibilityOffOutlined,
    onTap: onTap,
  );
}
