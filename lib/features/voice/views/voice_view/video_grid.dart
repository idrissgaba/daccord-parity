part of '../voice_view.dart';

/// The fill of a person's tile when they chose no accent colour.
const _kNeutralTile = Color(0xFFDDDEE2);

/// A renderable tile: either a video track or a placeholder for [userId].
class _Tile {
  const _Tile({
    required this.userId,
    required this.name,
    required this.avatarUrl,
    required this.bg,
    required this.avatarColor,
    required this.track,
    required this.isScreen,
    required this.muted,
    this.deafened = false,
    this.serverMuted = false,
    this.serverDeafened = false,
    this.watching = true,
    this.previewHidden = false,
    this.viewers = 0,
    this.quality,
  });

  final String userId;
  final String name;
  final String? avatarUrl;

  /// The tile's fill: the person's chosen accent colour, else the neutral
  /// light grey other chat apps use.
  final Color bg;

  /// The imageless avatar's own colour.
  final Color avatarColor;
  final VideoTrack? track;
  final bool isScreen;

  /// Not transmitting voice, for any reason (own mute, deafen, server mute or
  /// deafen, stage suppression).
  final bool muted;

  /// Their own deafen (a crossed headset rather than a crossed mic).
  final bool deafened;

  /// A moderator's mute / deafen: the same icons, in red.
  final bool serverMuted;
  final bool serverDeafened;

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
    this.showNonVideo = true,
    this.onShowNonVideo,
    this.revealNames = false,
  });

  /// Whether participants without a camera or share keep a tile while
  /// someone has video ("Show Non-Video Participants" in the tile menu).
  final bool showNonVideo;
  final ValueChanged<bool>? onShowNonVideo;

  /// The pointer rests on the call view: every tile names itself, as in
  /// other chat apps (the control bar appears on the same cue).
  final bool revealNames;

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
    // Playing a soundboard sound rings the tile like speaking does.
    final speaking = {
      ...ref.watch(voiceControllerProvider.select((v) => v.speakingUserIds)),
      ...watchSoundboardPlayers(ref),
    };
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
                    showNonVideo: showNonVideo,
                    onShowNonVideo: onShowNonVideo,
                    revealNames: revealNames,
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
    // "Show Non-Video Participants" off: once anyone has video, the
    // avatar-only tiles step aside.
    final anyVideo = tiles.any(
      (t) => t.track != null || (t.isScreen && !t.previewHidden),
    );
    if (!showNonVideo && anyVideo) {
      tiles.removeWhere((t) => t.track == null && !t.isScreen);
    }

    final serverKey = ref.readActiveServerKey();
    final voice = ref.read(voiceControllerProvider.notifier);

    void stopWatching(_Tile t) {
      // Stopping also drops the stream's spotlight: an unwatched tile is
      // only a "live" card and shouldn't fill the body.
      if (spotlightUserId == t.spotlightKey) onToggleSpotlight(t.spotlightKey);
      voice.setWatchingStream(t.userId, false);
    }

    void Function(Offset? position)? participantMenuFor(_Tile t) =>
        serverKey == null
        ? null
        : (position) => showVoiceParticipantMenu(
            context,
            ref,
            serverKey: serverKey,
            userId: t.userId,
            name: t.name,
            globalPosition: position,
            spaceId: spaceId,
            channelId: channelId,
            showNonVideoParticipants: onShowNonVideo == null
                ? null
                : showNonVideo,
            onShowNonVideoParticipants: onShowNonVideo,
          );

    // The tile's menu: right-click, long-press and the "…" button.
    void Function(Offset? position)? menuFor(_Tile t) {
      if (!t.isScreen) return participantMenuFor(t);
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
      return (position) => showWatchedStreamMenu(
        context,
        ref,
        serverKey: serverKey ?? '',
        userId: t.userId,
        name: t.name,
        globalPosition: position,
        onStopWatching: () => stopWatching(t),
        onPopOut: t.track != null && canPopOutStream
            ? () => popOutStream(t.track!)
            : null,
        showNonVideoParticipants: onShowNonVideo == null ? null : showNonVideo,
        onShowNonVideoParticipants: onShowNonVideo,
      );
    }

    // Spotlight a chosen tile (or any active screen-share) above a strip.
    final spotlightIdx = spotlightUserId != null
        ? tiles.indexWhere((t) => t.spotlightKey == spotlightUserId)
        : _defaultSpotlight(tiles, myId);
    final spotlightKey = spotlightIdx >= 0 && tiles.length > 1
        ? tiles[spotlightIdx].spotlightKey
        : null;

    Widget tileWidget(_Tile t, {bool compact = false}) => _VideoTile(
      key: tileKeys.putIfAbsent(t.spotlightKey, GlobalKey.new),
      tile: t,
      speaking: speaking.contains(t.userId),
      spotlighted: spotlightKey == t.spotlightKey,
      compact: compact,
      revealNames: revealNames,
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

    if (spotlightKey != null) {
      return _SpotlightLayout(
        spotlight: tiles[spotlightIdx],
        all: tiles,
        tileBuilder: tileWidget,
        edgeToEdge: edgeToEdge,
        stripHidden: stripHidden,
        onToggleStrip: onToggleStrip,
      );
    }

    // Alone in the channel: the panel inviting people in (and offering the
    // Arcade) takes the slot beside our tile(s), as in other chat apps.
    final alone = only == null && spaceId != null && states.length == 1;
    return _GridLayout(
      tiles: tiles,
      tileBuilder: (t) => tileWidget(t),
      extra: alone
          ? _AlonePanel(serverKey: serverKey ?? '', spaceId: spaceId!)
          : null,
    );
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
        bg: display.accent ?? _kNeutralTile,
        avatarColor: display.color,
        track: camera,
        isScreen: false,
        muted: vs.selfMute || vs.selfDeaf || vs.mute || vs.deaf || vs.suppress,
        deafened: vs.selfDeaf,
        serverMuted: vs.mute,
        serverDeafened: vs.deaf,
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
            bg: display.accent ?? _kNeutralTile,
            avatarColor: display.color,
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

/// One spotlighted tile filling the body above a strip of every tile
/// (16:9, 110 px, as in other chat apps; the spotlighted one is dimmed there
/// and never renders its video twice). A chevron on the strip's top edge
/// folds it away: the spotlight then runs edge to edge, the first other tile
/// floats small in the bottom-right corner, and the chevron sits above the
/// controls to bring the strip back.
class _SpotlightLayout extends StatelessWidget {
  const _SpotlightLayout({
    required this.spotlight,
    required this.all,
    required this.tileBuilder,
    this.edgeToEdge = false,
    this.stripHidden = false,
    this.onToggleStrip,
  });

  final _Tile spotlight;
  final List<_Tile> all;
  final Widget Function(_Tile, {bool compact}) tileBuilder;
  final bool edgeToEdge;
  final bool stripHidden;
  final VoidCallback? onToggleStrip;

  static const double _stripHeight = 110;
  static const double _stripGap = 8;

  /// The side inset that centres [count] strip tiles in a body [width] wide.
  static double _stripInset(int count, double width) {
    final tiles = count * (_stripHeight * 16 / 9 + _stripGap);
    final inset = (width - tiles) / 2;
    return inset > 8 ? inset : 8;
  }

  Widget _stripTile(_Tile t) => t.spotlightKey == spotlight.spotlightKey
      ? _FocusedStripStub(tile: t)
      : tileBuilder(t, compact: true);

  @override
  Widget build(BuildContext context) {
    final chevron = onToggleStrip == null
        ? null
        : _StripChevron(hidden: stripHidden, onPressed: onToggleStrip!);
    final others = [
      for (final t in all)
        if (t.spotlightKey != spotlight.spotlightKey) t,
    ];

    if (stripHidden) {
      return Stack(
        fit: StackFit.expand,
        children: [
          tileBuilder(spotlight),
          if (others.isNotEmpty)
            Positioned(
              right: 16,
              bottom: 94,
              width: 160,
              height: 90,
              child: tileBuilder(others.first, compact: true),
            ),
          if (chevron != null)
            Positioned(left: 0, right: 0, bottom: 112, child: chevron),
        ],
      );
    }

    // The spotlighted tile keeps 16:9, centred, 40 px clear of the header,
    // as in other chat apps; only the folded-strip view runs edge to edge.
    final gutter = edgeToEdge ? 0.0 : 8.0;
    final video = Padding(
      padding: EdgeInsets.fromLTRB(gutter, 40, gutter, _stripGap),
      child: Center(
        child: AspectRatio(aspectRatio: 16 / 9, child: tileBuilder(spotlight)),
      ),
    );
    return Column(
      children: [
        Expanded(child: video),
        SizedBox(
          height: _stripHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
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
                            all.length,
                            constraints.maxWidth,
                          ),
                        ),
                        children: [
                          for (final t in all)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: _stripGap / 2,
                              ),
                              child: AspectRatio(
                                aspectRatio: 16 / 9,
                                child: _stripTile(t),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (chevron != null)
                Positioned(left: 0, right: 0, top: -14, child: chevron),
            ],
          ),
        ),
      ],
    );
  }
}

