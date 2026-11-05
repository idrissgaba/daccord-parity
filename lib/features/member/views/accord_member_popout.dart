import 'package:bonfire/theme/app_icons.dart';
import 'package:accordkit/accordkit.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/features/events/controllers/presence.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/controllers/profile_extras.dart';
import 'package:bonfire/features/member/utils/member_actions.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/member/utils/permissions.dart';
import 'package:bonfire/features/member/views/accord_member_avatar.dart';
import 'package:bonfire/features/member/views/full_profile.dart';
import 'package:bonfire/features/member/views/profile_card.dart';
import 'package:bonfire/features/member/views/profile_extras.dart'
    show profileColor;
import 'package:bonfire/features/member/views/remote_origin_badge.dart';
import 'package:bonfire/features/member/views/user_context_menu.dart';
import 'package:bonfire/features/messaging/views/emoji_picker.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/features/user/views/account_card.dart';
import 'package:bonfire/shared/components/context_menu.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:collection/collection.dart';
import 'package:bonfire/shared/utils/platform.dart';
import 'package:bonfire/shared/utils/pointer_anchor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'member_popout/sections.dart';

/// Width of the profile popout, as the reference client's.
const double kProfilePopoutWidth = 300;

/// Opens the profile popout for [userId] — a member of [spaceId], or (in a
/// DM, with no space) the account alone. On desktop it pops out beside the
/// click that opened it; on touch layouts (or with no recent click) it is a
/// centered modal. Clicking the avatar or banner opens the full profile.
///
/// [besideRect] (a member-list row) puts the card's top-right corner 7 px
/// left of the row, level with it, as the reference client's roster does.
Future<void> showAccordMemberPopout(
  BuildContext context, {
  String? spaceId,
  required String userId,
  Rect? besideRect,
}) {
  final desktop = shouldUseDesktopLayout(context);
  if (desktop && besideRect != null) {
    return _showAnchoredPopout(
      context,
      _BesideLayout(besideRect),
      spaceId: spaceId,
      userId: userId,
    );
  }
  final anchor = desktop ? recentPointerAnchor() : null;
  if (anchor == null) {
    return showDialog<void>(
      context: context,
      builder: (_) => Center(
        child: _MemberPopout(spaceId: spaceId, userId: userId),
      ),
    );
  }
  return _showAnchoredPopout(
    context,
    _PopoverLayout(anchor),
    spaceId: spaceId,
    userId: userId,
  );
}

Future<void> _showAnchoredPopout(
  BuildContext context,
  SingleChildLayoutDelegate layout, {
  required String? spaceId,
  required String userId,
}) => showGeneralDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Close profile',
  barrierColor: Colors.transparent,
  transitionDuration: const Duration(milliseconds: 120),
  pageBuilder: (_, _, _) => CustomSingleChildLayout(
    delegate: layout,
    child: _MemberPopout(spaceId: spaceId, userId: userId),
  ),
  transitionBuilder: (_, animation, _, child) =>
      FadeTransition(opacity: animation, child: child),
);

/// Beside a roster row: the card's top-right corner 7 px left of the row,
/// level with its top, kept on screen.
class _BesideLayout extends SingleChildLayoutDelegate {
  const _BesideLayout(this.row);

  final Rect row;
  static const double _margin = 12;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(
        Size(
          kProfilePopoutWidth,
          (constraints.maxHeight - 2 * _margin).clamp(0, 900),
        ),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final x = (row.left - 7 - childSize.width).clamp(
      _margin,
      (size.width - childSize.width - _margin).clamp(_margin, size.width),
    );
    final y = row.top.clamp(
      _margin,
      (size.height - childSize.height - _margin).clamp(_margin, size.height),
    );
    return Offset(x.toDouble(), y.toDouble());
  }

  @override
  bool shouldRelayout(_BesideLayout oldDelegate) => row != oldDelegate.row;
}

/// Places the card to the right of [anchor] (to its left when there is no
/// room, e.g. clicks in the member list), its top a little above the click,
/// kept on screen.
class _PopoverLayout extends SingleChildLayoutDelegate {
  const _PopoverLayout(this.anchor);

  final Offset anchor;
  static const double _margin = 12;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(
        Size(
          kProfilePopoutWidth,
          (constraints.maxHeight - 2 * _margin).clamp(0, 900),
        ),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    var x = anchor.dx + 16;
    if (x + childSize.width > size.width - _margin) {
      x = anchor.dx - 20 - childSize.width;
    }
    final y = (anchor.dy - 20).clamp(
      _margin,
      (size.height - childSize.height - _margin).clamp(_margin, size.height),
    );
    return Offset(
      x.clamp(
        _margin,
        (size.width - childSize.width - _margin).clamp(_margin, size.width),
      ),
      y.toDouble(),
    );
  }

