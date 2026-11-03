part of '../voice_view.dart';

/// A renderable tile: either a video track or a placeholder for [userId].
class _Tile {
  const _Tile({
    required this.userId,
    required this.name,
    required this.avatarUrl,
    required this.bg,
    required this.track,
    required this.isScreen,
    required this.muted,
    this.watching = true,
    this.previewHidden = false,
    this.viewers = 0,
    this.quality,
  });

  final String userId;
  final String name;
  final String? avatarUrl;
  final Color bg;
  final VideoTrack? track;
  final bool isScreen;
  final bool muted;

  /// False for a peer's screen share we haven't chosen to watch: the tile
  /// offers a "Watch Stream" button instead of the video.
  final bool watching;

  /// Our own screen share on a phone: the capture is the whole screen, so
  /// drawing it here would film itself — an endless mirror that kept the
  /// encoder at full load and froze Android phones. A card stands in.
  final bool previewHidden;

  /// How many members of the channel are watching this stream (stream tiles).
  final int viewers;

  /// The stream's resolution and frame rate, as "720P 30FPS", when known.
  final String? quality;

  /// Which tile is spotlighted: a person has a camera tile and, while
  /// sharing, a screen tile — by user id alone the camera tile won, so
  /// opening someone's screen share showed their avatar instead.
  String get spotlightKey => '$userId:${isScreen ? 'screen' : 'camera'}';
}

/// Who the members of the channel ([states]) report watching [streamerId].
int streamViewerCount(Iterable<AccordVoiceState> states, String streamerId) =>
    states
        .where((s) => s.streamWatching == streamerId && s.userId != streamerId)
        .length;

/// The quality badge of [userId]'s stream: our own from the share settings
/// ("720P 60FPS"); a peer's from the published size ("1080P"), frame rate
/// unknown; null while nothing is known.
String? streamQualityLabel(
  WidgetRef ref,
  VoiceSession? session,
  String userId, {
  required String? myId,
}) {
  if (userId == myId) {
    final settings = ref.read(settingsControllerProvider);
    final (_, height) = settings.screenShareDimensions;
    final size = height == 0 ? 'SOURCE' : '${height}P';
    return '$size ${settings.screenShareFps}FPS';
  }
  final dimensions = session?.remoteScreenDimensions(userId);
  if (dimensions == null || dimensions.height == 0) return null;
  return '${dimensions.height}P';
}

/// The in-call body: the video grid (or spotlight + strip).
class _ConnectedBody extends ConsumerWidget {
  const _ConnectedBody({
    required this.tileKeys,
    required this.channelId,
    required this.spaceId,
    required this.spotlightUserId,
    required this.onToggleSpotlight,
    this.only,
    this.edgeToEdge = false,
    this.stripHidden = false,
    this.onToggleStrip,
  });

  /// Drop the gutter around the spotlighted tile (full screen).
  final bool edgeToEdge;

  /// Whether the strip under the spotlighted tile is folded away, and the
  /// chevron that folds it (see `_VoiceChannelViewState._stripHidden`).
  final bool stripHidden;
  final VoidCallback? onToggleStrip;

  /// The owning view's tile keys (see `_VoiceChannelViewState._tileKeys`).
  final Map<String, GlobalKey> tileKeys;

  final String channelId;
  final String? spaceId;
  final String? spotlightUserId;
  final ValueChanged<String> onToggleSpotlight;

