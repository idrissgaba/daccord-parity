import 'package:bonfire/theme/app_icons.dart';
import 'dart:async';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/features/events/controllers/presence.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/features/voice/controllers/voice_states.dart';
import 'package:bonfire/features/voice/utils/participant_display.dart';
import 'package:bonfire/features/voice/views/voice_participant_menu.dart';
import 'package:bonfire/features/voice/views/voice_moderation_menu.dart';
import 'package:bonfire/features/voice/views/voice_view.dart' show LiveBadge;
import 'package:bonfire/shared/utils/platform.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:bonfire/features/member/views/accord_member_avatar.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The list of users present in a voice [channelId], rendered as indented rows
/// beneath the channel tile in the sidebar. Ports the reference client's
/// `voice_channel_item.gd` participant strip: small avatar (green ring while
/// speaking), name in role color, M/D/V flag glyphs, and a LIVE badge for a
/// member sharing their screen (hover: the stream card with "Watch Stream").
class VoiceParticipantList extends ConsumerWidget {
  const VoiceParticipantList({
    super.key,
    required this.channelId,
    required this.spaceId,
    this.onOpenChannel,
  });

  final String channelId;
  final String? spaceId;

  /// Opens the channel's call view (the channel row's own tap), used by the
  /// stream card's "Watch Stream".
  final VoidCallback? onOpenChannel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bucket = ref.watch(
      voiceStatesControllerProvider(
        ref.readActiveServerKey() ?? '',
      ).select((cache) => cache[channelId]),
    );
    if (bucket == null || bucket.isEmpty) return const SizedBox.shrink();

    // Speaking highlights only apply while we're connected to this channel —
    // the speaking set is derived from our own LiveKit room.
    final speaking = ref.watch(
      voiceControllerProvider.select(
        (v) => v.channelId == channelId ? v.speakingUserIds : const <String>{},
      ),
    );

    // The Accord voice state carries no AFK field, so remote members are read
    // from presence (`idle`). Our own row uses the voice controller's flag so it
    // flips immediately, without waiting on the presence round-trip.
    final presences = ref.watch(activePresencesProvider);
    final selfAfk = ref.watch(
      voiceControllerProvider.select(
        (v) => v.channelId == channelId && v.isAfk,
      ),
    );
    final selfUserId = ref.watchUserId();
    final serverKey = ref.readActiveServerKey();
    final moderation = watchVoiceModerationRights(ref, spaceId);

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
    final roles = spaceId == null
        ? const <AccordRole>[]
        : ref.watch(
                spacesControllerProvider.select(
                  (s) => s?.firstWhereOrNull((sp) => sp.id == spaceId)?.roles,
                ),
              ) ??
              const <AccordRole>[];
    final cdnUrl = ref.watchCdnUrl();

    final ensure = ref
        .read(
          accordUsersControllerProvider(
            ref.readActiveServerKey() ?? '',
          ).notifier,
        )
        .ensure;
    final rows = [
      for (final vs in bucket.values)
        (
          voiceState: vs,
          display: participantDisplay(
            vs.userId,
            members: members,
            users: users,
            cdnUrl: cdnUrl,
            ensure: ensure,
          ),
        ),
    ];
    // Rows keep the order members joined in (the cache's insertion order),
    // as in other chat apps; no alphabetical re-sort.

    // Moderators drag participants onto another voice channel to move them
    // (mouse layouts; touch keeps long-press for the menu).
    final dragSpaceId = spaceId;
    final canDrag =
        moderation.move &&
        dragSpaceId != null &&
        serverKey != null &&
        shouldUseDesktopLayout(context);
    Widget draggable(Widget child, String userId, String name) {
      if (!canDrag) return child;
      return Draggable<VoiceMoveDrag>(
        data: VoiceMoveDrag(
          serverKey: serverKey,
          spaceId: dragSpaceId,
          fromChannelId: channelId,
          userId: userId,
          name: name,
        ),
        feedback: Material(
          color: Colors.transparent,
          child: Chip(
            avatar: const Icon(AppIcons.volumeUp, size: 16),
            label: Text(name),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.4, child: child),
        child: child,
      );
    }

    /// Joins the channel if we aren't in it, then receives [userId]'s stream
    /// and opens the call view on it.
    Future<void> watchStream(String userId) async {
      final voice = ref.read(voiceControllerProvider.notifier);
      if (ref.read(voiceControllerProvider).channelId != channelId) {
        await voice.join(channelId, spaceId);
        if (ref.read(voiceControllerProvider).channelId != channelId) return;
      }
      await voice.setWatchingStream(userId, true);
      onOpenChannel?.call();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in rows)
          draggable(
            _ParticipantRow(
              voiceState: row.voiceState,
              display: row.display,
              member: members?[row.voiceState.userId],
              roles: roles,
              speaking: speaking.contains(row.voiceState.userId),
              afk:
                  (selfAfk && row.voiceState.userId == selfUserId) ||
                  accordPresenceStatus(presences, row.voiceState.userId) ==
                      'idle',
              isSelf: row.voiceState.userId == selfUserId,
              onWatchStream: row.voiceState.selfStream
                  ? () => watchStream(row.voiceState.userId)
                  : null,
              // The one participant menu (profile, mention, mute, volume,
              // moderation, copy id), on every row including our own.
              onOpenVolume: serverKey == null
                  ? null
                  : (position) => showVoiceParticipantMenu(
                      context,
                      ref,
                      serverKey: serverKey,
                      userId: row.voiceState.userId,
                      name: row.display.name,
                      globalPosition: position,
                      spaceId: spaceId,
                      channelId: channelId,
                    ),
            ),
            row.voiceState.userId,
            row.display.name,
          ),
      ],
    );
  }
}

