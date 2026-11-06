import 'dart:async';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/channels/controllers/accord_channels.dart';
import 'package:bonfire/features/channels/controllers/dm_channels.dart';
import 'package:bonfire/features/channels/controllers/muted_channels.dart';
import 'package:bonfire/features/channels/controllers/read_state.dart';
import 'package:bonfire/features/channels/utils/mark_channel_read.dart';
import 'package:bonfire/features/channels/views/channel_context_menu.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/member/views/accord_member_avatar.dart';
import 'package:bonfire/features/messaging/views/box/accord_message_content.dart';
import 'package:bonfire/features/notifications/controllers/inbox_mentions.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/server/services/deep_link_navigation.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/features/spaces/utils/message_time.dart';
import 'package:bonfire/features/spaces/utils/space_display.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/features/user/controllers/friend_ids.dart';
import 'package:bonfire/features/user/views/accord_direct_messages.dart';
import 'package:bonfire/features/voice/utils/stage_logic.dart';
import 'package:bonfire/shared/components/context_menu.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/theme/app_icons.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

part 'inbox_popover/cards.dart';
part 'inbox_popover/tabs.dart';

/// The popover's surfaces, as measured on the reference client: the panel,
/// one channel's card, and the tip card.
const Color _kInboxBackground = Color(0xFF242429);
const Color _kInboxCard = Color(0xFF28282D);
const Color _kInboxTip = Color(0xFF121214);

/// The selected tab's label and underline (the reference client's brand
/// text).
const Color _kInboxTabSelected = Color(0xFF798DF9);

/// 560 wide, 610 tall at most, 4 px under the title bar.
const double _kInboxWidth = 560;
const double _kInboxMaxHeight = 610;

/// The reference client's tabs share the bar in fifths; Accord has the first
/// two (Bookmarks, Reminders and Scheduled have no server support).
const double _kInboxTabWidth = _kInboxWidth / 5;

enum InboxTab { unread, mentions }

/// The open inbox's route, so Ctrl+I and the button close it again.
Route<void>? _openInbox;

/// Opens the inbox under the title bar's inbox button ([context] is the
/// button), or closes it when it is already open: the Unread and Mentions
/// tabs of the reference client's popover.
Future<void> showInboxPopover(BuildContext context, {InboxTab? tab}) {
  final open = _openInbox;
  if (open != null && open.isActive) {
    open.navigator?.removeRoute(open);
    _openInbox = null;
    return Future.value();
  }
  final box = context.findRenderObject() as RenderBox?;
  final overlay =
      Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
  final anchor = box == null || overlay == null
      ? null
      // The reference client lines the panel's right edge up with its 24 px
      // button box, 12 px right of the glyph's centre.
      : box.localToGlobal(
          Offset(box.size.width / 2 + 12, box.size.height),
          ancestor: overlay,
        );
  final route = DialogRoute<void>(
    context: context,
    barrierColor: Colors.transparent,
    barrierDismissible: true,
    builder: (context) {
      final size = MediaQuery.sizeOf(context);
      final right = anchor == null ? 8.0 : size.width - anchor.dx;
      final top = (anchor?.dy ?? 32) + 4;
      return Stack(
        children: [
          Positioned(
            right: right.clamp(8.0, size.width),
            top: top,
            child: SizedBox(
              width: _kInboxWidth,
              height: (size.height - top - 16).clamp(200.0, _kInboxMaxHeight),
              child: InboxPopover(initialTab: tab ?? InboxTab.unread),
            ),
          ),
        ],
      );
    },
  );
  _openInbox = route;
  return Navigator.of(context).push(route).whenComplete(() {
    if (_openInbox == route) _openInbox = null;
  });
}

/// The inbox panel: "Inbox" with its buttons, the tab bar, and the tab.
class InboxPopover extends ConsumerStatefulWidget {
  const InboxPopover({super.key, this.initialTab = InboxTab.unread});

  final InboxTab initialTab;

  @override
  ConsumerState<InboxPopover> createState() => _InboxPopoverState();
}

class _InboxPopoverState extends ConsumerState<InboxPopover> {
  late InboxTab _tab = widget.initialTab;

  /// Unread messages already fetched, per channel (the newest last).
  final Map<String, List<AccordMessage>> _loaded = {};
  final Set<String> _loading = {};

  /// Cards folded with their chevron.
  final Set<String> _collapsed = {};

  String? get _serverKey => ref.read(connectionsControllerProvider).activeKey;

  /// Fetches what follows the read position of [entry]'s channel, once, and
  /// files the mentions it finds for the Mentions tab.
  void _ensureLoaded(ReadEntry entry) {
    final channelId = entry.channelId;
    final serverKey = _serverKey;
    if (serverKey == null ||
        _loaded.containsKey(channelId) ||
        !_loading.add(channelId)) {
      return;
    }
    final client = ref.clientForKey(serverKey);
    if (client == null) return;
    final after =
        entry.lastReadMessageId ??
        ref.read(readStateControllerProvider(serverKey).notifier).readThrough(
          channelId,
        );
    unawaited(
      client.messages
          .list(
            channelId,
            query: {'limit': '$_kUnreadFetchLimit', 'after': ?after},
          )
          .then((result) {
            final data = result.data;
            final messages = data is List
                ? data.whereType<AccordMessage>().toList()
                : <AccordMessage>[];
            messages.sort((a, b) => compareMessageIds(a.id, b.id));
            final unread = [
              for (final m in messages)
                if (after == null || compareMessageIds(m.id, after) > 0) m,
            ];
            if (!mounted) return;
            _fileMentions(serverKey, entry.spaceId, unread);
            setState(() {
              _loading.remove(channelId);
              _loaded[channelId] = unread;
            });
          }),
    );
  }

