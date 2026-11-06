part of 'accord_space_settings.dart';

/// A settings text input: 40 px (or [minLines] tall), the shared field fill.
class _SettingsTextField extends StatefulWidget {
  const _SettingsTextField({
    super.key,
    required this.controller,
    required this.colors,
    this.minLines = 1,
    this.maxLines = 1,
    this.maxLength,
    this.autofocus = false,
    this.onChanged,
  });

  final TextEditingController controller;
  final BonfireThemeExtension colors;
  final int minLines;
  final int maxLines;
  final int? maxLength;
  final bool autofocus;
  final ValueChanged<String>? onChanged;

  @override
  State<_SettingsTextField> createState() => _SettingsTextFieldState();
}

class _SettingsTextFieldState extends State<_SettingsTextField> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return Container(
      constraints: BoxConstraints(minHeight: widget.maxLines == 1 ? 40 : 96),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: settingsFieldDecoration(colors, focused: _focus.hasFocus),
      alignment: Alignment.centerLeft,
      child: TextField(
        controller: widget.controller,
        focusNode: _focus,
        autofocus: widget.autofocus,
        minLines: widget.minLines,
        maxLines: widget.maxLines,
        maxLength: widget.maxLength,
        onChanged: widget.onChanged,
        cursorColor: colors.dirtyWhite,
        style: TextStyle(fontSize: 16, height: 20 / 16, color: colors.dirtyWhite),
        decoration: InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          counterText: '',
          hintStyle: TextStyle(
            fontSize: 16,
            height: 20 / 16,
            color: colors.gray,
          ),
        ),
      ),
    );
  }
}

/// The hairline between the fields of a server-settings page, 40 px clear
/// on both sides.
class _FieldDivider extends StatelessWidget {
  const _FieldDivider();

  @override
  Widget build(BuildContext context) =>
      const SettingsDivider(top: 40, bottom: 40);
}

/// A 16/500 field label with its optional 14/400 description.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label, [this.description]);

  final String label;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: SettingsText.label(colors)),
          if (description != null) ...[
            const SizedBox(height: 4),
            Text(description!, style: SettingsText.description(colors)),
          ],
        ],
      ),
    );
  }
}

/// A small link-coloured text button ("Remove Icon").
class _TextLink extends StatelessWidget {
  const _TextLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: colors.dirtyWhite,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        minimumSize: const Size(0, 32),
      ),
      child: Text(label),
    );
  }
}

/// Server Settings › Server Profile: name, icon, banner and description on
/// the left, the invite-card preview at the right.
class _ServerProfilePage extends ConsumerWidget {
  const _ServerProfilePage({
    required this.space,
    required this.name,
    required this.description,
    required this.pendingIconBytes,
    required this.iconRemoved,
    required this.pendingBannerBytes,
    required this.bannerRemoved,
    required this.busy,
    required this.onPickIcon,
    required this.onRemoveIcon,
    required this.onPickBanner,
    required this.onRemoveBanner,
  });

