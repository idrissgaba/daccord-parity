import 'dart:async' show unawaited;
import 'dart:math' as math;

import 'package:accordkit/accordkit.dart'
    show AccordMember, AccordUser, AccordVoiceState;
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/features/voice/controllers/call.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/features/voice/controllers/voice_states.dart';
import 'package:bonfire/features/voice/services/voice_session.dart'
    show VoiceSession;
import 'package:bonfire/features/voice/utils/participant_display.dart';
import 'package:bonfire/features/voice/utils/audio_output_support.dart';
import 'package:bonfire/features/voice/views/user_volume_menu.dart';
import 'package:bonfire/features/voice/views/voice_moderation_menu.dart';
import 'package:bonfire/features/voice/views/stage_view.dart';
import 'package:bonfire/features/voice/utils/stage_logic.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/features/voice/services/stream_popout.dart';
import 'package:bonfire/features/voice/views/screen_share_picker.dart';
import 'package:bonfire/features/voice/views/stream_menu.dart';
import 'package:bonfire/features/voice/views/voice_settings_screen.dart';
import 'package:bonfire/features/voice/views/voice_text_panel.dart';
import 'package:bonfire/shared/components/context_menu.dart';
import 'package:bonfire/shared/components/horizontal_wheel_scroll.dart';
import 'package:bonfire/shared/utils/platform.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:bonfire/features/member/views/accord_member_avatar.dart';
import 'package:bonfire/features/voice/views/voice_lobby.dart';
import 'package:flutter/services.dart';
import 'package:universal_platform/universal_platform.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart' show VideoTrack;
import 'package:livekit_client/livekit_client.dart' as lk;

part 'voice_view/video_grid.dart';
part 'voice_view/control_bar.dart';

/// Whether the voice view fills the window. Full screen happens in place —
/// the screen hosting the view hides everything around it — never by pushing
/// a second view: building a second set of video renderers (and tearing one
/// down) crashes the Flutter engine on Windows.
final voiceViewExpanded = ValueNotifier<bool>(false);

/// Expands the voice view to fill the window (and the screen, on desktop), or
/// restores it.
Future<void> setVoiceViewExpanded(bool expanded) async {
  if (voiceViewExpanded.value == expanded) return;
  voiceViewExpanded.value = expanded;
  // Esc leaves full screen wherever keyboard focus is.
  if (expanded) {
    HardwareKeyboard.instance.addHandler(_escapeExitsFullScreen);
  } else {
    HardwareKeyboard.instance.removeHandler(_escapeExitsFullScreen);
  }
  if (_hasDesktopWindow) {
    try {
      await windowManager.setFullScreen(expanded);
    } catch (e) {
      debugPrint('Voice full screen failed: $e');
    }
  }
}

bool _escapeExitsFullScreen(KeyEvent event) {
  if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.escape) {
    return false;
  }
  setVoiceViewExpanded(false);
  return true;
}

/// Phones share the whole screen, this app included, so our own share must
/// not be previewed there (it would film itself); desktops share a chosen
/// screen or window.
bool get screenShareCapturesApp =>
    !kIsWeb && (UniversalPlatform.isAndroid || UniversalPlatform.isIOS);

bool get _hasDesktopWindow =>
    !kIsWeb &&
    (UniversalPlatform.isWindows ||
        UniversalPlatform.isLinux ||
        UniversalPlatform.isMacOS);

/// The voice channel screen shown in the message pane: a header, the video
/// grid (one tile per participant, camera/screen tracks or an initials
/// placeholder), an optional side text-chat panel, and a control bar
/// (reference: `main_window_voice_view.gd`).
///
/// A DM call embeds the same view above the conversation's messages
/// ([embedded]); there is no second, full-screen presentation of a call —
/// [setVoiceViewExpanded] grows this one in place.
class VoiceChannelView extends ConsumerStatefulWidget {
  const VoiceChannelView({
    super.key,
    required this.channelId,
    required this.spaceId,
    required this.channelName,
    this.embedded = false,
  });

  final String channelId;
  final String? spaceId;
  final String? channelName;

  /// Hosted inside a conversation (a DM call): the conversation's own header
  /// and messages surround the view, so it draws neither its header nor a
  /// chat panel of its own.
  final bool embedded;

  @override
  ConsumerState<VoiceChannelView> createState() => _VoiceChannelViewState();
}

