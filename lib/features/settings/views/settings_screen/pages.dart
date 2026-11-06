part of '../accord_settings_screen.dart';

/// The body of [page], shared by the desktop modal and the phone pages.
class _SettingsPageBody extends StatelessWidget {
  const _SettingsPageBody({required this.page, required this.onOpenPage});

  final SettingsPage page;
  final ValueChanged<SettingsPage> onOpenPage;

  @override
  Widget build(BuildContext context) {
    return switch (page) {
      SettingsPage.account => const _AccountPage(),
      SettingsPage.dataPrivacy => const PrivacySettingsScreen(embedded: true),
      SettingsPage.notifications => const _NotificationsPage(),
      SettingsPage.voiceVideo => VoiceVideoSettingsPage(
        onOpenNotifications: () => onOpenPage(SettingsPage.notifications),
      ),
      SettingsPage.appearance => _AppearancePage(onOpenPage: onOpenPage),
      SettingsPage.accessibility => _AccessibilityPage(onOpenPage: onOpenPage),
      SettingsPage.system => const _SystemPage(),
      SettingsPage.connectedApps => const ConnectionsScreen(embedded: true),
      SettingsPage.developer => const _DeveloperPage(),
    };
  }
}

/// Lays sections out separated by hairlines.
class _Sections extends StatelessWidget {
  const _Sections(this.children);

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, child) in children.indexed) ...[
          if (i > 0) const SettingsDivider(),
          child,
        ],
      ],
    );
  }
}

/// One anchored section: its title and rows.
class _Section extends StatelessWidget {
  const _Section({
    required this.id,
    required this.title,
    required this.children,
    this.gap = 32,
  });

  final String id;
  final String title;
  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return SettingsAnchor(
      id: id,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsSectionTitle(title),
          SettingsRows(gap: gap, children: children),
        ],
      ),
    );
  }
}

/// A label with a value and a chevron at the right ("5 devices ›").
class _ChevronRow extends StatelessWidget {
  const _ChevronRow({
    required this.label,
    this.value,
    this.onTap,
    this.onTapAt,
  });

  final String label;
  final String? value;
  final VoidCallback? onTap;

  /// Like [onTap], with where the pointer went up (menus anchor there).
  final ValueChanged<Offset>? onTapAt;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return InkWell(
      onTap: onTap ?? () {},
      onTapUp: onTapAt == null ? null : (d) => onTapAt!(d.globalPosition),
      borderRadius: BorderRadius.circular(8),
      child: SettingsRow(
        label: label,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (value != null) Text(value!, style: SettingsText.label(colors)),
            const SizedBox(width: 4),
            Icon(AppIcons.chevronRight, size: 20, color: colors.dirtyWhite),
          ],
        ),
      ),
    );
  }
}

/// A label with a value and an "Edit" button at the right.
class _EditRow extends StatelessWidget {
  const _EditRow({
    super.key,
    required this.label,
    this.value,
    required this.onEdit,
    this.buttonLabel = 'Edit',
  });

  final String label;
  final String? value;
  final VoidCallback onEdit;
  final String buttonLabel;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return SettingsRow(
      label: label,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(
                value!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SettingsText.label(colors),
              ),
            ),
            const SizedBox(width: 16),
          ],
          AccordButton(
            label: buttonLabel,
            tone: AccordButtonTone.secondary,
            minWidth: 99,
            onPressed: onEdit,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Account
// ---------------------------------------------------------------------------

class _AccountPage extends ConsumerWidget {
  const _AccountPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(
      accordAuthProvider.select(
        (s) => s is AccordAuthLoggedIn ? s.session : null,
      ),
    );
    final multiple = ref.watch(connectionsControllerProvider).hasMultiple;
    return _Sections([
      _Section(
        id: 'account-info',
        title: 'Account Info',
        children: [
          _EditRow(
            key: const Key('settings-edit-profile'),
            label: 'Username',
            value: session?.username,
            onEdit: () => showAccordProfileEdit(context),
          ),
          if (session != null)
            SettingsRow(
              label: 'Server',
              trailing: _Value(session.server.baseUrl),
            ),
          if (multiple)
            _ChevronRow(
              label: 'Per-server Profile',
              onTapAt: (position) => _pickServerProfile(context, ref, position),
            ),
          _ChevronRow(
            label: 'Switch Accounts',
            onTap: () => context.push('/switcher'),
          ),
          _ChevronRow(
            label: 'Device Profiles',
            onTap: () => showProfilesSettings(context),
          ),
          if (session?.isAdmin ?? false)
            _ChevronRow(
              label: 'Server Administration',
              onTap: () => context.push('/admin'),
            ),
        ],
      ),
      _Section(
        id: 'password-security',
        title: 'Password & Security',
        children: [
          _EditRow(
            key: const Key('settings-password'),
            label: 'Password',
            onEdit: () => showAccordAccountSettings(context),
          ),
          _ChevronRow(
            label: 'Multi-Factor Authentication',
            value: 'Set up',
            onTap: () => showAccordAccountSettings(context),
          ),
        ],
      ),
    ]);
  }
}