class _ParticipantRow extends StatefulWidget {
  const _ParticipantRow({
    required this.voiceState,
    required this.display,
    required this.member,
    required this.roles,
    required this.speaking,
    required this.afk,
    required this.isSelf,
    this.onWatchStream,
    this.onOpenVolume,
  });

  final AccordVoiceState voiceState;
  final ParticipantDisplay display;
  final AccordMember? member;
  final List<AccordRole> roles;
  final bool speaking;

  /// Away from keyboard: dims the row and adds a moon badge.
  final bool afk;

  /// This row is us: our own stream card says so instead of offering to
  /// watch.
  final bool isSelf;

  /// Starts watching this member's stream (null when they aren't live).
  final VoidCallback? onWatchStream;

  /// Opens the local volume menu (right-click position, null on long-press).
  /// Null for our own row.
  final void Function(Offset? position)? onOpenVolume;

  @override
  State<_ParticipantRow> createState() => _ParticipantRowState();
}

class _ParticipantRowState extends State<_ParticipantRow> {
  /// The stream card shown beside the row while the pointer rests on the
  /// row or on the card itself.
  final _card = OverlayPortalController();
  final _link = LayerLink();
  Timer? _hide;

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  void _enter() {
    _hide?.cancel();
    if (widget.voiceState.selfStream &&
        shouldUseDesktopLayout(context) &&
        !_card.isShowing) {
      _card.show();
    }
  }

  void _leave() {
    _hide?.cancel();
    _hide = Timer(const Duration(milliseconds: 150), () {
      if (mounted && _card.isShowing) _card.hide();
    });
  }

  @override
  void didUpdateWidget(covariant _ParticipantRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.voiceState.selfStream && _card.isShowing) _card.hide();
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    final member = widget.member;
    final colorRole = member == null
        ? null
        : memberColorRole(member, widget.roles);
    final nameColor =
        (colorRole == null ? null : accordRoleColor(colorRole.color)) ??
        colors.gray;
    final afk = widget.afk;
    final display = widget.display;