class _VoiceChannelViewState extends ConsumerState<VoiceChannelView> {
  String? _spotlightUserId;

  /// One global key per video tile of this view, so a tile moving between the
  /// grid and the spotlight is moved, not rebuilt: rebuilding tears down and
  /// recreates its video renderer, which crashes the engine on Windows.
  final _tileKeys = <String, GlobalKey>{};

  /// Whether the strip of other participants under the spotlighted tile is
  /// folded away (the chevron between them), so a stream can take the whole
  /// body in full screen.
  bool _stripHidden = false;

  /// Whether the voice text-chat panel is open. Defaults open in the lobby
  /// and closed for a call already in progress; the header toggle then wins
  /// until the view switches to another channel. Never in an embedded view,
  /// whose conversation already shows the messages.
  late bool _chatOpen = _defaultChatOpen();

  /// Below this width the chat panel takes over the body instead of sitting
  /// beside the video grid.
  static const double _sidePanelBreakpoint = 720;

  bool _defaultChatOpen() {
    if (widget.embedded) return false;
    final connectedHere =
        ref.read(voiceControllerProvider).channelId == widget.channelId;
    return !connectedHere;
  }

  @override
  void dispose() {
    // Leaving the voice view (another channel, another space) ends full
    // screen; scheduled because the home screen rebuilds on it.
    if (voiceViewExpanded.value) {
      Future.microtask(() => setVoiceViewExpanded(false));
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant VoiceChannelView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The message pane reuses one [VoiceChannelView] across channel switches, so
    // per-channel view state has to be re-derived rather than carried over.
    if (oldWidget.channelId != widget.channelId) {
      _spotlightUserId = null;
      _chatOpen = _defaultChatOpen();
    }
  }

  /// Whether this is a DM/group-DM call (no parent space). DM calls layer the
  /// ring/accept/decline signaling on top of the plain voice session.
  bool get _isDmCall => widget.spaceId == null;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final connectedHere = ref.watch(
      voiceControllerProvider.select((v) => v.channelId == widget.channelId),
    );

    final ringing =
        _isDmCall &&
        connectedHere &&
        ref.watch(
          callControllerProvider.select(
            (s) => s.outgoingChannelId == widget.channelId,
          ),
        );

    return Container(
      color: colors.background,
      child: Column(
        children: [
          if (!widget.embedded) _header(context, colors),
          if (ringing) _RingingBanner(name: widget.channelName),
          Expanded(child: _body(connectedHere)),
          if (connectedHere)
            _ControlBar(channelId: widget.channelId, spaceId: widget.spaceId),
        ],
      ),
    );
  }