  /// The unread messages that mention the user also belong to Mentions.
  void _fileMentions(
    String serverKey,
    String? spaceId,
    List<AccordMessage> messages,
  ) {
    if (spaceId == null) return;
    final selfId = ref
        .read(connectionsControllerProvider)
        .connectionFor(serverKey)
        ?.session
        .userId;
    final roles =
        ref.read(accordMembersControllerProvider(serverKey, spaceId))?[selfId]
            ?.roles ??
        const <String>[];
    final mentions = ref.read(
      inboxMentionsControllerProvider(serverKey).notifier,
    );
    for (final m in messages) {
      if (m.authorId == selfId) continue;
      final kind = inboxMentionKind(
        m,
        isSelf: (id) => id == selfId,
        memberRoles: roles,
      );
      if (kind == null) continue;
      m.spaceId ??= spaceId;
      mentions.record(m, kind);
    }
  }

  void _markAllRead(List<ReadEntry> entries) {
    for (final e in entries) {
      markChannelRead(ref, e.channelId, fallbackMessageId: e.lastMessageId);
    }
  }

  void _openFriendRequests() {
    Navigator.of(context).maybePop();
    dmHome.showFriends(FriendsPage.pending);
  }

  Future<void> _openMentionFilter(Offset position) {
    final settings = ref.read(settingsControllerProvider);
    final ctl = ref.read(settingsControllerProvider.notifier);
    return showAccordContextMenu(
      context,
      globalPosition: position,
      anchorX: 1,
      entries: [
        AccordMenuEntry(
          key: const Key('inbox-filter-everyone'),
          label: 'Include @everyone mentions',
          checked: settings.inboxIncludeEveryone,
          onSelected: () =>
              ctl.setInboxIncludeEveryone(!settings.inboxIncludeEveryone),
        ),
        AccordMenuEntry(
          key: const Key('inbox-filter-roles'),
          label: 'Include @role mentions',
          checked: settings.inboxIncludeRoles,
          onSelected: () => ctl.setInboxIncludeRoles(!settings.inboxIncludeRoles),
        ),
      ],
    );
  }