    final openVolume = widget.onOpenVolume;
    return OverlayPortal(
      controller: _card,
      overlayChildBuilder: (context) => CompositedTransformFollower(
        link: _link,
        targetAnchor: Alignment.topRight,
        followerAnchor: Alignment.topLeft,
        offset: const Offset(12, -10),
        child: Align(
          alignment: Alignment.topLeft,
          child: MouseRegion(
            onEnter: (_) => _enter(),
            onExit: (_) => _leave(),
            child: _StreamCard(
              display: display,
              isSelf: widget.isSelf,
              onWatch: widget.onWatchStream,
            ),
          ),
        ),
      ),
      child: CompositedTransformTarget(
        link: _link,
        child: MouseRegion(
          onEnter: (_) => _enter(),
          onExit: (_) => _leave(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // Double-clicking a live member watches their stream.
            onDoubleTap: widget.isSelf ? null : widget.onWatchStream,
            onSecondaryTapUp: openVolume == null
                ? null
                : (d) => openVolume(d.globalPosition),
            onLongPress: openVolume == null ? null : () => openVolume(null),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 1, 8, 1),
              child: _Hover(
                builder: (hovered) => Material(
                  color: hovered ? colors.hover : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    height: 32,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(32, 0, 8, 0),
                      child: Row(
                        children: [
                          Opacity(
                            // Dimmed avatar for an away member, matching how
                            // every other chat client signals "present but
                            // not here".
                            opacity: afk ? 0.4 : 1,
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: widget.speaking
                                    ? Border.all(color: colors.green, width: 2)
                                    : null,
                              ),
                              child: AccordMemberAvatar(
                                avatarUrl: display.avatarUrl,
                                initial: accordInitial(display.name),
                                radius: widget.speaking ? 10 : 12,
                                backgroundColor: display.color,
                                initialStyle: const TextStyle(fontSize: 10),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              display.name,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium!.copyWith(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: afk
                                    ? nameColor.withValues(alpha: 0.5)
                                    : widget.speaking || hovered
                                    ? colors.dirtyWhite
                                    : nameColor,
                              ),
                            ),
                          ),
                          if (afk)
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Tooltip(
                                message: 'Away',
                                child: Icon(
                                  AppIcons.nightlightRound,
                                  size: 14,
                                  color: colors.gray,
                                  key: const Key('voice-participant-afk'),
                                ),
                              ),
                            ),
                          ..._flags(colors),
                          if (widget.voiceState.selfStream)
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: GestureDetector(
                                key: Key(
                                  'voice-participant-live-${widget.voiceState.userId}',
                                ),
                                // Touch has no hover: the badge itself opens
                                // the stream.
                                onTap: shouldUseDesktopLayout(context)
                                    ? null
                                    : widget.onWatchStream,
                                child: const LiveBadge(small: true),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _flags(BonfireThemeExtension colors) {
    final voiceState = widget.voiceState;
    final flags = <Widget>[];
    // Moderator-imposed states win over our own toggles, with an icon so they
    // read differently from a self-mute.
    if (voiceState.deaf) {
      flags.add(
        _serverFlag(
          AppIcons.headsetOff,
          'Server deafened',
          colors.red,
          const Key('voice-participant-server-deaf'),
        ),
      );
    } else if (voiceState.mute) {
      flags.add(
        _serverFlag(
          AppIcons.micOff,
          'Server muted',
          colors.red,
          const Key('voice-participant-server-mute'),
        ),
      );
    } else if (voiceState.selfDeaf) {
      flags.add(
        _serverFlag(
          AppIcons.headsetOff,
          'Deafened',
          colors.gray,
          const Key('voice-participant-self-deaf'),
        ),
      );
    } else if (voiceState.selfMute) {
      flags.add(
        _serverFlag(
          AppIcons.micOff,
          'Muted',
          colors.gray,
          const Key('voice-participant-self-mute'),
        ),
      );
    } else if (voiceState.suppress) {
      flags.add(
        _serverFlag(
          AppIcons.micOff,
          "Can't speak in this channel",
          colors.gray,
          const Key('voice-participant-suppressed'),
        ),
      );
    }
    if (voiceState.selfVideo) {
      flags.add(
        _serverFlag(
          AppIcons.videocam,
          'Camera on',
          colors.gray,
          const Key('voice-participant-video'),
        ),
      );
    }
    return flags;
  }

  Widget _serverFlag(IconData icon, String tooltip, Color color, Key key) =>
      Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Tooltip(
          message: tooltip,
          child: Icon(icon, key: key, size: 16, color: color),
        ),
      );
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

/// The card beside a live member's row: "Streaming Now", a LIVE badge, the
/// stream's picture and the button that watches it. The picture is the
/// streamer's avatar on a dark panel rather than live frames: the server
/// makes no preview, and a second renderer on a track we already draw
/// crashes the engine on Windows.
class _StreamCard extends StatelessWidget {
  const _StreamCard({
    required this.display,
    required this.isSelf,
    required this.onWatch,
  });

  final ParticipantDisplay display;
  final bool isSelf;
  final VoidCallback? onWatch;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    return Material(
      key: const Key('voice-stream-card'),
      color: colors.background,
      elevation: 8,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: 228,
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Streaming Now',
                    style: theme.textTheme.bodySmall!.copyWith(
                      color: colors.gray,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const LiveBadge(),
              ],
            ),
            const SizedBox(height: 8),
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(4),
                ),
                alignment: Alignment.center,
                child: AccordMemberAvatar(
                  avatarUrl: display.avatarUrl,
                  initial: accordInitial(display.name),
                  radius: 20,
                  backgroundColor: display.color,
                  initialStyle: const TextStyle(fontSize: 14),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 32,
              child: FilledButton.icon(
                key: const Key('voice-stream-card-watch'),
                onPressed: isSelf ? null : onWatch,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.darkGray,
                  disabledBackgroundColor: colors.darkGray,
                  foregroundColor: colors.dirtyWhite,
                  disabledForegroundColor: colors.gray,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                icon: const Icon(AppIcons.desktopWindowsOutlined, size: 16),
                label: Text(isSelf ? "You're Streaming!" : 'Watch Stream'),
              ),
            ),
            if (!isSelf) ...[
              const SizedBox(height: 8),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'PROTIP: ',
                      style: TextStyle(
                        color: colors.green,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const TextSpan(text: 'Double click user to watch'),
                  ],
                ),
                style: theme.textTheme.bodySmall!.copyWith(
                  color: colors.gray,
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