/// The strip's copy of the spotlighted tile: dimmed, with no video (a second
/// renderer of the same track crashes the engine on Windows) and an eye for
/// "this is what's on the big tile".
class _FocusedStripStub extends StatelessWidget {
  const _FocusedStripStub({required this.tile});

  final _Tile tile;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Container(
      key: Key('voice-strip-focused-${tile.spotlightKey}'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: tile.isScreen ? colors.raised : tile.bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (!tile.isScreen)
            Center(
              child: AccordMemberAvatar(
                avatarUrl: tile.avatarUrl,
                initial: accordInitial(tile.name),
                radius: 20,
                backgroundColor: tile.avatarColor,
                initialStyle: const TextStyle(fontSize: 14),
              ),
            ),
          ColoredBox(color: Colors.black.withValues(alpha: 0.5)),
          const Center(
            child: Icon(AppIcons.visibility, size: 24, color: Colors.white),
          ),
          if (tile.isScreen)
            const Positioned(right: 8, top: 8, child: LiveBadge()),
          Positioned(
            left: 8,
            bottom: 8,
            right: 8,
            child: _NamePill(
              name: tile.name,
              icon: tile.isScreen ? AppIcons.desktopWindowsOutlined : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// The small centred chevron pill that folds the participant strip under the
/// spotlighted tile away, and brings it back.
class _StripChevron extends StatelessWidget {
  const _StripChevron({required this.hidden, required this.onPressed});

  final bool hidden;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Tooltip(
        message: hidden ? 'Show Members' : 'Hide Members',
        child: Material(
          color: const Color(0xFF202024),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            key: Key(hidden ? 'voice-strip-show' : 'voice-strip-hide'),
            borderRadius: BorderRadius.circular(14),
            onTap: onPressed,
            child: SizedBox(
              width: 44,
              height: 28,
              child: Icon(
                hidden ? AppIcons.keyboardArrowUp : AppIcons.keyboardArrowDown,
                size: 16,
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
  const _GridLayout({
    required this.tiles,
    required this.tileBuilder,
    this.extra,
  });

  final List<_Tile> tiles;
  final Widget Function(_Tile) tileBuilder;

  /// A last cell laid out like a tile (the "alone" panel).
  final Widget? extra;

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
            tiles.length + (extra == null ? 0 : 1),
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
                if (extra != null)
                  SizedBox(
                    width: size.width,
                    height: size.height,
                    child: extra,
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
    this.compact = false,
    this.revealNames = false,
    this.onWatch,
    this.onMenu,
  });

  final _Tile tile;
  final bool speaking;
  final bool spotlighted;

  /// A small strip tile: the name shows at rest.
  final bool compact;

  /// The pointer is somewhere on the call view (see
  /// `_ConnectedBody.revealNames`).
  final bool revealNames;
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
    // Touch layouts have no hover: the name and the menu button stay.
    final revealed = _hover || !shouldUseDesktopLayout(context);
    // The spotlighted tile and the strip's small tiles name themselves at
    // rest; a grid tile while the pointer is on the view.
    final named =
        revealed || widget.revealNames || widget.spotlighted || widget.compact;
    // A spotlighted stream sits on black with its badges in the header.
    final focusedStream = widget.spotlighted && tile.isScreen;
    final statusIcon = tile.isScreen
        ? null
        : tile.deafened || tile.serverDeafened
        ? AppIcons.headsetOff
        : tile.muted
        ? AppIcons.micOff
        : null;
    final statusColor = tile.serverMuted || tile.serverDeafened
        ? colors.red
        : Colors.white;
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
          key: Key('voice-tile-${tile.spotlightKey}'),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            // A person's tile wears their colour; video and streams sit on
            // a dark panel.
            color: tile.track == null && !tile.isScreen
                ? tile.bg
                : focusedStream
                ? Colors.black
                : colors.raised,
            borderRadius: BorderRadius.circular(8),
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
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      AccordMemberAvatar(
                        avatarUrl: tile.avatarUrl,
                        initial: initial,
                        radius: widget.compact ? 20 : 40,
                        backgroundColor: tile.avatarColor,
                        initialStyle: TextStyle(
                          fontSize: widget.compact ? 14 : 28,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      // The soundboard sound being played: its emoji rises
                      // over the avatar.
                      if (!tile.isScreen)
                        SoundboardAvatarCue(
                          userId: tile.userId,
                          size: widget.compact ? 40 : 80,
                        ),
                    ],
                  ),
                ),
              // The pointer resting on a video tile shades its top and
              // bottom edges, where the badges and the name sit.
              if (_hover &&
                  !widget.compact &&
                  (tile.track != null || tile.isScreen))
                const Positioned.fill(
                  child: IgnorePointer(child: _HoverShade()),
                ),
              // Speaking: a green ring just inside the tile's edge.
              if (widget.speaking)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colors.green, width: 3),
                      ),
                    ),
                  ),
                ),
              if (live && tile.watching && !focusedStream)
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
                      // The quality joins LIVE while the pointer rests on
                      // the tile.
                      if (tile.quality != null && revealed) ...[
                        _StreamBadge(label: tile.quality!),
                        const SizedBox(width: 4),
                      ],
                      const LiveBadge(),
                    ],
                  ),
                ),
              // At rest only a small status square (crossed mic / headset)
              // marks the corner; the name joins it when the pointer rests
              // on the tile.
              if (named)
                Positioned(
                  left: 8,
                  bottom: 8,
                  right: openMenu != null && revealed ? 48 : 8,
                  child: _NamePill(
                    name: tile.name,
                    icon: tile.isScreen
                        ? AppIcons.desktopWindowsOutlined
                        : statusIcon,
                    iconColor: statusColor,
                  ),
                )
              else if (statusIcon != null)
                Positioned(
                  left: 8,
                  bottom: 8,
                  child: _StatusSquare(
                    key: Key('tile-status-${tile.userId}'),
                    icon: statusIcon,
                    color: statusColor,
                  ),
                ),
              if (openMenu != null && revealed)
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