  @override
  bool shouldRelayout(_PopoverLayout oldDelegate) =>
      anchor != oldDelegate.anchor;
}

class _MemberPopout extends ConsumerStatefulWidget {
  const _MemberPopout({required this.spaceId, required this.userId});

  final String? spaceId;
  final String userId;

  @override
  ConsumerState<_MemberPopout> createState() => _MemberPopoutState();
}

class _MemberPopoutState extends ConsumerState<_MemberPopout> {
  final _message = TextEditingController();
  int? _relationship;
  bool _relationshipLoaded = false;
  List<AccordUser> _mutualFriends = const [];

  String get _serverKey => ref.readActiveServerKey() ?? '';

  @override
  void initState() {
    super.initState();
    _loadRelations();
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _loadRelations() async {
    if (widget.userId == ref.readUserId()) return;
    final type = await fetchRelationshipType(ref, widget.userId);
    final client = ref.accordClient;
    final mutual = client == null
        ? null
        : await client.users.getMutualFriends(widget.userId);
    if (!mounted) return;
    setState(() {
      _relationship = type;
      _relationshipLoaded = true;
      final data = mutual?.data;
      _mutualFriends = data is List
          ? data.whereType<AccordUser>().toList()
          : const [];
    });
  }

  /// "Message @x": sends, closes the popout and stays where you are. What the
  /// reference client does afterwards could not be seen without writing to
  /// someone: à confirmer.
  Future<void> _send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final navigator = Navigator.of(context);
    final sent = await sendDirectMessage(context, ref, widget.userId, trimmed);
    if (sent && mounted) navigator.pop();
  }