class _Value extends StatelessWidget {
  const _Value(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: SettingsText.label(colors),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Notifications
// ---------------------------------------------------------------------------

/// The message and call sounds; the voice ones live under Voice & Video ›
/// Sounds, as in the reference client.
const List<String> kNotificationSoundNames = [
  'message_received',
  'mention_received',
  'message_sent',
  'ringtone',
  'ring_outgoing',
];

class _NotificationsPage extends ConsumerWidget {
  const _NotificationsPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    return _Sections([
      _Section(
        id: 'notifications-overview',
        title: 'Overview',
        children: [
          SettingsSwitchRow(
            key: const Key('settings-desktop-notifications'),
            label: 'Enable Desktop Notifications',
            description:
                "If you're looking for per-channel or per-server "
                'notifications, right-click the desired server icon and '
                'select Notification Settings.',
            value: settings.notificationsEnabled,
            onChanged: controller.setNotificationsEnabled,
          ),
          SettingsSwitchRow(
            label: 'Suppress @everyone and @here',
            description: 'Never notify for @everyone and @here mentions.',
            value: settings.suppressEveryone,
            onChanged: settings.notificationsEnabled
                ? controller.setSuppressEveryone
                : null,
          ),
          // Android sideload builds only — see
          // [isBackgroundConnectionAvailable] (#306).
          if (isBackgroundConnectionAvailable)
            SettingsSwitchRow(
              key: const Key('background-connection-switch'),
              label: 'Stay connected in the background',
              description:
                  'Keeps notifications arriving while the app is closed. '
                  'Shows a permanent notification and uses more battery.',
              value: settings.backgroundConnection,
              onChanged: controller.setBackgroundConnection,
            ),
        ],
      ),
      _Section(
        id: 'notifications-sounds',
        title: 'Sounds',
        children: [
          SettingsSwitchRow(
            key: const Key('settings-sounds-enabled'),
            label: 'Enable Sounds',
            description: 'Play sound effects for messages, calls and voice.',
            value: settings.soundsEnabled,
            onChanged: controller.setSoundsEnabled,
          ),
          _SliderRow(
            label: 'Sound Volume',
            value: settings.sfxVolume,
            onChanged: settings.soundsEnabled ? controller.setSfxVolume : null,
          ),
          for (final (name, label) in SoundManager.userSounds)
            if (kNotificationSoundNames.contains(name))
              SettingsSoundRow(name: name, label: label),
        ],
      ),
    ]);
  }
}

/// A labelled slider row (label above, 0–1 slider under it).
class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    this.description,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.valueLabel,
    this.sliderKey,
  });

  final String label;
  final String? description;
  final double value;
  final double min;
  final double max;
  final String? valueLabel;
  final Key? sliderKey;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: SettingsText.label(colors))),
            if (valueLabel != null)
              Text(valueLabel!, style: SettingsText.description(colors)),
          ],
        ),
        if (description != null) ...[
          const SizedBox(height: 4),
          Text(description!, style: SettingsText.description(colors)),
        ],
        const SizedBox(height: 16),
        AccordSlider(
          key: sliderKey,
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
          semanticLabel: label,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Appearance
// ---------------------------------------------------------------------------

class _AppearancePage extends ConsumerWidget {
  const _AppearancePage({required this.onOpenPage});

  final ValueChanged<SettingsPage> onOpenPage;

  static const _hand = EmojiEntry(
    '✋',
    'raised_hand',
    EmojiCategory.people,
    '',
    ['✋🏻', '✋🏼', '✋🏽', '✋🏾', '✋🏿'],
  );
  static const _toneLabels = [
    'None',
    'Light',
    'Medium-light',
    'Medium',
    'Medium-dark',
    'Dark',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    return _Sections([
      _Section(
        id: 'theme',
        title: 'Theme',
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Default Themes', style: SettingsText.label(colors)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in AppThemePreset.values)
                    _ThemeTile(
                      preset: preset,
                      selected: settings.themePreset == preset,
                      onTap: () => controller.setThemePreset(preset),
                    ),
                ],
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Accent Colour', style: SettingsText.label(colors)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  ColorSwatchChip(
                    color: defaultAccentFor(settings.themePreset),
                    selected: settings.accentColor == null,
                    label: 'Default',
                    onTap: () => controller.setAccentColor(null),
                  ),
                  for (final (argb, name) in avatarColorPalette)
                    ColorSwatchChip(
                      color: Color(argb),
                      selected: settings.accentColor == argb,
                      label: name,
                      onTap: () => controller.setAccentColor(argb),
                    ),
                ],
              ),
            ],
          ),
          SettingsLinkCard(
            icon: AppIcons.accessibilityNewOutlined,
            title: 'Accessibility',
            description:
                'Change saturation of colours, reduce motion and adjust the '
                'zoom level',
            onTap: () => onOpenPage(SettingsPage.accessibility),
          ),
        ],
      ),
      _Section(
        id: 'messages',
        title: 'Messages',
        children: [
          SettingsSwitchRow(
            key: const Key('settings-show-embeds'),
            label: 'Show embeds and link previews',
            value: settings.showEmbeds,
            onChanged: controller.setShowEmbeds,
          ),
        ],
      ),
      _Section(
        id: 'chat-box',
        title: 'Chat Box',
        children: [
          SettingsSwitchRow(
            key: const Key('settings-convert-emoticons'),
            label: 'Automatically convert emoticons in your messages to emojis',
            description:
                'For example, when you type :) Daccord will convert it to 🙂',
            value: settings.convertEmoticons,
            onChanged: controller.setConvertEmoticons,
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Default emoji skin tone',
                style: SettingsText.label(colors),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (var t = 0; t <= 5; t++)
                    Tooltip(
                      message: _toneLabels[t],
                      child: InkWell(
                        key: Key('settings-skin-tone-$t'),
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => controller.setEmojiSkinTone(t),
                        child: Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: settings.emojiSkinTone == t
                                ? colors.primary.withValues(alpha: 0.25)
                                : Colors.black.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: settings.emojiSkinTone == t
                                  ? colors.primary
                                  : const Color(0x339696A0),
                            ),
                          ),
                          child: Text(
                            _hand.withTone(t),
                            style: const TextStyle(fontSize: 22),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
      _Section(
        id: 'streamer-mode',
        title: 'Streamer Mode',
        children: [
          SettingsSwitchRow(
            key: const Key('settings-streamer-mode'),
            label: 'Enable Streamer Mode',
            description:
                'Streamer Mode hides your notes and invite codes and silences '
                'notifications while you stream or share your screen.',
            value: settings.streamerMode,
            onChanged: controller.setStreamerMode,
          ),
        ],
      ),
    ]);
  }
}

