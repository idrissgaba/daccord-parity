import 'dart:math' as math;

import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:flutter/foundation.dart';

/// How many of the home screen's three panes fit side by side.
///
/// The panes are, left to right: the space rail + channel list, the message
/// column, and the member roster. Which of them stay on screen is decided from
/// the *available width* rather than a device breakpoint — see
/// [resolveHomeLayout].
enum HomeLayoutMode {
  /// Rail + channel list + messages + member roster, all inline.
  wide,

  /// Rail + channel list + messages inline; the member roster moves into the
  /// end drawer (reachable from the "Members" button in the header).
  medium,

  /// Only the message column is inline; the rail + channel list live in the
  /// navigation drawer and the roster in the end drawer.
  compact,
}

/// Fixed width of the space rail (`_SpaceRail`).
const double kSpaceRailWidth = 72;

/// Width of the drag handle on the channel list's trailing edge. It overlays
/// the list (it is part of [AccordSettings.channelListWidth]), so it adds
/// nothing to the row.
const double kChannelListHandleWidth = 4;

/// Height of the desktop title bar above the panes.
const double kHomeTitleBarHeight = 32;

/// Fixed width of the inline member roster (`AccordMemberList`).
const double kMemberListWidth = 264;

/// The narrowest the message column is allowed to get before a pane is dropped
/// on touch layouts.
///
/// Below roughly this width message bodies wrap to a handful of words per line
/// and the composer placeholder breaks onto two lines; App Review read that on
/// an iPad Air in portrait (820pt) as a broken build.
/// Everything above it is a pane that must give way first: the member roster,
/// then the channel list.
const double kMinMessagePaneWidth = 420;

/// Width at or above which the rail + channel list can sit beside a usable
/// message column, i.e. the boundary between [HomeLayoutMode.compact] and
/// [HomeLayoutMode.medium].
///
/// Derived from the panes themselves (rail + the *narrowest* the channel list
/// is allowed to be + [kMinMessagePaneWidth]) so it can never drift out of sync
/// with them.
const double kHomeSidebarBreakpoint =
    kSpaceRailWidth + AccordSettings.minChannelListWidth + kMinMessagePaneWidth;

/// Width at or above which the member roster can also stay inline, i.e. the
/// boundary between [HomeLayoutMode.medium] and [HomeLayoutMode.wide].
const double kHomeMemberListBreakpoint =
    kHomeSidebarBreakpoint + kMemberListWidth;

/// The narrowest window a desktop client keeps all three panes at. The
/// reference client never drops a pane on desktop: its desktop app refuses to
/// shrink below 940 px and its web client keeps squeezing the message column
/// (260 px left at 900, verified down to 600). Below this the touch rules
/// apply so a tiny window stays usable.
const double kDesktopMinWindowWidth = 720;

/// The resolved home layout for a given available width.
@immutable
class HomeLayout {
  const HomeLayout({required this.mode, required this.channelListWidth});

  final HomeLayoutMode mode;

  /// The width the channel list should actually be rendered at. Equal to the
  /// user's persisted preference unless honouring it would push the message
  /// column below [kMinMessagePaneWidth] on a touch layout, in which case the
  /// list is trimmed (never below [AccordSettings.minChannelListWidth]) rather
  /// than the whole pane being thrown into a drawer. Meaningless in
  /// [HomeLayoutMode.compact], where the list is a drawer of its own.
  final double channelListWidth;

  bool get showsSidebarInline => mode != HomeLayoutMode.compact;
  bool get showsMemberListInline => mode == HomeLayoutMode.wide;

  @override
  bool operator ==(Object other) =>
      other is HomeLayout &&
      other.mode == mode &&
      other.channelListWidth == channelListWidth;

  @override
  int get hashCode => Object.hash(mode, channelListWidth);

  @override
  String toString() => 'HomeLayout($mode, channelList: $channelListWidth)';
}

/// Picks the home layout for [width].
///
/// On a [desktop] window at or above [kDesktopMinWindowWidth] all three panes
/// stay inline at the user's channel-list width, as in the reference desktop
/// client — the message column takes whatever is left.
///
/// Otherwise (touch, or a desktop window squeezed below that) the message
/// column is kept at least [kMinMessagePaneWidth] wide and panes are given up
/// in order of how much the screen needs them: the member roster first, then
/// the channel list. Before either is dropped the channel list is squeezed
/// down towards [AccordSettings.minChannelListWidth], so a user who dragged
/// the divider wide on a large window doesn't get thrown into the drawer
/// layout when they shrink it.
///
/// [preferredChannelListWidth] is the persisted
/// [AccordSettings.channelListWidth] (or the live drag width).
HomeLayout resolveHomeLayout({
  required double width,
  required double preferredChannelListWidth,
  bool desktop = false,
}) {
  final preferred = preferredChannelListWidth.clamp(
    AccordSettings.minChannelListWidth,
    AccordSettings.maxChannelListWidth,
  );
  if (desktop && width >= kDesktopMinWindowWidth) {
    return HomeLayout(mode: HomeLayoutMode.wide, channelListWidth: preferred);
  }

  final mode = width >= kHomeMemberListBreakpoint
      ? HomeLayoutMode.wide
      : width >= kHomeSidebarBreakpoint
      ? HomeLayoutMode.medium
      : HomeLayoutMode.compact;

  if (mode == HomeLayoutMode.compact) {
    return HomeLayout(
      mode: mode,
      channelListWidth: AccordSettings.minChannelListWidth,
    );
  }

  final reserved =
      kSpaceRailWidth +
      kMinMessagePaneWidth +
      (mode == HomeLayoutMode.wide ? kMemberListWidth : 0);
  final available = math.max(
    AccordSettings.minChannelListWidth,
    width - reserved,
  );
  final channelListWidth = preferred.clamp(
    AccordSettings.minChannelListWidth,
    available,
  );

  return HomeLayout(mode: mode, channelListWidth: channelListWidth);
}
