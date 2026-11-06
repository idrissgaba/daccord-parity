part of 'accord_space_settings.dart';

/// "Membership" section: the change-your-nickname tile.
class _MembershipSection extends StatelessWidget {
  const _MembershipSection({required this.onEditNickname});

  final VoidCallback onEditNickname;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader('Membership'),
        ListTile(
          leading: Icon(AppIcons.badgeOutlined, color: colors.dirtyWhite),
          title: const Text('Change your nickname'),
          subtitle: const Text('How you appear in this space'),
          trailing: const Icon(AppIcons.chevronRight),
          onTap: onEditNickname,
        ),
      ],
    );
  }
}

/// "Management" section: permission-gated tiles that open the roles, audit
/// log, ban list, reports, emoji, and soundboard screens.
class _ManagementSection extends StatelessWidget {
  const _ManagementSection({
    required this.spaceId,
    required this.canManageRoles,
    required this.canViewAuditLog,
    required this.canModerate,
    required this.canManageEmojis,
    required this.canOpenSoundboard,
    required this.serverKey,
    this.canManageWebhooks = false,
  });

  final String spaceId;
  final bool canManageRoles;
  final bool canViewAuditLog;
  final bool canModerate;
  final bool canManageEmojis;
  final bool canOpenSoundboard;
  final String serverKey;
  final bool canManageWebhooks;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader('Management'),
        if (canManageRoles)
          ListTile(
            leading: Icon(AppIcons.shieldOutlined, color: colors.dirtyWhite),
            title: const Text('Roles'),
            subtitle: const Text('Create, edit, and order roles'),
            trailing: const Icon(AppIcons.chevronRight),
            onTap: () => showAccordRoleManagement(context, spaceId: spaceId),
          ),
        if (canViewAuditLog)
          ListTile(
            leading: Icon(AppIcons.history, color: colors.dirtyWhite),
            title: const Text('Audit log'),
            subtitle: const Text('Recent moderation and admin actions'),
            trailing: const Icon(AppIcons.chevronRight),
            onTap: () => showAccordAuditLog(context, spaceId: spaceId),
          ),
        if (canModerate) ...[
          ListTile(
            leading: Icon(AppIcons.gavel, color: colors.dirtyWhite),
            title: const Text('Banned members'),
            subtitle: const Text('Review and unban members'),
            trailing: const Icon(AppIcons.chevronRight),
            onTap: () => showAccordBanList(context, spaceId: spaceId),
          ),
          ListTile(
            leading: Icon(AppIcons.flagOutlined, color: colors.dirtyWhite),
            title: const Text('Reports'),
            subtitle: const Text('Review and resolve member reports'),
            trailing: const Icon(AppIcons.chevronRight),
            onTap: () => showReportsPanel(context, spaceId: spaceId),
          ),
        ],
        if (canManageEmojis)
          ListTile(
            leading: Icon(
              AppIcons.emojiEmotionsOutlined,
              color: colors.dirtyWhite,
            ),
            title: const Text('Custom emoji'),
            subtitle: const Text('Upload, rename, and delete emoji'),
            trailing: const Icon(AppIcons.chevronRight),
            onTap: () => showAccordEmojiManagement(context, spaceId: spaceId),
          ),
        if (canManageEmojis)
          ListTile(
            key: const Key('space-settings-stickers'),
            leading: Icon(
              AppIcons.stickyNote2Outlined,
              color: colors.dirtyWhite,
            ),
            title: const Text('Stickers'),
            subtitle: const Text('Upload, rename, and delete stickers'),
            trailing: const Icon(AppIcons.chevronRight),
            onTap: () => showStickerManagement(context, spaceId: spaceId),
          ),
        if (canOpenSoundboard)
          ListTile(
            key: const Key('space-settings-soundboard'),
            leading: Icon(AppIcons.celebration, color: colors.dirtyWhite),
            title: const Text('Soundboard'),
            subtitle: const Text('Upload, edit, and delete sounds'),
            trailing: const Icon(AppIcons.chevronRight),
            onTap: () => showSpaceSoundboardSettings(
              context,
              serverKey: serverKey,
              spaceId: spaceId,
            ),
          ),
        if (canManageWebhooks)
          ListTile(
            key: const Key('space-settings-webhooks'),
            leading: Icon(AppIcons.webhook, color: colors.dirtyWhite),
            title: const Text('Webhooks'),
            subtitle: const Text('Let services post into a channel'),
            trailing: const Icon(AppIcons.chevronRight),
            onTap: () => showAccordWebhooks(context, spaceId: spaceId),
          ),
      ],
    );
  }
}

/// "Danger zone" section (owner only): transfer ownership and delete space.
class _DangerZoneSection extends StatelessWidget {
  const _DangerZoneSection({
    required this.spaceId,
    required this.busy,
    required this.onDeleteSpace,
  });

  final String spaceId;
  final bool busy;
  final VoidCallback onDeleteSpace;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader('Danger zone'),
        ListTile(
          leading: Icon(AppIcons.swapHoriz, color: colors.dirtyWhite),
          title: const Text('Transfer ownership'),
          subtitle: const Text('Hand this space to another member'),
          trailing: const Icon(AppIcons.chevronRight),
          onTap: () => showTransferOwnership(context, spaceId: spaceId),
        ),
        ListTile(
          leading: Icon(AppIcons.deleteForever, color: colors.red),
          title: Text('Delete space', style: TextStyle(color: colors.red)),
          subtitle: const Text('Permanently remove this space'),
          onTap: busy ? null : onDeleteSpace,
        ),
      ],
    );
  }
}
