part of '../accord_member_popout.dart';

/// The banner (105 px) with the avatar (80 px at 16, 61) astride it and the
/// status bubble to the avatar's right.
class _PopoutHeader extends StatelessWidget {
  const _PopoutHeader({
    required this.bannerColor,
    required this.avatarUrl,
    required this.name,
    required this.avatarColor,
    required this.status,
    required this.customStatus,
    required this.isSelf,
    required this.cardColor,
    required this.onOpenFull,
    required this.onEditStatus,
    required this.buttons,
  });

  final Color? bannerColor;
  final String? avatarUrl;
  final String name;
  final Color avatarColor;
  final String status;
  final String? customStatus;
  final bool isSelf;
  final Color cardColor;
  final VoidCallback onOpenFull;
  final VoidCallback? onEditStatus;
  final List<Widget> buttons;

  @override
  Widget build(BuildContext context) {
    final showBubble =
        isSelf || (customStatus != null && customStatus!.isNotEmpty);
    return SizedBox(
      height: 105 + 44,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: GestureDetector(
              onTap: onOpenFull,
              child: ProfileBanner(
                height: 105,
                topRadius: 7,
                color: bannerColor,
                avatarUrl: avatarUrl,
                trailing: buttons,
              ),
            ),
          ),
          Positioned(
            left: 12,
            top: 57,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                key: const Key('profile-popout-avatar'),
                onTap: onOpenFull,
                child: ProfileAvatarCutout(
                  size: 80,
                  ring: 4,
                  avatarUrl: avatarUrl,
                  initial: accordInitial(name),
                  backgroundColor: avatarColor,
                  status: status,
                  cardColor: cardColor,
                ),
              ),
            ),
          ),
          if (showBubble)
            Positioned(
              left: 106,
              top: 99,
              child: CustomStatusBubble(
                text: customStatus,
                prompt: statusPromptOfTheDay(),
                onTap: onEditStatus,
              ),
            ),
        ],
      ),
    );
  }
}

/// Display name (20 / 600) over the username, pronouns and origin badge.
class _NameBlock extends StatelessWidget {
  const _NameBlock({
    required this.name,
    required this.username,
    required this.pronouns,
    required this.remoteDomain,
    required this.onTap,
  });

  final String name;
  final String username;
  final String? pronouns;
  final String? remoteDomain;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final muted = Color.lerp(colors.gray, colors.interactive, 0.5)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onTap,
            child: Text(
              name,
              key: const Key('profile-popout-name'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                height: 24 / 20,
                color: colors.dirtyWhite,
              ),
            ),
          ),
        ),
        const SizedBox(height: 3),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          runSpacing: 4,
          children: [
            if (username.isNotEmpty)
              Text(
                username,
                style: TextStyle(
                  fontSize: 14,
                  height: 18 / 14,
                  color: colors.dirtyWhite,
                ),
              ),
            if (pronouns != null && pronouns!.isNotEmpty)
              Text(
                '• $pronouns',
                style: TextStyle(fontSize: 14, height: 18 / 14, color: muted),
              ),
            if (remoteDomain != null) RemoteOriginBadge(domain: remoteDomain!),
          ],
        ),
      ],
    );
  }
}

/// "[avatar] 1 Mutual Friend • 1 Mutual Server" (12 px), opening the full
/// profile on the friends tab.
class _MutualLine extends StatelessWidget {
  const _MutualLine({
    required this.friends,
    required this.servers,
    required this.cdnUrl,
    required this.onTap,
  });

  final List<AccordUser> friends;
  final int servers;
  final String? cdnUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final style = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      height: 16 / 12,
      color: colors.interactive,
    );
    final parts = [
      if (friends.isNotEmpty)
        friends.length == 1 ? '1 Mutual Friend' : '${friends.length} Mutual Friends',
      if (servers > 0) servers == 1 ? '1 Mutual Server' : '$servers Mutual Servers',
    ];
    final first = friends.firstOrNull;
    return Align(
      alignment: Alignment.centerLeft,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (first != null) ...[
                AccordMemberAvatar(
                  avatarUrl: accordAvatarUrl(first, cdnUrl),
                  initial: accordInitial(accordUserName(first, fallback: first.id)),
                  radius: 8,
                  backgroundColor: accordAvatarColor(first, first.id),
                  initialStyle: const TextStyle(fontSize: 7),
                ),
                const SizedBox(width: 4),
              ],
              Text(parts.join(' • '), style: style),
            ],
          ),
        ),
      ),
    );
  }
}

/// The member's role pills, and "+ Add role" for those who manage roles.
class _RoleList extends StatelessWidget {
  const _RoleList({required this.roles, required this.onAdd});

  final List<AccordRole> roles;
  final void Function(Offset position)? onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final pillColor = profileBubbleColor(colors);
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final role in roles)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: pillColor,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: accordRoleColor(role.color) ?? colors.gray,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  role.name,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: colors.dirtyWhite,
                  ),
                ),
              ],
            ),
          ),
        if (onAdd != null)
          GestureDetector(
            key: const Key('profile-add-role'),
            onTapUp: (d) => onAdd!(d.globalPosition),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(AppIcons.add, size: 14, color: colors.interactive),
                    const SizedBox(width: 4),
                    Text(
                      'Add role',
                      style: TextStyle(
                        fontSize: 12,
                        height: 16 / 12,
                        color: colors.interactive,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Your own card's "Edit Profile": a full-width accent button.
class _EditProfileButton extends StatelessWidget {
  const _EditProfileButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return SizedBox(
      height: 32,
      child: FilledButton.icon(
        key: const Key('profile-edit'),
        style: FilledButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          padding: EdgeInsets.zero,
        ),
        onPressed: onTap,
        icon: const Icon(AppIcons.edit, size: 16),
        label: const Text('Edit Profile'),
      ),
    );
  }
}

/// "Message @name" with the emoji button, sending on Enter.
class _MessageField extends ConsumerWidget {
  const _MessageField({
    required this.controller,
    required this.name,
    required this.onSend,
  });

  final TextEditingController controller;
  final String name;
  final ValueChanged<String> onSend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final muted = Color.lerp(colors.gray, colors.interactive, 0.5)!;
    return Container(
      height: 40,
      padding: const EdgeInsets.only(left: 12, right: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.hairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('profile-message-field'),
              controller: controller,
              onSubmitted: onSend,
              style: TextStyle(fontSize: 14, color: colors.dirtyWhite),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Message @$name',
                hintStyle: TextStyle(fontSize: 14, color: muted),
              ),
            ),
          ),
          Builder(
            builder: (buttonContext) => IconButton(
              tooltip: 'Select emoji',
              iconSize: 20,
              color: colors.interactive,
              icon: const Icon(AppIcons.emojiEmotionsOutlined),
              onPressed: () async {
                final pick = await showAccordEmojiPicker(buttonContext);
                if (pick == null) return;
                controller.text += pick.composerText;
              },
            ),
          ),
        ],
      ),
    );
  }
}