  Widget _body(bool connectedHere) {
    final primary = connectedHere
        ? ValueListenableBuilder<bool>(
            valueListenable: voiceViewExpanded,
            builder: (context, expanded, _) => _ConnectedBody(
              tileKeys: _tileKeys,
              channelId: widget.channelId,
              spaceId: widget.spaceId,
              // Full screen: the video runs edge to edge, no gutter.
              edgeToEdge: expanded,
              spotlightUserId: _spotlightUserId,
              onToggleSpotlight: (userId) => setState(
                () => _spotlightUserId = _spotlightUserId == userId
                    ? null
                    : userId,
              ),
              stripHidden: _stripHidden,
              onToggleStrip: () => setState(() => _stripHidden = !_stripHidden),
            ),
          )
        : VoiceLobbyBody(
            channelId: widget.channelId,
            spaceId: widget.spaceId,
            channelName: widget.channelName,
          );

    if (!_chatOpen || widget.embedded) return primary;

    final chat = VoiceTextPanel(
      channelId: widget.channelId,
      spaceId: widget.spaceId,
      channelName: widget.channelName,
      onClose: () => setState(() => _chatOpen = false),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Wide: chat sits beside the video grid / lobby.
        if (constraints.maxWidth >= _sidePanelBreakpoint) {
          return Row(
            children: [
              Expanded(child: primary),
              // Wide enough for the full message pane's chrome (avatar gutter,
              // reactions, floating action bar) to stay readable.
              SizedBox(width: 340, child: chat),
            ],
          );
        }
        // Narrow, in a call: chat takes over the body. The video grid is the
        // thing being traded away, and every call control still lives in the
        // control bar below.
        if (connectedHere) return chat;
        // Narrow, in the lobby: chat still takes the body, but the participants
        // and the Join button stay pinned above it.
        return Column(
          children: [
            VoiceLobbyBody(
              channelId: widget.channelId,
              spaceId: widget.spaceId,
              channelName: widget.channelName,
              compact: true,
            ),
            Expanded(child: chat),
          ],
        );
      },
    );
  }

  /// The user whose screen share is focused, or null when no stream is.
  String? get _focusedStreamUserId {
    final key = _spotlightUserId;
    if (key == null || !key.endsWith(':screen')) return null;
    return key.substring(0, key.length - ':screen'.length);
  }

  Widget _header(BuildContext context, BonfireThemeExtension colors) {
    // A focused stream names itself in the header — "General • X's Screen" —
    // with its quality and LIVE at the right.
    final streamUserId = _focusedStreamUserId;
    final connectedHere =
        ref.watch(voiceControllerProvider).channelId == widget.channelId;
    final stream = streamUserId == null || !connectedHere
        ? null
        : _focusedStream(streamUserId);
    return Container(
      height: 48,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(left: 16, right: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.foreground, width: 1)),
      ),
      child: Row(
        children: [
          Icon(
            watchIsStage(ref, widget.spaceId, widget.channelId)
                ? Icons.podcasts
                : Icons.volume_up,
            size: 18,
            color: colors.dirtyWhite,
          ),
          const SizedBox(width: 6),
          if (stream == null)
            Expanded(
              child: Text(
                widget.channelName ?? '',
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            )
          else ...[
            Text(
              widget.channelName ?? '',
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text('•', style: TextStyle(color: colors.gray)),
            ),
            AccordMemberAvatar(
              avatarUrl: stream.display.avatarUrl,
              initial: accordInitial(stream.display.name),
              radius: 10,
              backgroundColor: stream.display.color,
              initialStyle: const TextStyle(fontSize: 10),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                "${stream.display.name}'s Screen",
                key: const Key('voice-header-stream'),
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            _StreamQualityPill(quality: stream.quality),
            const SizedBox(width: 8),
          ],
          IconButton(
            tooltip: _chatOpen ? 'Hide chat' : 'Show chat',
            onPressed: () => setState(() => _chatOpen = !_chatOpen),
            icon: Icon(
              _chatOpen ? Icons.chat_bubble : Icons.chat_bubble_outline,
              size: 18,
              color: _chatOpen ? colors.primary : colors.dirtyWhite,
            ),
          ),
        ],
      ),
    );
  }
}

/// The focused stream's owner and quality, for the header.
typedef _FocusedStream = ({ParticipantDisplay display, String? quality});

extension on _VoiceChannelViewState {
  _FocusedStream _focusedStream(String userId) {
    final serverKey = ref.readActiveServerKey() ?? '';
    final spaceId = widget.spaceId;
    final members = spaceId == null
        ? null
        : ref.watch(accordMembersControllerProvider(serverKey, spaceId));
    final users = ref.watch(accordUsersControllerProvider(serverKey));
    final display = participantDisplay(
      userId,
      members: members,
      users: users,
      cdnUrl: ref.watchCdnUrl(),
    );
    ref.watch(
      settingsControllerProvider.select(
        (s) => (s.screenShareResolution, s.screenShareFps),
      ),
    );
    final quality = streamQualityLabel(
      ref,
      ref.read(voiceControllerProvider.notifier).session,
      userId,
      myId: ref.watchUserId(),
    );
    return (display: display, quality: quality);
  }
}

/// "720p 30FPS  LIVE" at the right of the header while a stream is focused.
class _StreamQualityPill extends StatelessWidget {
  const _StreamQualityPill({required this.quality});

  final String? quality;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 2, 2, 2),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (quality != null) ...[
            Text(
              quality!.replaceFirst('P ', 'p '),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 6),
          ],
          const LiveBadge(),
        ],
      ),
    );
  }
}

/// A thin banner shown while an outgoing DM call is still ringing (the callee
/// hasn't joined yet).
class _RingingBanner extends StatelessWidget {
  const _RingingBanner({required this.name});

  final String? name;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: colors.foreground,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colors.dirtyWhite,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              name == null || name!.isEmpty ? 'Calling…' : 'Calling $name…',
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium!.copyWith(color: colors.dirtyWhite),
            ),
          ),
        ],
      ),
    );
  }
}