  final AccordSpace space;
  final TextEditingController name;
  final TextEditingController description;
  final Uint8List? pendingIconBytes;
  final bool iconRemoved;
  final Uint8List? pendingBannerBytes;
  final bool bannerRemoved;
  final bool busy;
  final VoidCallback onPickIcon;
  final VoidCallback onRemoveIcon;
  final VoidCallback onPickBanner;
  final VoidCallback onRemoveBanner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final cdnUrl = ref.watchCdnUrl();
    final iconUrl = iconRemoved ? null : accordSpaceIconUrl(space, cdnUrl);
    final bannerUrl = bannerRemoved
        ? null
        : accordSpaceBannerUrl(space, cdnUrl);
    final hasIcon = pendingIconBytes != null || iconUrl != null;
    final hasBanner = pendingBannerBytes != null || bannerUrl != null;
    final form = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsPageHeader(
          title: 'Server Profile',
          description:
              'Customise how your server appears in invite links and, if '
              'enabled, in Server Discovery.',
        ),
        const _FieldLabel('Name'),
        _SettingsTextField(
          key: const Key('space-settings-name'),
          controller: name,
          colors: colors,
          maxLength: 100,
        ),
        const _FieldDivider(),
        const _FieldLabel('Icon', 'We recommend an image of at least 512x512.'),
        Row(
          children: [
            AccordButton(
              key: const Key('space-settings-change-icon'),
              label: 'Change Server Icon',
              small: true,
              onPressed: busy ? null : onPickIcon,
            ),
            if (hasIcon) ...[
              const SizedBox(width: 8),
              _TextLink(
                label: 'Remove Icon',
                onTap: busy ? null : onRemoveIcon,
              ),
            ],
          ],
        ),
        const _FieldDivider(),
        const _FieldLabel(
          'Banner',
          'Shown behind the server name in the channel list and on invite '
              'cards. 16:9, at least 960×540.',
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 280,
            child: SpaceSettingsBannerPreview(
              url: bannerUrl,
              pendingBytes: pendingBannerBytes,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            AccordButton(
              key: const Key('space-settings-change-banner'),
              label: 'Change Server Banner',
              small: true,
              onPressed: busy ? null : onPickBanner,
            ),
            if (hasBanner) ...[
              const SizedBox(width: 8),
              _TextLink(
                label: 'Remove Banner',
                onTap: busy ? null : onRemoveBanner,
              ),
            ],
          ],
        ),
        const _FieldDivider(),
        const _FieldLabel(
          'Description',
          'How should people describe your server?',
        ),
        _SettingsTextField(
          key: const Key('space-settings-description'),
          controller: description,
          colors: colors,
          minLines: 3,
          maxLines: 6,
          maxLength: 300,
        ),
        // Room for the unsaved-changes bar under the last field.
        const SizedBox(height: 80),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final preview = _ServerPreviewCard(
          space: space,
          name: name,
          iconUrl: iconUrl,
          pendingIconBytes: pendingIconBytes,
          bannerUrl: bannerUrl,
          pendingBannerBytes: pendingBannerBytes,
        );
        if (constraints.maxWidth < 900) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [form, preview],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 560, child: form),
            const SizedBox(width: 39),
            SizedBox(width: 299, child: preview),
          ],
        );
      },
    );
  }
}

/// The invite card at the right of Server Profile: banner, icon, name, how
/// many are online and members, and when the server was established.
class _ServerPreviewCard extends ConsumerWidget {
  const _ServerPreviewCard({
    required this.space,
    required this.name,
    required this.iconUrl,
    required this.pendingIconBytes,
    required this.bannerUrl,
    required this.pendingBannerBytes,
  });

  final AccordSpace space;
  final TextEditingController name;
  final String? iconUrl;
  final Uint8List? pendingIconBytes;
  final String? bannerUrl;
  final Uint8List? pendingBannerBytes;

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final serverKey = ref.watchActiveServerKey() ?? '';
    final members = ref.watch(
      accordMembersControllerProvider(serverKey, space.id),
    );
    final presences = ref.watch(activePresencesProvider);
    final total = members?.length ?? space.memberCount;
    final online = members == null
        ? 0
        : members.keys
              .where(
                (id) => accordPresenceStatus(presences, id) != 'offline',
              )
              .length;
    final created = DateTime.tryParse(space.createdAt);
    final ImageProvider? banner = pendingBannerBytes != null
        ? MemoryImage(pendingBannerBytes!)
        : bannerUrl != null
        ? NetworkImage(bannerUrl!)
        : null;
    final ImageProvider? icon = pendingIconBytes != null
        ? MemoryImage(pendingIconBytes!)
        : iconUrl != null
        ? NetworkImage(iconUrl!)
        : null;
    final small = TextStyle(
      fontSize: 12,
      height: 16 / 12,
      color: colors.interactive,
    );
    Widget dot(Color c) => Container(
      width: 8,
      height: 8,
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
    );
    return Container(
      key: const Key('space-settings-preview'),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                height: 120,
                decoration: BoxDecoration(
                  gradient: banner == null
                      ? LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [colors.foreground, colors.raised],
                        )
                      : null,
                  image: banner == null
                      ? null
                      : DecorationImage(image: banner, fit: BoxFit.cover),
                ),
              ),
              Positioned(
                left: 16,
                top: 88,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: colors.foreground,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colors.background, width: 4),
                    image: icon == null
                        ? null
                        : DecorationImage(image: icon, fit: BoxFit.cover),
                  ),
                  alignment: Alignment.center,
                  child: icon == null
                      ? Text(
                          accordSpaceInitials(space.name),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: colors.dirtyWhite,
                          ),
                        )
                      : null,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 44, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListenableBuilder(
                  listenable: name,
                  builder: (context, _) => Text(
                    name.text.trim().isEmpty ? space.name : name.text.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      height: 20 / 16,
                      color: colors.dirtyWhite,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    dot(colors.green),
                    Text('$online Online', style: small),
                    const SizedBox(width: 8),
                    dot(colors.gray),
                    Text(
                      '$total ${total == 1 ? 'Member' : 'Members'}',
                      style: small,
                    ),
                  ],
                ),
                if (created != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Est. ${_months[created.month - 1]} ${created.year}',
                    style: small,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The space's text channels, for the channel pickers.
List<AccordChannel> _textChannels(
  WidgetRef ref,
  String serverKey,
  String spaceId,
) =>
    (ref.watch(accordChannelsControllerProvider(serverKey, spaceId)) ??
            const <AccordChannel>[])
        .where((c) => c.type == 'text')
        .toList();

/// A channel select with a leading "No channel" option; a stale id shows as
/// that option.
class _ChannelSelect extends ConsumerWidget {
  const _ChannelSelect({
    super.key,
    required this.spaceId,
    required this.serverKey,
    required this.value,
    required this.onChanged,
  });

  final String spaceId;
  final String serverKey;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channels = _textChannels(ref, serverKey, spaceId);
    final ids = channels.map((c) => c.id).toSet();
    return AccordSelect<String?>(
      value: ids.contains(value) ? value : null,
      leadingIcon: AppIcons.tag,
      options: [
        const AccordSelectOption(null, 'No channel'),
        for (final c in channels) AccordSelectOption(c.id, c.name ?? c.id),
      ],
      onChanged: onChanged,
    );
  }
}