  /// Only these participants get tiles (a stage's speakers); everyone when
  /// null. Set, the body is laid out as a plain call.
  final Set<String>? only;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Rebuild on any room change (track added/removed, speaker changes).
    ref.watch(voiceControllerProvider.select((v) => v.tick));
    final states =
        ref
            .watch(
              voiceStatesControllerProvider(
                ref.readActiveServerKey() ?? '',
              ).select((cache) => cache[channelId]),
            )
            ?.values ??
        const [];
    final speaking = ref.watch(
      voiceControllerProvider.select((v) => v.speakingUserIds),
    );
    final members = spaceId == null
        ? null
        : ref.watch(
            accordMembersControllerProvider(
              ref.readActiveServerKey() ?? '',
              spaceId!,
            ),
          );
    final users = ref.watch(
      accordUsersControllerProvider(ref.readActiveServerKey() ?? ''),
    );
    final cdnUrl = ref.watchCdnUrl();
    final myId = ref.watchUserId();
    final session = ref.read(voiceControllerProvider.notifier).session;
    final stage = only == null && watchIsStage(ref, spaceId, channelId);
    if (stage) {
      final speakers = stageSpeakers(states);
      return Column(
        children: [
          Expanded(
            child: speakers.isEmpty
                ? const Center(child: Text('No one is on stage yet.'))
                : _ConnectedBody(
                    tileKeys: tileKeys,
                    channelId: channelId,
                    spaceId: spaceId,
                    spotlightUserId: spotlightUserId,
                    onToggleSpotlight: onToggleSpotlight,
                    only: {for (final s in speakers) s.userId},
                    edgeToEdge: edgeToEdge,
                    stripHidden: stripHidden,
                    onToggleStrip: onToggleStrip,
                  ),
          ),
          StageAudiencePanel(channelId: channelId, spaceId: spaceId!),
        ],
      );
    }

    // The share settings feed our own stream's quality badge.
    ref.watch(
      settingsControllerProvider.select(
        (s) => (s.screenShareResolution, s.screenShareFps),
      ),
    );
    final tiles = _buildTiles(
      ref: ref,
      states: only == null
          ? states
          : states.where((s) => only!.contains(s.userId)),
      allStates: states,
      members: members,
      users: users,
      cdnUrl: cdnUrl,
      ensure: ref
          .read(
            accordUsersControllerProvider(
              ref.readActiveServerKey() ?? '',
            ).notifier,
          )
          .ensure,
      myId: myId,
      session: session,
    );

    if (tiles.isEmpty) {
      return const Center(child: Text('Connecting…'));
    }

    final serverKey = ref.readActiveServerKey();
    final moderation = watchVoiceModerationRights(ref, spaceId);
    final voice = ref.read(voiceControllerProvider.notifier);

    void stopWatching(_Tile t) {
      // Stopping also drops the stream's spotlight: an unwatched tile is
      // only a "live" card and shouldn't fill the body.
      if (spotlightUserId == t.spotlightKey) onToggleSpotlight(t.spotlightKey);
      voice.setWatchingStream(t.userId, false);
    }

    void Function(Offset? position)? volumeMenuFor(_Tile t) =>
        serverKey == null || (t.userId == myId && !moderation.any)
        ? null
        : (position) => showUserVolumeMenu(
            context,
            serverKey: serverKey,
            userId: t.userId,
            name: t.name,
            globalPosition: position,
            spaceId: spaceId,
            channelId: channelId,
            showVolume: t.userId != myId,
            stream: t.isScreen,
          );

    // The tile's menu: right-click, long-press and the "…" button.
    void Function(Offset? position)? menuFor(_Tile t) {
      if (!t.isScreen) return volumeMenuFor(t);
      if (t.userId == myId) {
        return (position) => showStreamMenu(
          context,
          ref,
          globalPosition: position,
          popOutTrack: t.track,
        );
      }
      if (!t.watching) return null;
      // Stop Watching, Mute, Stream Volume (and Pop Out on the web), as in
      // other chat apps.
      return (position) => showUserVolumeMenu(
        context,
        serverKey: serverKey ?? '',
        userId: t.userId,
        name: t.name,
        globalPosition: position,
        spaceId: spaceId,
        channelId: channelId,
        stream: true,
        onStopWatching: () => stopWatching(t),
        onPopOut: t.track != null && canPopOutStream
            ? () => popOutStream(t.track!)
            : null,
      );
    }

