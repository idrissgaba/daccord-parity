part of '../full_profile.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "19 Jun 2018", as the reference client writes dates on a profile.
String _profileDate(DateTime d) {
  final l = d.toLocal();
  return '${l.day} ${_months[l.month - 1]} ${l.year}';
}

/// The left card: banner 140, avatar 120 at (32, 80), name 24 / 600, the
/// buttons, then the labelled sections.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.cardColor,
    required this.bannerColor,
    required this.avatarUrl,
    required this.avatarColor,
    required this.name,
    required this.username,
    required this.pronouns,
    required this.remoteDomain,
    required this.status,
    required this.customStatus,
    required this.isSelf,
    required this.bio,
    required this.memberSince,
    required this.joinedSpace,
    required this.space,
    required this.friendsSince,
    required this.relationship,
    required this.note,
    required this.noteFocus,
    required this.onMessage,
    required this.onFriend,
    required this.onEditProfile,
    required this.onMore,
  });

  final Color cardColor;
  final Color? bannerColor;
  final String? avatarUrl;
  final Color avatarColor;
  final String name;
  final String username;
  final String? pronouns;
  final String? remoteDomain;
  final String status;
  final String? customStatus;
  final bool isSelf;
  final String? bio;
  final DateTime? memberSince;
  final DateTime? joinedSpace;
  final AccordSpace? space;
  final DateTime? friendsSince;
  final int? relationship;
  final TextEditingController? note;
  final FocusNode noteFocus;
  final VoidCallback? onMessage;
  final VoidCallback? onFriend;
  final VoidCallback? onEditProfile;
  final void Function(Offset position) onMore;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final muted = Color.lerp(colors.gray, colors.interactive, 0.5)!;
    final label = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      height: 16 / 12,
      color: colors.interactive,
    );
    final value = TextStyle(
      fontSize: 14,
      height: 18 / 14,
      color: colors.dirtyWhite,
    );
    Widget section(String title, Widget child) => Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: label),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
    final bioText = bio?.trim();
    final showBubble =
        isSelf || (customStatus != null && customStatus!.isNotEmpty);
    final squareStyle = IconButton.styleFrom(
      backgroundColor: menuButtonColor(colors),
      fixedSize: const Size(32, 32),
      minimumSize: const Size(32, 32),
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );

    return Container(
      key: const Key('full-profile-card'),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 140 + 80,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  ProfileBanner(
                    height: 140,
                    topRadius: 16,
                    color: bannerColor,
                    avatarUrl: avatarUrl,
                  ),
                  Positioned(
                    left: 26,
                    top: 74,
                    child: ProfileAvatarCutout(
                      size: 120,
                      ring: 6,
                      avatarUrl: avatarUrl,
                      initial: accordInitial(name),
                      backgroundColor: avatarColor,
                      status: status,
                      cardColor: cardColor,
                    ),
                  ),
                  if (showBubble)
                    Positioned(
                      left: 172,
                      top: 132,
                      child: CustomStatusBubble(
                        text: customStatus,
                        prompt: statusPromptOfTheDay(),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      height: 32 / 24,
                      color: colors.dirtyWhite,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (username.isNotEmpty) Text(username, style: value),
                      if (pronouns != null && pronouns!.isNotEmpty)
                        Text(
                          '• $pronouns',
                          style: value.copyWith(color: muted),
                        ),
                      if (remoteDomain != null)
                        RemoteOriginBadge(domain: remoteDomain!),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (onMessage != null)
                        SizedBox(
                          height: 32,
                          child: FilledButton.icon(
                            key: const Key('full-profile-message'),
                            onPressed: onMessage,
                            style: FilledButton.styleFrom(
                              backgroundColor: colors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            icon: const Icon(AppIcons.chatBubble, size: 16),
                            label: const Text('Message'),
                          ),
                        ),
                      if (onEditProfile != null)
                        SizedBox(
                          height: 32,
                          child: FilledButton.icon(
                            key: const Key('full-profile-edit'),
                            onPressed: onEditProfile,
                            style: FilledButton.styleFrom(
                              backgroundColor: colors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            icon: const Icon(AppIcons.edit, size: 16),
                            label: const Text('Edit Profile'),
                          ),
                        ),
                      if (onFriend != null &&
                          relationship != AccordRelationshipType.blocked) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          key: const Key('full-profile-friend'),
                          tooltip: switch (relationship) {
                            AccordRelationshipType.friend => 'Remove Friend',
                            AccordRelationshipType.pendingOut => 'Pending',
                            AccordRelationshipType.pendingIn => 'Accept',
                            _ => 'Add Friend',
                          },
                          style: squareStyle,
                          iconSize: 18,
                          color: colors.dirtyWhite,
                          icon: Icon(
                            relationship == AccordRelationshipType.friend
                                ? AppIcons.personRemoveOutlined
                                : AppIcons.personAdd,
                          ),
                          onPressed: onFriend,
                        ),
                      ],
                      const SizedBox(width: 8),
                      Builder(
                        builder: (buttonContext) => IconButton(
                          key: const Key('full-profile-more'),
                          tooltip: 'More',
                          style: squareStyle,
                          iconSize: 18,
                          color: colors.dirtyWhite,
                          icon: const Icon(AppIcons.moreHoriz),
                          onPressed: () {
                            final box =
                                buttonContext.findRenderObject() as RenderBox?;
                            onMore(
                              box?.localToGlobal(
                                    Offset(0, box.size.height + 4),
                                  ) ??
                                  Offset.zero,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  if (bioText != null && bioText.isNotEmpty)
                    section('About Me', Text(bioText, style: value)),
                  if (memberSince != null || joinedSpace != null)
                    section(
                      'Member Since',
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        children: [
                          if (memberSince != null)
                            Text(_profileDate(memberSince!), style: value),
                          if (memberSince != null && joinedSpace != null)
                            Text('•', style: value.copyWith(color: muted)),
                          if (joinedSpace != null) ...[
                            if (space != null)
                              _SpaceGlyph(space: space!, size: 16),
                            Text(_profileDate(joinedSpace!), style: value),
                          ],
                        ],
                      ),
                    ),
                  if (friendsSince != null)
                    section(
                      'Friends Since',
                      Text(_profileDate(friendsSince!), style: value),
                    ),
                  if (note != null)
                    section(
                      'Note (only visible to you)',
                      TextField(
                        key: const Key('profile-note'),
                        controller: note,
                        focusNode: noteFocus,
                        maxLength: 256,
                        minLines: 1,
                        maxLines: 4,
                        style: value,
                        decoration: InputDecoration(
                          isDense: true,
                          counterText: '',
                          hintText: 'Click to add a note',
                          hintStyle: value.copyWith(
                            color: muted,
                            fontStyle: FontStyle.italic,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 4,
                          ),
                          border: InputBorder.none,
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: colors.primary),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A space's icon (or initials) at [size].
class _SpaceGlyph extends ConsumerWidget {
  const _SpaceGlyph({required this.space, required this.size});

  final AccordSpace space;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final url = accordSpaceIconUrl(space, ref.watchCdnUrl());
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 3),
      child: SizedBox(
        width: size,
        height: size,
        child: url == null
            ? ColoredBox(
                color: colors.raised,
                child: Center(
                  child: Text(
                    accordSpaceInitials(space.name),
                    style: TextStyle(
                      fontSize: size * 0.35,
                      fontWeight: FontWeight.w600,
                      color: colors.dirtyWhite,
                    ),
                  ),
                ),
              )
            : Image.network(url, fit: BoxFit.cover),
      ),
    );
  }
}

/// Activity · N Mutual Friends · N Mutual Servers.
class _ProfileTabs extends StatelessWidget {
  const _ProfileTabs({
    required this.tab,
    required this.onTab,
    required this.name,
    required this.isSelf,
    required this.mutualFriends,
    required this.mutualSpaces,
    required this.cdnUrl,
    required this.onMessage,
  });

  final FullProfileTab tab;
  final ValueChanged<FullProfileTab> onTab;
  final String name;
  final bool isSelf;
  final List<AccordUser> mutualFriends;
  final List<AccordSpace> mutualSpaces;
  final String? cdnUrl;
  final VoidCallback? onMessage;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    Widget tabLabel(FullProfileTab t, String text) {
      final selected = t == tab;
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => onTab(t),
          child: Container(
            height: 30,
            margin: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: selected ? colors.dirtyWhite : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 14 / 14,
                color: selected ? colors.dirtyWhite : colors.interactive,
              ),
            ),
          ),
        ),
      );
    }

    final body = switch (tab) {
      FullProfileTab.activity => _ActivityEmpty(
        name: name,
        onMessage: onMessage,
      ),
      FullProfileTab.mutualFriends => ListView(
        padding: const EdgeInsets.only(top: 12),
        children: [
          for (final u in mutualFriends)
            _MutualRow(
              leading: Consumer(
                builder: (context, ref, _) => AccordMemberAvatar(
                  avatarUrl: accordAvatarUrl(u, cdnUrl),
                  initial: accordInitial(accordUserName(u, fallback: u.id)),
                  radius: 20,
                  backgroundColor: accordAvatarColor(u, u.id),
                  status: ref.watch(
                    activePresencesProvider.select(
                      (p) => accordPresenceStatus(p, u.id),
                    ),
                  ),
                  statusRingColor: colors.background,
                ),
              ),
              title: accordUserName(u, fallback: u.id),
            ),
        ],
      ),
      FullProfileTab.mutualServers => ListView(
        padding: const EdgeInsets.only(top: 12),
        children: [
          for (final s in mutualSpaces)
            _MutualRow(
              leading: _SpaceGlyph(space: s, size: 40),
              title: s.name,
            ),
        ],
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 27),
        Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.hairline)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                tabLabel(FullProfileTab.activity, 'Activity'),
                if (!isSelf) ...[
                  tabLabel(
                    FullProfileTab.mutualFriends,
                    mutualFriends.length == 1
                        ? '1 Mutual Friend'
                        : '${mutualFriends.length} Mutual Friends',
                  ),
                  tabLabel(
                    FullProfileTab.mutualServers,
                    mutualSpaces.length == 1
                        ? '1 Mutual Server'
                        : '${mutualSpaces.length} Mutual Servers',
                  ),
                ],
              ],
            ),
          ),
        ),
        Expanded(child: body),
      ],
    );
  }
}

/// "X doesn't have any activity to share here" with a Message button.
class _ActivityEmpty extends StatelessWidget {
  const _ActivityEmpty({required this.name, required this.onMessage});

  final String name;
  final VoidCallback? onMessage;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            onMessage == null
                ? "You don't have any activity to share here"
                : "$name doesn't have any activity to share here",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 20 / 16,
              color: colors.dirtyWhite,
            ),
          ),
          if (onMessage != null) ...[
            const SizedBox(height: 16),
            SizedBox(
              height: 32,
              child: TextButton.icon(
                onPressed: onMessage,
                style: TextButton.styleFrom(
                  backgroundColor: menuButtonColor(colors),
                  foregroundColor: colors.dirtyWhite,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                icon: const Icon(AppIcons.chatBubble, size: 16),
                label: const Text('Message'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MutualRow extends StatelessWidget {
  const _MutualRow({required this.leading, required this.title});

  final Widget leading;
  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return SizedBox(
      height: 62,
      child: Row(
        children: [
          leading,
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: colors.dirtyWhite,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