/// Server Settings › Engagement: where system messages go, the default
/// notification level for new members, and the welcome screen.
class _EngagementPage extends StatelessWidget {
  const _EngagementPage({
    required this.spaceId,
    required this.serverKey,
    required this.systemChannelId,
    required this.notifications,
    required this.onSystemChannel,
    required this.onNotifications,
  });

  final String spaceId;
  final String serverKey;
  final String? systemChannelId;
  final String notifications;
  final ValueChanged<String?> onSystemChannel;
  final ValueChanged<String> onNotifications;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsPageHeader(
          title: 'Engagement',
          description:
              'Choose how members are greeted and how they are notified.',
        ),
        const _FieldLabel(
          'System Messages Channel',
          'This is the channel we send system event messages to, such as '
              'members joining.',
        ),
        _ChannelSelect(
          key: const Key('space-settings-system-channel'),
          spaceId: spaceId,
          serverKey: serverKey,
          value: systemChannelId,
          onChanged: onSystemChannel,
        ),
        const _FieldDivider(),
        const _FieldLabel(
          'Default Notification Settings',
          'This will determine whether members who have not explicitly set '
              'their notification settings receive a notification for every '
              'message sent in this server or not.',
        ),
        const SizedBox(height: 8),
        AccordRadioRow(
          key: const Key('space-settings-notify-all'),
          label: 'All Messages',
          selected: notifications == 'all',
          onTap: () => onNotifications('all'),
        ),
        const SizedBox(height: 8),
        AccordRadioRow(
          key: const Key('space-settings-notify-mentions'),
          label: 'Only @mentions',
          selected: notifications == 'mentions',
          onTap: () => onNotifications('mentions'),
        ),
        const _FieldDivider(),
        SettingsLinkCard(
          icon: AppIcons.wavingHandOutlined,
          title: 'Welcome Screen',
          description: 'Greet new members and point them around.',
          onTap: () => showWelcomeScreenEditor(context, spaceId: spaceId),
        ),
        const SizedBox(height: 80),
      ],
    );
  }
}

/// Server Settings › Access: who can join (invite only or discoverable),
/// guests, the rules channel, verification, age restriction and the
/// explicit-content filter.
class _AccessPage extends StatelessWidget {
  const _AccessPage({
    required this.spaceId,
    required this.serverKey,
    required this.isPublic,
    required this.guestAccess,
    required this.verification,
    required this.nsfw,
    required this.contentFilter,
    required this.rulesChannelId,
    required this.onPublic,
    required this.onGuestAccess,
    required this.onVerification,
    required this.onNsfw,
    required this.onContentFilter,
    required this.onRulesChannel,
  });