  /// Jumps to [message] (the space's channel, or the DM) and closes the inbox.
  void _jump(AccordMessage message, {required String? spaceId}) {
    final serverKey = _serverKey;
    if (serverKey == null) return;
    Navigator.of(context).maybePop();
    if (spaceId == null) {
      final dm = ref
          .read(dmChannelsControllerProvider(serverKey))
          ?.firstWhereOrNull((c) => c.id == message.channelId);
      if (dm != null) dmHome.open(dm);
      return;
    }
    final baseUrl = ref
        .read(connectionsControllerProvider)
        .connectionFor(serverKey)
        ?.session
        .server
        .baseUrl;
    ref
        .read(pendingDeepLinkProvider.notifier)
        .hold(
          PendingDeepLinkDestination(
            serverBaseUrl: baseUrl,
            spaceId: spaceId,
            channelId: message.channelId,
            messageId: message.id,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final serverKey = ref.watch(
      connectionsControllerProvider.select((s) => s.activeKey),
    );
    final unread = serverKey == null
        ? const <ReadEntry>[]
        : inboxUnreadEntries(ref, serverKey);
    final requests = serverKey == null
        ? 0
        : ref.watch(
            friendIdsControllerProvider(
              serverKey,
            ).select((s) => s.pendingIncoming),
          );
    return Material(
      key: const Key('inbox-popover'),
      color: _kInboxBackground,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      elevation: 8,
      shadowColor: Colors.black,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header: padding 16 16 0, a 34 px title row, 16 px, the tabs.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: SizedBox(
                height: 34,
                child: Row(
                  children: [
                    Icon(AppIcons.tray, size: 24, color: colors.dirtyWhite),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Inbox',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          height: 24 / 20,
                          color: colors.dirtyWhite,
                        ),
                      ),
                    ),
                    if (_tab == InboxTab.unread)
                      _HeaderButton(
                        key: const Key('inbox-mark-all-read'),
                        tooltip: 'Mark All as Read',
                        icon: AppIcons.doneAll,
                        onTap: unread.isEmpty
                            ? null
                            : (_) => _markAllRead(unread),
                      )
                    else
                      _HeaderButton(
                        key: const Key('inbox-filter'),
                        tooltip: 'Filter',
                        icon: AppIcons.tune,
                        onTap: _openMentionFilter,
                      ),
                    const SizedBox(width: 8),
                    _HeaderButton(
                      key: const Key('inbox-friend-requests'),
                      tooltip: 'View Friend Requests, $requests',
                      icon: AppIcons.peopleAltOutlined,
                      onTap: (_) => _openFriendRequests(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _InboxTabBar(
              selected: _tab,
              onSelect: (tab) => setState(() => _tab = tab),
            ),
            Expanded(
              child: serverKey == null
                  ? const SizedBox.shrink()
                  : switch (_tab) {
                      InboxTab.unread => _UnreadTab(
                        serverKey: serverKey,
                        entries: unread,
                        loaded: _loaded,
                        collapsed: _collapsed,
                        onNeed: _ensureLoaded,
                        onToggle: (id) => setState(
                          () => _collapsed.contains(id)
                              ? _collapsed.remove(id)
                              : _collapsed.add(id),
                        ),
                        onMarkRead: (e) => markChannelRead(
                          ref,
                          e.channelId,
                          fallbackMessageId: e.lastMessageId,
                        ),
                        onJump: _jump,
                      ),
                      InboxTab.mentions => _MentionsTab(
                        serverKey: serverKey,
                        unread: unread,
                        onNeed: _ensureLoaded,
                        onJump: _jump,
                      ),
                    },
            ),
          ],
        ),
      ),
    );
  }
}

/// How many unread messages a card fetches at most.
const int _kUnreadFetchLimit = 25;

/// The unread channels the inbox lists: every channel and DM with unread
/// messages that isn't muted (its own mute, its category's, its space's) or
/// set to Nothing, newest first. The first is what Ctrl+Shift+E marks read.
/// [watch] subscribes the calling build; a callback passes false.
List<ReadEntry> inboxUnreadEntries(
  WidgetRef ref,
  String serverKey, {
  bool watch = true,
}) {
  T get<T>(ProviderListenable<T> provider) =>
      watch ? ref.watch(provider) : ref.read(provider);
  final snapshot = get(readStateControllerProvider(serverKey));
  get(settingsControllerProvider.select((s) => s.channelNotifications));
  get(settingsControllerProvider.select((s) => s.mutedSpaces));
  final settings = ref.read(settingsControllerProvider);
  final levels = settings.channelNotificationsFor(serverKey);
  final muted =
      get(mutedChannelsControllerProvider(serverKey)).value ??
      const <String>{};
  final entries = <ReadEntry>[];
  for (final e in snapshot.entries.values) {
    final spaceId = e.spaceId;
    var channelMuted = muted.contains(e.channelId);
    if (spaceId != null && !channelMuted) {
      final parent = ref
          .read(accordChannelsControllerProvider(serverKey, spaceId))
          ?.firstWhereOrNull((c) => c.id == e.channelId)
          ?.parentId;
      channelMuted = parent != null && muted.contains(parent);
    }
    if (!UnreadIndicatorGate.countsTowardSpace(
      spaceMuted: spaceId != null && settings.isSpaceMuted(serverKey, spaceId),
      channelLevel: levels[e.channelId],
      channelMuted: channelMuted,
    )) {
      continue;
    }
    entries.add(e);
  }
  entries.sort(
    (a, b) => compareMessageIds(b.lastMessageId ?? '0', a.lastMessageId ?? '0'),
  );
  return entries;
}

/// A 32 px square button of the header (Mark All as Read, Filter, View Friend
/// Requests): 12 % grey fill, rounded 8, a faint border.
class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final ValueChanged<Offset>? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Tooltip(
      message: tooltip,
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: Material(
          color: const Color(0x1F94949C),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.04)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            // Menus hang from the button's bottom-right corner.
            onTapUp: onTap == null ? null : (_) => onTap!(_anchor(context)),
            onTap: onTap == null ? null : () {},
            child: SizedBox(
              width: 32,
              height: 32,
              child: Icon(icon, size: 16, color: colors.dirtyWhite),
            ),
          ),
        ),
      ),
    );
  }
}

/// 8 px under the bottom-right corner of [context]'s box, in global
/// coordinates.
Offset _anchor(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  if (box == null) return Offset.zero;
  return box.localToGlobal(Offset(box.size.width, box.size.height + 8));
}

/// Unread | Mentions, each a fifth of the bar: 14/600 labels, the selected
/// one in brand blue over a 2 px underline, a hairline under the bar.
class _InboxTabBar extends StatelessWidget {
  const _InboxTabBar({required this.selected, required this.onSelect});

  final InboxTab selected;
  final ValueChanged<InboxTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    Widget tab(InboxTab value, String label) {
      final on = value == selected;
      return SizedBox(
        width: _kInboxTabWidth,
        height: 36,
        child: InkWell(
          key: Key('inbox-tab-${value.name}'),
          onTap: () => onSelect(value),
          child: Stack(
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 20 / 14,
                    color: on ? _kInboxTabSelected : colors.interactive,
                  ),
                ),
              ),
              if (on)
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 2,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: _kInboxTabSelected,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(2),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.hairline)),
      ),
      child: Row(
        children: [
          tab(InboxTab.unread, 'Unread'),
          tab(InboxTab.mentions, 'Mentions'),
        ],
      ),
    );
  }
}