    Widget tileWidget(_Tile t) => _VideoTile(
      key: tileKeys.putIfAbsent(t.spotlightKey, GlobalKey.new),
      tile: t,
      speaking: speaking.contains(t.userId),
      spotlighted: spotlightUserId == t.spotlightKey,
      // A click focuses the tile; a double click fills the window with it.
      onTap: () => onToggleSpotlight(t.spotlightKey),
      onDoubleTap: () {
        if (spotlightUserId != t.spotlightKey) {
          onToggleSpotlight(t.spotlightKey);
        }
        setVoiceViewExpanded(!voiceViewExpanded.value);
      },
      onWatch: !t.isScreen || t.userId == myId || t.watching
          ? null
          : () => voice.setWatchingStream(t.userId, true),
      onMenu: menuFor(t),
    );

    // Spotlight a chosen tile (or any active screen-share) above a strip.
    final spotlightIdx = spotlightUserId != null
        ? tiles.indexWhere((t) => t.spotlightKey == spotlightUserId)
        : _defaultSpotlight(tiles, myId);
    if (spotlightIdx >= 0 && tiles.length > 1) {
      return _SpotlightLayout(
        spotlight: tiles[spotlightIdx],
        rest: [
          for (var i = 0; i < tiles.length; i++)
            if (i != spotlightIdx) tiles[i],
        ],
        tileBuilder: tileWidget,
        edgeToEdge: edgeToEdge,
        stripHidden: stripHidden,
        onToggleStrip: onToggleStrip,
      );
    }

    return _GridLayout(tiles: tiles, tileBuilder: tileWidget);
  }

  /// Builds one [_Tile] per participant (plus one per active screen share) —
  /// pure data assembly, no widgets.
  List<_Tile> _buildTiles({
    required WidgetRef ref,
    required Iterable<AccordVoiceState> states,
    required Iterable<AccordVoiceState> allStates,
    required Map<String, AccordMember>? members,
    required Map<String, AccordUser>? users,
    required String? cdnUrl,
    required void Function(String) ensure,
    required String? myId,
    required VoiceSession? session,
  }) {
    final tiles = <_Tile>[];
    for (final vs in states) {
      final isMe = vs.userId == myId;
      final display = participantDisplay(
        vs.userId,
        members: members,
        users: users,
        cdnUrl: cdnUrl,
        ensure: ensure,
      );
      // Follow LiveKit's tracks, not just the voice-state flags: a flag that
      // lags (or never arrives) used to hide a live camera or screen share.
      final VideoTrack? camera = session == null
          ? null
          : isMe
          ? session.localCameraTrack
          : session.remoteCameraTrack(vs.userId);
      final person = _Tile(
        userId: vs.userId,
        name: display.name,
        avatarUrl: display.avatarUrl,
        bg: display.color,
        track: camera,
        isScreen: false,
        muted: vs.selfMute || vs.selfDeaf || vs.mute || vs.deaf || vs.suppress,
      );
      final VideoTrack? screen = session == null
          ? null
          : isMe
          ? session.localScreenTrack
          : session.remoteScreenTrack(vs.userId);
      // A peer's share stays unsubscribed until we watch it, so the tile
      // follows the publication (and the voice-state flag), not the track.
      final streaming =
          screen != null ||
          (session != null &&
              (vs.selfStream ||
                  (!isMe && session.remoteIsStreaming(vs.userId))));
      // A share comes before its owner's own tile, as in other chat apps.
      if (streaming) {
        tiles.add(
          _Tile(
            userId: vs.userId,
            name: display.name,
            avatarUrl: display.avatarUrl,
            bg: display.color,
            track: isMe && screenShareCapturesApp ? null : screen,
            isScreen: true,
            muted: false,
            watching: isMe || session!.isWatchingStream(vs.userId),
            previewHidden: isMe && screenShareCapturesApp,
            viewers: streamViewerCount(allStates, vs.userId),
            quality: streamQualityLabel(ref, session, vs.userId, myId: myId),
          ),
        );
      }
      tiles.add(person);
    }
    return tiles;
  }
}