  final String spaceId;
  final String serverKey;
  final bool isPublic;
  final bool guestAccess;
  final String verification;
  final String nsfw;
  final String contentFilter;
  final String? rulesChannelId;
  final ValueChanged<bool> onPublic;
  final ValueChanged<bool> onGuestAccess;
  final ValueChanged<String> onVerification;
  final ValueChanged<String> onNsfw;
  final ValueChanged<String> onContentFilter;
  final ValueChanged<String?> onRulesChannel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsPageHeader(title: 'Access', bottom: 32),
        const _FieldLabel(
          'How can people join your server?',
          'Keep your server private or open it up for more people to join.',
        ),
        const SizedBox(height: 8),
        _JoinModeCards(isPublic: isPublic, onPublic: onPublic),
        const _FieldDivider(),
        SettingsSwitchRow(
          key: const Key('space-settings-nsfw'),
          label: 'Age-Restricted Server',
          description:
              'Users will need to confirm that they are of over the legal '
              'age to view the content in this server.',
          value: nsfw != 'default',
          onChanged: (on) => onNsfw(on ? 'explicit' : 'default'),
        ),
        const _FieldDivider(),
        const _FieldLabel(
          'Server Rules',
          'Members must agree to the rules posted in this channel before they '
              'can chat or interact in the server.',
        ),
        _ChannelSelect(
          key: const Key('space-settings-rules-channel'),
          spaceId: spaceId,
          serverKey: serverKey,
          value: rulesChannelId,
          onChanged: onRulesChannel,
        ),
        const _FieldDivider(),
        SettingsSwitchRow(
          key: const Key('space-settings-guest-access'),
          label: 'Guest Access',
          description:
              'People without an account can browse this server read-only.',
          value: guestAccess,
          onChanged: onGuestAccess,
        ),
        const _FieldDivider(),
        const _FieldLabel(
          'Verification Level',
          'Members must meet the following criteria before they can send '
              'messages.',
        ),
        AccordSelect<String>(
          key: const Key('space-settings-verification'),
          value: verification,
          options: [
            for (final o in _verificationLevels)
              AccordSelectOption(o.value, o.label),
          ],
          onChanged: onVerification,
        ),
        const _FieldDivider(),
        const _FieldLabel(
          'Explicit Media Content Filter',
          'Automatically scan and delete media sent in this server that '
              'contains explicit content.',
        ),
        AccordSelect<String>(
          key: const Key('space-settings-content-filter'),
          value: contentFilter,
          options: [
            for (final o in _contentFilters) AccordSelectOption(o.value, o.label),
          ],
          onChanged: onContentFilter,
        ),
        const SizedBox(height: 80),
      ],
    );
  }
}

/// The two join modes as the reference client's option cards (Apply to
/// Join has no Accord counterpart).
class _JoinModeCards extends StatelessWidget {
  const _JoinModeCards({required this.isPublic, required this.onPublic});

  final bool isPublic;
  final ValueChanged<bool> onPublic;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    Widget card({
      required Key key,
      required IconData icon,
      required String title,
      required String text,
      required bool selected,
      required VoidCallback onTap,
    }) => Expanded(
      child: InkWell(
        key: key,
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 132,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFF94949C).withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? colors.hairline : Colors.transparent,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: colors.dirtyWhite),
              const SizedBox(height: 8),
              Text(
                title,
                style: SettingsText.label(colors).copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 16 / 12,
                  color: colors.dirtyWhite,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          card(
            key: const Key('space-settings-invite-only'),
            icon: AppIcons.lock,
            title: 'Invite Only',
            text: 'People can join your server directly with an invite',
            selected: !isPublic,
            onTap: () => onPublic(false),
          ),
          const SizedBox(width: 8),
          card(
            key: const Key('space-settings-discoverable'),
            icon: AppIcons.public,
            title: 'Discoverable',
            text: 'Anyone can join your server directly through Server '
                'Discovery',
            selected: isPublic,
            onTap: () => onPublic(true),
          ),
        ],
      ),
    );
  }
}