  void _openFull() {
    final navigator = Navigator.of(context);
    navigator.pop();
    showFullProfile(
      navigator.context,
      userId: widget.userId,
      spaceId: widget.spaceId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final serverKey = _serverKey;
    final spaceId = widget.spaceId;
    final member = spaceId == null
        ? null
        : ref.watch(
            accordMembersControllerProvider(
              serverKey,
              spaceId,
            ).select((m) => m?[widget.userId]),
          );
    final cachedUser = ref.watch(
      accordUsersControllerProvider(serverKey).select((m) => m[widget.userId]),
    );
    if (member == null && cachedUser == null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref
            .read(accordUsersControllerProvider(serverKey).notifier)
            .ensure(widget.userId),
      );
    }
    final space = spaceId == null
        ? null
        : ref.watch(
            spacesControllerProvider.select(
              (s) => s?.firstWhereOrNull((sp) => sp.id == spaceId),
            ),
          );
    final status = ref.watch(
      activePresencesProvider.select(
        (p) => accordPresenceStatus(p, widget.userId),
      ),
    );
    final customStatus = ref.watch(
      activePresencesProvider.select(
        (p) => accordCustomStatus(p, widget.userId),
      ),
    );
    final extras = ref
        .watch(profileExtrasProvider(serverKey, widget.userId))
        .asData
        ?.value;
    final cdnUrl = ref.watchCdnUrl();
    final selfId = ref.watchUserId();
    final isSelf = selfId != null && selfId == widget.userId;
    final user = member?.user ?? cachedUser;
    final name = member != null
        ? accordMemberName(member)
        : accordUserName(cachedUser, fallback: widget.userId);
    final username = user?.username ?? '';
    final avatarUrl = member != null
        ? accordMemberAvatarUrl(member, cdnUrl)
        : accordAvatarUrl(cachedUser, cdnUrl);
    final roles = space?.roles ?? const <AccordRole>[];
    final memberRoles = [
      for (final id in member?.roles ?? const <String>[])
        if (roles.firstWhereOrNull((r) => r.id == id) case final role?)
          if (role.position != 0) role,
    ]..sort((a, b) => b.position.compareTo(a.position));
    final perms = spaceId == null
        ? const <String>{}
        : ref.watchAccordPermissions(space, spaceId);
    final canManageRoles =
        member != null &&
        accordMemberOrigin(member) == null &&
        accordHasPermission(perms, AccordPermission.manageRoles);
    final remoteDomain = accordMemberOrigin(member) ?? accordUserOrigin(user);
    final card = profileCardColor(colors);
    final bannerColor = extras?.themePrimary != null
        ? profileColor(extras!.themePrimary!)
        : null;
    final bio = user?.bio?.trim();
    // Spaces of this connection whose member list holds the user (Accord has
    // no mutual-servers endpoint, §4).
    final mutualSpaces = isSelf
        ? 0
        : (ref.watch(spacesControllerProvider) ?? const <AccordSpace>[])
              .where(
                (s) => ref.watch(
                  accordMembersControllerProvider(
                    serverKey,
                    s.id,
                  ).select((m) => m?.containsKey(widget.userId) ?? false),
                ),
              )
              .length;

    final notFriend =
        !isSelf &&
        _relationshipLoaded &&
        _relationship != AccordRelationshipType.friend &&
        _relationship != AccordRelationshipType.blocked;

    return Material(
      type: MaterialType.transparency,
      child: Container(
        key: const Key('profile-popout'),
        width: kProfilePopoutWidth,
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.hairline),
          boxShadow: const [
            BoxShadow(
              color: Color(0x3D000000),
              offset: Offset(0, 12),
              blurRadius: 24,
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PopoutHeader(
                bannerColor: bannerColor,
                avatarUrl: avatarUrl,
                name: name,
                avatarColor: accordAvatarColor(user, widget.userId),
                status: status,
                customStatus: customStatus,
                isSelf: isSelf,
                cardColor: card,
                onOpenFull: _openFull,
                onEditStatus: isSelf
                    ? () {
                        Navigator.of(context).pop();
                        showCustomStatusDialog(context, ref);
                      }
                    : null,
                buttons: [
                  if (notFriend)
                    BannerRoundButton(
                      key: const Key('profile-add-friend'),
                      icon: AppIcons.personAdd,
                      tooltip: switch (_relationship) {
                        AccordRelationshipType.pendingOut => 'Pending',
                        _ => 'Add Friend',
                      },
                      onTap: (_) async {
                        await changeRelationship(
                          context,
                          ref,
                          widget.userId,
                          _relationship,
                        );
                        _loadRelations();
                      },
                    ),
                  BannerRoundButton(
                    key: const Key('profile-more'),
                    icon: AppIcons.moreHoriz,
                    tooltip: 'More',
                    onTap: (position) => showUserContextMenu(
                      context,
                      ref,
                      userId: widget.userId,
                      user: user,
                      spaceId: spaceId,
                      globalPosition: position,
                      origin: UserMenuOrigin.profile,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _NameBlock(
                      name: name,
                      username: username,
                      pronouns: extras?.pronouns,
                      remoteDomain: remoteDomain,
                      onTap: _openFull,
                    ),
                    if (bio != null && bio.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        bio,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          height: 18 / 14,
                          color: colors.dirtyWhite,
                        ),
                      ),
                    ],
                    if (!isSelf &&
                        (_mutualFriends.isNotEmpty || mutualSpaces > 0)) ...[
                      const SizedBox(height: 12),
                      _MutualLine(
                        friends: _mutualFriends,
                        servers: mutualSpaces,
                        cdnUrl: cdnUrl,
                        onTap: () {
                          final navigator = Navigator.of(context);
                          navigator.pop();
                          showFullProfile(
                            navigator.context,
                            userId: widget.userId,
                            spaceId: spaceId,
                            initialTab: FullProfileTab.mutualFriends,
                          );
                        },
                      ),
                    ],
                    if (memberRoles.isNotEmpty || canManageRoles) ...[
                      const SizedBox(height: 12),
                      _RoleList(
                        roles: memberRoles,
                        onAdd: canManageRoles
                            ? (position) => showAccordContextMenu(
                                context,
                                globalPosition: position,
                                entries: [
                                  for (final role
                                      in roles
                                          .where(
                                            (r) =>
                                                r.position != 0 && !r.managed,
                                          )
                                          .sortedBy<num>((r) => -r.position))
                                    AccordMenuEntry(
                                      label: role.name,
                                      checked: member.roles.contains(role.id),
                                      onSelected: () => setMemberRole(
                                        context,
                                        ref,
                                        spaceId: spaceId!,
                                        member: member,
                                        role: role,
                                        add: !member.roles.contains(role.id),
                                      ),
                                    ),
                                ],
                              )
                            : null,
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (isSelf)
                      _EditProfileButton(
                        onTap: () {
                          Navigator.of(context).pop();
                          openEditProfile(context);
                        },
                      )
                    else
                      _MessageField(
                        controller: _message,
                        name: username.isNotEmpty ? username : name,
                        onSend: _send,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