/// A 48 px square showing a preset's surfaces; the selected one has an
/// accent ring and a check badge.
class _ThemeTile extends StatelessWidget {
  const _ThemeTile({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final AppThemePreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final palette = paletteFor(preset);
    return Tooltip(
      message: preset.label,
      child: InkWell(
        key: Key('settings-theme-${preset.name}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox.square(
          dimension: 52,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: palette.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selected
                          ? colors.primary
                          : const Color(0x339696A0),
                      width: selected ? 2 : 1,
                    ),
                  ),
                ),
              ),
              if (selected)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: colors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      AppIcons.check,
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Accessibility
// ---------------------------------------------------------------------------

class _AccessibilityPage extends ConsumerWidget {
  const _AccessibilityPage({required this.onOpenPage});

  final ValueChanged<SettingsPage> onOpenPage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    return _Sections([
      _Section(
        id: 'text-readability',
        title: 'Text Readability',
        children: [
          _SliderRow(
            label: 'Zoom Level',
            description: 'Adjust the size of the whole app.',
            valueLabel: '${(settings.uiScale * 100).round()}%',
            value: settings.uiScale,
            min: AccordSettings.minUiScale,
            max: AccordSettings.maxUiScale,
            onChanged: (v) =>
                controller.setUiScale((v * 10).roundToDouble() / 10),
          ),
        ],
      ),
      _Section(
        id: 'visual-density',
        title: 'Visual Density',
        gap: 8,
        children: [
          const _FieldHeading(
            'Chat Message Display',
            'Change the appearance of chat messages.',
          ),
          AccordRadioRow(
            key: const Key('settings-display-default'),
            label: 'Default',
            selected: !settings.compactMode,
            onTap: () => controller.setCompactMode(false),
          ),
          AccordRadioRow(
            key: const Key('settings-display-compact'),
            label: 'Compact',
            selected: settings.compactMode,
            onTap: () => controller.setCompactMode(true),
          ),
        ],
      ),
      _Section(
        id: 'colour-contrast',
        title: 'Colour & Contrast',
        children: [
          _SliderRow(
            sliderKey: const Key('settings-saturation'),
            label: 'Saturation',
            description:
                'Reduce the saturation of colours within the app, for those '
                'with colour sensitivities. This does not affect the '
                'saturation of images, videos, role colours or other user '
                'content.',
            valueLabel: '${(settings.uiSaturation * 100).round()}%',
            value: settings.uiSaturation,
            onChanged: (v) =>
                controller.setUiSaturation((v * 10).roundToDouble() / 10),
          ),
          SettingsLinkCard(
            icon: AppIcons.paletteOutlined,
            title: 'Appearance',
            description: 'Change your app theme',
            onTap: () => onOpenPage(SettingsPage.appearance),
          ),
        ],
      ),
      _Section(
        id: 'reduced-motion',
        title: 'Reduced Motion',
        children: [
          SettingsSwitchRow(
            key: const Key('settings-reduced-motion'),
            label: 'Enable Reduced Motion',
            description:
                'Reduce the amount and intensity of animations, hover effects '
                'and other moving effects.',
            value: settings.reducedMotion,
            onChanged: controller.setReducedMotion,
          ),
        ],
      ),
    ]);
  }
}

/// A 16/500 heading with its description, above a group of controls.
class _FieldHeading extends StatelessWidget {
  const _FieldHeading(this.label, [this.description]);

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

// ---------------------------------------------------------------------------
// System
// ---------------------------------------------------------------------------

class _SystemPage extends ConsumerWidget {
  const _SystemPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    final subs = {for (final s in visibleSubs(SettingsPage.system)) s.id: s};
    return _Sections([
      const SettingsAnchor(id: 'keybinds', child: KeybindsSection()),
      if (subs['desktop'] case final desktop?)
        _Section(
          id: 'desktop',
          title: desktop.label,
          children: [
            SettingsSwitchRow(
              key: const Key('settings-close-to-tray'),
              label: 'Minimise to Tray',
              description:
                  'Hitting X will make Daccord minimise to the system tray '
                  'instead of closing.',
              value: settings.closeToTray,
              onChanged: controller.setCloseToTray,
            ),
          ],
        ),
      if (subs.containsKey('updates'))
        _Section(
          id: 'updates',
          title: 'Updates',
          children: [
            _EditRow(
              label: 'Current Version',
              value: 'v$kAppVersion',
              buttonLabel: 'Check for Updates',
              onEdit: () => showUpdatesSettings(context),
            ),
          ],
        ),
      const _Section(
        id: 'backup',
        title: 'Backup',
        children: [SettingsBackupSection()],
      ),
      const _Section(
        id: 'system-advanced',
        title: 'Advanced',
        children: [_MasterServerField(), OnboardingHelpSection()],
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Developer
// ---------------------------------------------------------------------------

class _DeveloperPage extends ConsumerWidget {
  const _DeveloperPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    return _Section(
      id: 'developer',
      title: 'Developer',
      children: [
        SettingsSwitchRow(
          key: const Key('settings-developer-mode'),
          label: 'Developer Mode',
          description: 'Unlock the local Client MCP server for AI agents.',
          value: settings.developerMode,
          onChanged: controller.setDeveloperMode,
        ),
        if (settings.developerMode)
          _ChevronRow(
            label: 'Client MCP Server',
            value: 'Token, port, tools',
            onTap: () => showDeveloperSettings(context),
          ),
      ],
    );
  }
}