/// The top and bottom shading of a hovered tile.
class _HoverShade extends StatelessWidget {
  const _HoverShade();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x80000000), Color(0x00000000), Color(0x00000000), Color(0x80000000)],
          stops: [0.0, 0.3, 0.7, 1.0],
        ),
      ),
    );
  }
}

/// The 32 px square in a resting tile's corner holding its crossed mic or
/// headset.
class _StatusSquare extends StatelessWidget {
  const _StatusSquare({super.key, required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.56),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 16, color: color),
    );
  }
}

/// The panel shown beside our tile while nobody else is in the channel:
/// an illustration over a dark glow, "Invite to Voice" and "Choose Activity"
/// (the Arcade), as other chat apps fill the empty call.
class _AlonePanel extends ConsumerWidget {
  const _AlonePanel({required this.serverKey, required this.spaceId});

  final String serverKey;
  final String spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final space = ref.watch(
      spacesControllerProvider.select(
        (spaces) => spaces?.firstWhereOrNull((s) => s.id == spaceId),
      ),
    );
    final canInvite = accordHasPermission(
      ref.watchAccordPermissions(space, spaceId),
      AccordPermission.createInvites,
    );
    return Container(
      key: const Key('voice-alone-panel'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: const RadialGradient(
          center: Alignment(-0.6, -0.9),
          radius: 1.2,
          colors: [Color(0xFF3A0B33), Color(0xFF120212), Color(0xFF000000)],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: Icon(
                AppIcons.emojiEvents,
                size: 112,
                color: const Color(0xFF8B6CF6),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 56),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (canInvite) ...[
                  _PanelButton(
                    key: const Key('voice-alone-invite'),
                    icon: AppIcons.personAdd,
                    label: 'Invite to Voice',
                    onPressed: () =>
                        showAccordInvites(context, spaceId: spaceId),
                  ),
                  const SizedBox(width: 8),
                ],
                _PanelButton(
                  key: const Key('voice-alone-activity'),
                  icon: AppIcons.sportsEsportsOutlined,
                  label: 'Choose Activity',
                  onPressed: () => showSpaceArcade(
                    context,
                    serverKey: serverKey,
                    spaceId: spaceId,
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

/// A dark pill button on the "alone" panel: icon, label, faint border.
class _PanelButton extends StatelessWidget {
  const _PanelButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Material(
      color: Colors.black.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onPressed,
        hoverColor: colors.hover,
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
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
  const _NamePill({required this.name, this.icon, this.iconColor});

  final String name;
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomLeft,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.56),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: iconColor ?? Colors.white),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
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