/// One spotlighted tile filling the body above a strip of the remaining
/// tiles (16:9, as in other chat apps). A chevron on the strip's top edge
/// folds it away: the spotlight then runs edge to edge, the first other tile
/// floats small in the bottom-right corner, and the chevron sits at the
/// bottom to bring the strip back.
class _SpotlightLayout extends StatelessWidget {
  const _SpotlightLayout({
    required this.spotlight,
    required this.rest,
    required this.tileBuilder,
    this.edgeToEdge = false,
    this.stripHidden = false,
    this.onToggleStrip,
  });

  final _Tile spotlight;
  final List<_Tile> rest;
  final Widget Function(_Tile) tileBuilder;
  final bool edgeToEdge;
  final bool stripHidden;
  final VoidCallback? onToggleStrip;

  static const double _stripHeight = 90;

  /// The side inset that centres [count] strip tiles in a body [width] wide.
  static double _stripInset(int count, double width) {
    final tiles = count * (_stripHeight * 16 / 9 + 8);
    final inset = (width - tiles) / 2;
    return inset > 8 ? inset : 8;
  }

  @override
  Widget build(BuildContext context) {
    final chevron = onToggleStrip == null
        ? null
        : _StripChevron(hidden: stripHidden, onPressed: onToggleStrip!);

    if (stripHidden) {
      return Stack(
        fit: StackFit.expand,
        children: [
          tileBuilder(spotlight),
          if (rest.isNotEmpty)
            Positioned(
              right: 12,
              bottom: 12,
              width: 150,
              height: 84,
              child: tileBuilder(rest.first),
            ),
          if (chevron != null)
            Positioned(left: 0, right: 0, bottom: 8, child: chevron),
        ],
      );
    }

    final gutter = edgeToEdge ? 0.0 : 8.0;
    final video = Padding(
      padding: EdgeInsets.fromLTRB(gutter, gutter, gutter, 8),
      child: tileBuilder(spotlight),
    );
    return Column(
      children: [
        Expanded(child: video),
        SizedBox(
          height: _stripHeight + 8,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                top: 8,
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(
                    context,
                  ).copyWith(scrollbars: false),
                  child: LayoutBuilder(
                    builder: (context, constraints) => HorizontalWheelScroll(
                      builder: (context, controller) => ListView(
                        controller: controller,
                        scrollDirection: Axis.horizontal,
                        // Centred under the spotlight until the strip is
                        // wider than the body, then it scrolls.
                        padding: EdgeInsets.symmetric(
                          horizontal: _stripInset(
                            rest.length,
                            constraints.maxWidth,
                          ),
                        ),
                        children: [
                          for (final t in rest)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: AspectRatio(
                                aspectRatio: 16 / 9,
                                child: tileBuilder(t),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (chevron != null)
                Positioned(left: 0, right: 0, top: -6, child: chevron),
            ],
          ),
        ),
      ],
    );
  }
}

/// The small centred chevron that folds the participant strip under the
/// spotlighted tile away, and brings it back.
class _StripChevron extends StatelessWidget {
  const _StripChevron({required this.hidden, required this.onPressed});

  final bool hidden;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Center(
      child: Tooltip(
        message: hidden ? 'Show Members' : 'Hide Members',
        child: Material(
          color: colors.background,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            key: Key(hidden ? 'voice-strip-show' : 'voice-strip-hide'),
            borderRadius: BorderRadius.circular(16),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Icon(
                hidden ? AppIcons.keyboardArrowUp : AppIcons.keyboardArrowDown,
                size: 20,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The plain participant grid: 16:9 tiles sized to fill the body as large as
/// they can, in as many columns as that takes, centred both ways (a
/// three-tile call is two tiles over one centred tile), as in other chat
/// apps.
class _GridLayout extends StatelessWidget {
  const _GridLayout({required this.tiles, required this.tileBuilder});

  final List<_Tile> tiles;
  final Widget Function(_Tile) tileBuilder;

  static const double _gap = 8;

  /// The tile size that fills [width]x[height] for [count] tiles laid out
  /// in [columnsFor] columns.
  static Size fitTiles(int count, double width, double height) {
    final columns = columnsFor(count, width, height);
    final rows = (count / columns).ceil();
    final byWidth = (width - _gap * (columns - 1)) / columns;
    final byHeight = (height - _gap * (rows - 1)) / rows * 16 / 9;
    final tileWidth = byWidth < byHeight ? byWidth : byHeight;
    return Size(tileWidth, tileWidth * 9 / 16);
  }

  /// How many columns [count] tiles take: as square a grid as possible
  /// (two side by side, three as two over one, four as 2×2, five to nine in
  /// three columns), one fewer in a portrait body.
  static int columnsFor(int count, double width, double height) {
    if (count <= 1) return 1;
    var columns = math.sqrt(count).ceil();
    if (width < height && columns > 1) columns -= 1;
    return columns;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = fitTiles(
            tiles.length,
            constraints.maxWidth,
            constraints.maxHeight,
          );
          return Center(
            child: Wrap(
              spacing: _gap,
              runSpacing: _gap,
              alignment: WrapAlignment.center,
              runAlignment: WrapAlignment.center,
              children: [
                for (final t in tiles)
                  SizedBox(
                    width: size.width,
                    height: size.height,
                    child: tileBuilder(t),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _VideoTile extends StatefulWidget {
  const _VideoTile({
    super.key,
    required this.tile,
    required this.speaking,
    required this.spotlighted,
    required this.onTap,
    required this.onDoubleTap,
    this.onWatch,
    this.onMenu,
  });

  final _Tile tile;
  final bool speaking;
  final bool spotlighted;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;

  /// Starts watching this peer's stream. Null for anything but a peer's
  /// unwatched screen tile.
  final VoidCallback? onWatch;

  /// The tile's menu (right-click position, null on long-press / the "…"
  /// button): our stream's menu, a watched stream's menu, or the local
  /// volume menu for a person. Null when there is nothing to offer.
  final void Function(Offset? position)? onMenu;

  @override
  State<_VideoTile> createState() => _VideoTileState();
}

class _VideoTileState extends State<_VideoTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final tile = widget.tile;
    final initial = accordInitial(tile.name);
    final openMenu = widget.onMenu;
    final live = tile.isScreen && !tile.previewHidden;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        onSecondaryTapUp: openMenu == null
            ? null
            : (d) => openMenu(d.globalPosition),
        onLongPress: openMenu == null ? null : () => openMenu(null),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: colors.foreground,
            borderRadius: BorderRadius.circular(8),
            border: widget.speaking
                ? Border.all(color: colors.green, width: 2)
                : null,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (tile.previewHidden)
                const _SharingCard()
              else if (tile.isScreen && !tile.watching)
                _LiveCard(tile: tile, onWatch: widget.onWatch)
              else if (tile.track != null)
                lk.VideoTrackRenderer(
                  tile.track!,
                  fit: tile.isScreen
                      ? lk.VideoViewFit.contain
                      : lk.VideoViewFit.cover,
                )
              else
                Center(
                  child: AccordMemberAvatar(
                    avatarUrl: tile.avatarUrl,
                    initial: initial,
                    radius: 28,
                    backgroundColor: tile.bg,
                    initialStyle: const TextStyle(fontSize: 20),
                  ),
                ),
              if (live && tile.watching)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (tile.viewers > 0) ...[
                        _StreamBadge(
                          key: Key('stream-viewers-${tile.userId}'),
                          icon: AppIcons.visibility,
                          label: '${tile.viewers}',
                        ),
                        const SizedBox(width: 4),
                      ],
                      if (tile.quality != null) ...[
                        _StreamBadge(label: tile.quality!),
                        const SizedBox(width: 4),
                      ],
                      const LiveBadge(),
                    ],
                  ),
                ),
              Positioned(
                left: 8,
                bottom: 8,
                right: 48,
                child: _NamePill(
                  name: tile.name,
                  icon: tile.isScreen
                      ? AppIcons.desktopWindowsOutlined
                      : tile.muted
                      ? AppIcons.micOff
                      : null,
                ),
              ),
              if (openMenu != null &&
                  (_hover || !shouldUseDesktopLayout(context)))
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: _TileMenuButton(
                    key: Key(
                      '${tile.isScreen ? 'stream' : 'tile'}-menu-${tile.userId}',
                    ),
                    onPressed: openMenu,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The red "LIVE" pill marking a screen share, on tiles, in the channel list
/// and on the stream card.
class LiveBadge extends StatelessWidget {
  const LiveBadge({super.key, this.small = false});

  /// The channel-list size (a little shorter than the tile one).
  final bool small;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 5 : 6, vertical: 1),
      decoration: BoxDecoration(
        color: colors.red,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'LIVE',
        style: TextStyle(
          color: Colors.white,
          fontSize: small ? 10 : 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
          height: 1.3,
        ),
      ),
    );
  }
}

/// A dark pill beside the LIVE badge: the stream's quality, or its viewers.
class _StreamBadge extends StatelessWidget {
  const _StreamBadge({super.key, required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: Colors.white),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// The name pill in a tile's bottom-left corner, with the muted-mic icon or
/// the screen icon of a stream in front of the name.
class _NamePill extends StatelessWidget {
  const _NamePill({required this.name, this.icon});

  final String name;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The "…" in a tile's bottom-right corner, shown on hover (always on touch).
class _TileMenuButton extends StatelessWidget {
  const _TileMenuButton({super.key, required this.onPressed});

  final void Function(Offset? position) onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onPressed(menuAnchorOf(context)),
        child: const SizedBox(
          width: 32,
          height: 32,
          child: Icon(AppIcons.moreHoriz, size: 18, color: Colors.white),
        ),
      ),
    );
  }
}

/// A peer's screen share we aren't receiving: their avatar, a LIVE badge and
/// the button that starts the stream, as in other chat apps.
class _LiveCard extends StatelessWidget {
  const _LiveCard({required this.tile, required this.onWatch});

  final _Tile tile;
  final VoidCallback? onWatch;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AccordMemberAvatar(
              avatarUrl: tile.avatarUrl,
              initial: accordInitial(tile.name),
              radius: 24,
              backgroundColor: tile.bg,
              initialStyle: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 12),
            _TileButton(
              key: Key('watch-stream-${tile.userId}'),
              label: 'Watch Stream',
              icon: AppIcons.desktopWindowsOutlined,
              onPressed: onWatch,
              primary: true,
            ),
          ],
        ),
        const Positioned(right: 8, top: 8, child: LiveBadge()),
      ],
    );
  }
}

/// Stands in for our own screen share where previewing it would film itself
/// (see [_Tile.previewHidden]).
class _SharingCard extends StatelessWidget {
  const _SharingCard();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(AppIcons.screenShare, size: 32),
        SizedBox(height: 8),
        Text(
          "You're sharing your screen",
          key: Key('own-share-card'),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// A compact pill button drawn over a video tile.
class _TileButton extends StatelessWidget {
  const _TileButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: primary ? colors.primary : Colors.black54,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      icon: Icon(icon, size: 16),
      label: Text(label),
    );
  }
}

/// The tile spotlighted when nobody picked one: a peer's screen share we
/// watch (what you came to watch). Our own share stays in the grid, as in
/// other chat apps; a live card we don't watch stays there too.
int _defaultSpotlight(List<_Tile> tiles, String? myId) =>
    tiles.indexWhere((t) => t.isScreen && t.userId != myId && t.watching);
