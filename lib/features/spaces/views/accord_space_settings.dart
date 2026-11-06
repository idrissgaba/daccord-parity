import 'dart:typed_data';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/automod/views/automod_panel.dart';
import 'package:bonfire/features/channels/controllers/accord_channels.dart';
import 'package:bonfire/features/events/controllers/presence.dart';
import 'package:bonfire/features/experiences/views/arcade.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/member/utils/permissions.dart';
import 'package:bonfire/features/member/views/accord_member_avatar.dart';
import 'package:bonfire/features/member/views/user_context_menu.dart';
import 'package:bonfire/features/messaging/views/stickers.dart';
import 'package:bonfire/features/soundboard/views/soundboard_settings_page.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/features/spaces/utils/space_display.dart';
import 'package:bonfire/features/spaces/utils/space_media_cache.dart';
import 'package:bonfire/features/spaces/views/accord_audit_log.dart';
import 'package:bonfire/features/spaces/views/accord_ban_list.dart';
import 'package:bonfire/features/spaces/views/accord_emoji_management.dart';
import 'package:bonfire/features/spaces/views/accord_invites.dart';
import 'package:bonfire/features/spaces/views/accord_reports.dart';
import 'package:bonfire/features/spaces/views/accord_role_management.dart';
import 'package:bonfire/features/spaces/views/accord_space_settings_media.dart';
import 'package:bonfire/features/spaces/views/accord_transfer_ownership.dart';
import 'package:bonfire/features/spaces/views/accord_webhooks.dart';
import 'package:bonfire/features/spaces/views/space_settings_frame.dart';
import 'package:bonfire/features/spaces/views/welcome_screen.dart';
import 'package:bonfire/shared/components/accord_dialog.dart';
import 'package:bonfire/shared/components/image_crop_dialog.dart';
import 'package:bonfire/shared/components/settings_controls.dart';
import 'package:bonfire/shared/components/unsaved_changes_bar.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/theme/app_icons.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'accord_space_settings_form.dart';
part 'accord_space_settings_management.dart';

/// The pages of the server settings, in the reference client's sidebar
/// order. Server Tag, Boost Perks, App Directory, Safety Setup, Enable
/// Community and Server Template have no Accord counterpart (§4); Arcade,
/// Reports and Transfer Ownership are Accord's own.
abstract final class SpaceSettingsPages {
  static const profile = 'profile';
  static const engagement = 'engagement';
  static const emoji = 'emoji';
  static const stickers = 'stickers';
  static const soundboard = 'soundboard';
  static const members = 'members';
  static const roles = 'roles';
  static const invites = 'invites';
  static const access = 'access';
  static const integrations = 'integrations';
  static const arcade = 'arcade';
  static const auditLog = 'audit-log';
  static const bans = 'bans';
  static const automod = 'automod';
  static const reports = 'reports';
  static const transfer = 'transfer';
  static const delete = 'delete';
}

/// Opens the full-screen server settings of [spaceId] on [page] (one of
/// [SpaceSettingsPages], else the first page the user may open). With
/// [openSoundUpload] the Soundboard page opens its "Upload a Sound" dialog.
Future<void> showAccordSpaceSettings(
  BuildContext context, {
  required String spaceId,
  String? page,
  String? serverKey,
  bool openSoundUpload = false,
}) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      settings: const RouteSettings(name: 'space-settings'),
      transitionDuration: const Duration(milliseconds: 150),
      reverseTransitionDuration: const Duration(milliseconds: 100),
      pageBuilder: (_, _, _) => SpaceSettingsScreen(
        spaceId: spaceId,
        initialPage: page,
        serverKey: serverKey,
        openSoundUpload: openSoundUpload,
      ),
      transitionsBuilder: (_, animation, _, child) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween(begin: 1.04, end: 1.0).animate(animation),
          child: child,
        ),
      ),
    ),
  );
}

/// Space-level option presets. The right-hand value is the wire string sent
/// to `spaces.update`.
const _verificationLevels = <({String label, String value})>[
  (label: 'None', value: 'none'),
  (label: 'Low', value: 'low'),
  (label: 'Medium', value: 'medium'),
  (label: 'High', value: 'high'),
];
const _contentFilters = <({String label, String value})>[
  (label: 'Do not filter', value: 'disabled'),
  (label: 'Filter messages from members without roles', value: 'no_role'),
  (label: 'Filter messages from all members', value: 'everyone'),
];

/// The reference client's Server Settings: [SpaceSettingsFrame] with every
/// page the user's permissions allow. Server Profile, Engagement and Access
/// share one draft saved through the unsaved-changes bar; leaving a page (or
/// the settings) with pending edits only warns, as there.
class SpaceSettingsScreen extends ConsumerStatefulWidget {
  const SpaceSettingsScreen({
    super.key,
    required this.spaceId,
    this.initialPage,
    this.serverKey,
    this.openSoundUpload = false,
  });

  final String spaceId;
  final String? initialPage;
  final String? serverKey;
  final bool openSoundUpload;

  @override
  ConsumerState<SpaceSettingsScreen> createState() =>
      _SpaceSettingsScreenState();
}

class _SpaceSettingsScreenState extends ConsumerState<SpaceSettingsScreen> {
  final UnsavedChangesController _unsaved = UnsavedChangesController();
  String? _page;
  bool _busy = false;
  String? _error;

  // The draft of Server Profile, Engagement and Access, seeded from the
  // space (see [_seed]) and flushed in one `spaces.update` on Save.
  final TextEditingController _name = TextEditingController();
  final TextEditingController _description = TextEditingController();
  String _verification = 'none';
  String _notifications = 'all';
  String _nsfw = 'default';
  String _contentFilter = 'disabled';
  bool _public = false;
  bool _guestAccess = true;
  String? _rulesChannelId;
  String? _systemChannelId;
  Uint8List? _pendingIconBytes;
  Uint8List? _pendingBannerBytes;
  bool _bannerRemoved = false;
  bool _iconRemoved = false;
  AccordSpace? _seededFrom;

  @override
  void initState() {
    super.initState();
    _name.addListener(_onDraftChanged);
    _description.addListener(_onDraftChanged);
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _unsaved.dispose();
    super.dispose();
  }

  String get _serverKey =>
      widget.serverKey ?? ref.readActiveServerKey() ?? '';

  AccordClient? get _client => ref.accordClient;

  AccordSpace? get _space => ref
      .read(spacesControllerProvider)
      ?.firstWhereOrNull((s) => s.id == widget.spaceId);

  /// Seeds (or reseeds, after Reset or Save) the draft from [space].
  void _seed(AccordSpace space) {
    _seededFrom = space;
    _name.text = space.name;
    _description.text = space.description ?? '';
    _verification = space.verificationLevel;
    _notifications = space.defaultNotifications;
    _nsfw = space.nsfwLevel;
    _contentFilter = space.explicitContentFilter;
    _public = space.public;
    _guestAccess = space.allowGuestAccess;
    _rulesChannelId = space.rulesChannelId;
    _systemChannelId = space.systemChannelId;
    _pendingIconBytes = null;
    _pendingBannerBytes = null;
    _bannerRemoved = false;
    _iconRemoved = false;
  }

  bool get _dirty {
    final space = _seededFrom;
    if (space == null) return false;
    return _name.text != space.name ||
        _description.text != (space.description ?? '') ||
        _verification != space.verificationLevel ||
        _notifications != space.defaultNotifications ||
        _nsfw != space.nsfwLevel ||
        _contentFilter != space.explicitContentFilter ||
        _public != space.public ||
        _guestAccess != space.allowGuestAccess ||
        _rulesChannelId != space.rulesChannelId ||
        _systemChannelId != space.systemChannelId ||
        _pendingIconBytes != null ||
        _pendingBannerBytes != null ||
        _bannerRemoved ||
        _iconRemoved;
  }

  void _onDraftChanged() {
    if (mounted) setState(() {});
  }

  void _edit(VoidCallback change) => setState(change);

  void _reset() {
    final space = _space;
    if (space != null) setState(() => _seed(space));
  }

  /// The sidebar for what the user may open.
  List<SpaceSettingsGroup> _groups(Set<String> perms, bool isOwner) {
    bool has(String p) => accordHasPermission(perms, p);
    final manageSpace = has(AccordPermission.manageSpace);
    final expressions =
        has(AccordPermission.manageEmojis) ||
        has(AccordPermission.createExpressions);
    final sounds =
        has(AccordPermission.manageSoundboard) ||
        has(AccordPermission.createExpressions);
    SpaceSettingsGroup? group(String? title, List<SpaceSettingsItem?> items) {
      final visible = items.whereType<SpaceSettingsItem>().toList();
      return visible.isEmpty
          ? null
          : SpaceSettingsGroup(title: title, items: visible);
    }

    return [
      group(null, [
        if (manageSpace) ...const [
          SpaceSettingsItem(
            key: SpaceSettingsPages.profile,
            label: 'Server Profile',
          ),
          SpaceSettingsItem(
            key: SpaceSettingsPages.engagement,
            label: 'Engagement',
          ),
        ],
      ]),
      group('Expression', [
        if (expressions) ...const [
          SpaceSettingsItem(key: SpaceSettingsPages.emoji, label: 'Emoji'),
          SpaceSettingsItem(
            key: SpaceSettingsPages.stickers,
            label: 'Stickers',
          ),
        ],
        if (sounds)
          const SpaceSettingsItem(
            key: SpaceSettingsPages.soundboard,
            label: 'Soundboard',
          ),
      ]),
      group('People', [
        if (manageSpace ||
            has(AccordPermission.kickMembers) ||
            has(AccordPermission.banMembers) ||
            has(AccordPermission.manageRoles))
          const SpaceSettingsItem(
            key: SpaceSettingsPages.members,
            label: 'Members',
          ),
        if (has(AccordPermission.manageRoles))
          const SpaceSettingsItem(key: SpaceSettingsPages.roles, label: 'Roles'),
        if (manageSpace) ...const [
          SpaceSettingsItem(key: SpaceSettingsPages.invites, label: 'Invites'),
          SpaceSettingsItem(key: SpaceSettingsPages.access, label: 'Access'),
        ],
      ]),
      group('Apps', [
        if (has(AccordPermission.manageWebhooks))
          const SpaceSettingsItem(
            key: SpaceSettingsPages.integrations,
            label: 'Integrations',
          ),
        if (manageSpace)
          const SpaceSettingsItem(
            key: SpaceSettingsPages.arcade,
            label: 'Arcade',
          ),
      ]),
      group('Moderation', [
        if (has(AccordPermission.viewAuditLog))
          const SpaceSettingsItem(
            key: SpaceSettingsPages.auditLog,
            label: 'Audit Log',
          ),
        if (has(AccordPermission.banMembers)) ...const [
          SpaceSettingsItem(key: SpaceSettingsPages.bans, label: 'Bans'),
        ],
        if (manageSpace || has(AccordPermission.moderateMembers))
          const SpaceSettingsItem(
            key: SpaceSettingsPages.automod,
            label: 'AutoMod',
          ),
        if (has(AccordPermission.banMembers))
          const SpaceSettingsItem(
            key: SpaceSettingsPages.reports,
            label: 'Reports',
          ),
      ]),
      group(null, [
        if (isOwner) ...const [
          SpaceSettingsItem(
            key: SpaceSettingsPages.transfer,
            label: 'Transfer Ownership',
          ),
          SpaceSettingsItem(
            key: SpaceSettingsPages.delete,
            label: 'Delete Server',
            danger: true,
            trailingIcon: AppIcons.deleteOutline,
          ),
        ],
      ]),
    ].whereType<SpaceSettingsGroup>().toList();
  }

  void _select(String key, AccordSpace space) {
    // Dialog rows act in place; the page stays.
    if (key == SpaceSettingsPages.delete) {
      _deleteSpace(space.name);
      return;
    }
    if (key == SpaceSettingsPages.transfer) {
      showTransferOwnership(context, spaceId: widget.spaceId);
      return;
    }
    if (key == _page) return;
    if (!_unsaved.attemptLeave()) return;
    setState(() => _page = key);
  }

  Future<bool> _update(Map<String, dynamic> body, String failure) async {
    final client = _client;
    if (client == null || _busy) return false;
    final previous = _space;
    final cdnUrl = ref.readCdnUrl();
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await client.spaces.update(widget.spaceId, body);
    if (!mounted) return false;
    final space = result.data;
    if (result.ok && space is AccordSpace) {
      // A removal must also work with servers that omit cleared fields.
      if (body.containsKey('icon') && body['icon'] == null) space.icon = null;
      if (body.containsKey('banner') && body['banner'] == null) {
        space.banner = null;
      }
      await spaceMediaCache.invalidate(
        {
          if (body.containsKey('icon')) ...[
            if (previous != null)
              accordSpaceIconUrl(previous, cdnUrl, versioned: false),
            accordSpaceIconUrl(space, cdnUrl, versioned: false),
          ],
          if (body.containsKey('banner')) ...[
            if (previous != null)
              accordSpaceBannerUrl(previous, cdnUrl, versioned: false),
            accordSpaceBannerUrl(space, cdnUrl, versioned: false),
          ],
        }.whereType<String>(),
      );
      if (!mounted) return false;
      ref.read(spacesControllerProvider.notifier).upsertSpace(space);
      setState(() {
        _busy = false;
        _seed(space);
      });
      return true;
    }
    setState(() {
      _busy = false;
      _error = result.ok ? failure : result.errorOr(failure);
    });
    return false;
  }

  Future<void> _pickBanner() async {
    final cropped = await pickAndCropImage(
      context,
      aspectRatio: 16 / 9,
      title: 'Crop banner',
      maxOutputDimension: 1024,
    );
    if (cropped == null || !mounted) return;
    setState(() {
      _pendingBannerBytes = cropped;
      _bannerRemoved = false;
    });
  }

  Future<void> _pickIcon() async {
    final cropped = await pickAndCropImage(
      context,
      aspectRatio: 1,
      circular: true,
      title: 'Crop icon',
      maxOutputDimension: 512,
    );
    if (cropped == null || !mounted) return;
    setState(() {
      _pendingIconBytes = cropped;
      _iconRemoved = false;
    });
  }

  /// Flushes the draft in one `spaces.update`; images only when changed.
  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name is required');
      return;
    }
    final body = <String, dynamic>{
      'name': name,
      'description': _description.text.trim(),
      'verification_level': _verification,
      'default_notifications': _notifications,
      'nsfw_level': _nsfw,
      'explicit_content_filter': _contentFilter,
      'public': _public,
      'allow_guest_access': _guestAccess,
      'rules_channel_id': _rulesChannelId,
      'system_channel_id': _systemChannelId,
    };
    if (_pendingIconBytes != null) {
      body['icon'] = AccordCDN.buildDataUri(_pendingIconBytes!, 'icon.png');
    } else if (_iconRemoved) {
      body['icon'] = null;
    }
    if (_pendingBannerBytes != null) {
      body['banner'] = AccordCDN.buildDataUri(
        _pendingBannerBytes!,
        'banner.png',
      );
    } else if (_bannerRemoved) {
      body['banner'] = null;
    }
    await _update(body, 'Failed to save settings');
  }

  /// "Delete 'name'": the reference client's confirmation with the server
  /// name typed in. On success the settings close; the gateway
  /// `space.delete` event prunes the rail.
  Future<void> _deleteSpace(String spaceName) async {
    final client = _client;
    if (client == null) return;
    final typed = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final colors = BonfireThemeExtension.of(ctx);
          return AccordDialog(
            title: "Delete '$spaceName'",
            subtitle:
                'Are you sure you want to delete $spaceName? This action '
                'cannot be undone.',
            primaryLabel: 'Delete Server',
            tone: AccordDialogTone.danger,
            primaryEnabled: typed.text.trim() == spaceName.trim(),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SettingsFieldLabel('Enter server name'),
                _SettingsTextField(
                  key: const Key('delete-server-name'),
                  controller: typed,
                  autofocus: true,
                  onChanged: (_) => setLocal(() {}),
                  colors: colors,
                ),
              ],
            ),
          );
        },
      ),
    );
    typed.dispose();
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await client.spaces.delete(widget.spaceId);
    if (!mounted) return;
    if (!result.ok) {
      setState(() {
        _busy = false;
        _error = result.errorOr('Failed to delete space');
      });
      return;
    }
    ref.read(spacesControllerProvider.notifier).removeSpace(widget.spaceId);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final space = ref.watch(
      spacesControllerProvider.select(
        (s) => s?.firstWhereOrNull((sp) => sp.id == widget.spaceId),
      ),
    );
    if (space == null) {
      return const Material(child: SizedBox.expand());
    }
    if (_seededFrom == null) _seed(space);
    final perms = ref.watchAccordPermissions(space, widget.spaceId);
    final userId = ref.watchUserId();
    final isOwner = userId != null && space.ownerId == userId;
    final groups = _groups(perms, isOwner);
    final keys = [
      for (final g in groups)
        for (final i in g.items)
          if (i.key != SpaceSettingsPages.delete &&
              i.key != SpaceSettingsPages.transfer)
            i.key,
    ];
    final page = keys.contains(_page)
        ? _page!
        : keys.contains(widget.initialPage)
        ? widget.initialPage!
        : keys.firstOrNull ?? '';
    _page ??= page;
    final draftPage =
        page == SpaceSettingsPages.profile ||
        page == SpaceSettingsPages.engagement ||
        page == SpaceSettingsPages.access;
    // The shared draft reports here; other pages (a role being edited)
    // report through [UnsavedChangesHost] themselves.
    final dirty = _dirty;
    if (draftPage && dirty != _unsaved.dirty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _unsaved.dirty = _dirty;
      });
    }

    return UnsavedChangesPopGuard(
      controller: _unsaved,
      child: UnsavedChangesScope(
        controller: _unsaved,
        child: SpaceSettingsFrame(
          spaceName: space.name,
          groups: groups,
          selected: page,
          onSelect: (key) => _select(key, space),
          wide:
              page == SpaceSettingsPages.profile ||
              page == SpaceSettingsPages.members,
          scrollable: !_selfScrolling.contains(page),
          overlay: draftPage
              ? ListenableBuilder(
                  listenable: _unsaved,
                  builder: (context, _) => UnsavedChangesBar(
                    visible: dirty,
                    warning: _unsaved.warning,
                    shakes: _unsaved.shakes,
                    saving: _busy,
                    onReset: _reset,
                    onSave: _save,
                  ),
                )
              : null,
          child: KeyedSubtree(
            key: ValueKey('space-settings-page-$page'),
            child: _pageBody(page, space),
          ),
        ),
      ),
    );
  }

  /// Pages that lay out their own scrolling list under a fixed header.
  static const _selfScrolling = {
    SpaceSettingsPages.roles,
    SpaceSettingsPages.automod,
    SpaceSettingsPages.reports,
    SpaceSettingsPages.auditLog,
    SpaceSettingsPages.bans,
    SpaceSettingsPages.members,
  };

  Widget _pageBody(String page, AccordSpace space) {
    final error = _error;
    Widget withError(Widget child) => error == null
        ? child
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              child,
              const SizedBox(height: 16),
              Text(
                error,
                style: TextStyle(color: BonfireThemeExtension.of(context).red),
              ),
            ],
          );
    switch (page) {
      case SpaceSettingsPages.profile:
        return withError(
          _ServerProfilePage(
            space: space,
            name: _name,
            description: _description,
            pendingIconBytes: _pendingIconBytes,
            iconRemoved: _iconRemoved,
            pendingBannerBytes: _pendingBannerBytes,
            bannerRemoved: _bannerRemoved,
            busy: _busy,
            onPickIcon: _pickIcon,
            onRemoveIcon: () => _edit(() {
              _pendingIconBytes = null;
              _iconRemoved = true;
            }),
            onPickBanner: _pickBanner,
            onRemoveBanner: () => _edit(() {
              _pendingBannerBytes = null;
              _bannerRemoved = true;
            }),
          ),
        );
      case SpaceSettingsPages.engagement:
        return withError(
          _EngagementPage(
            spaceId: widget.spaceId,
            serverKey: _serverKey,
            systemChannelId: _systemChannelId,
            notifications: _notifications,
            onSystemChannel: (v) => _edit(() => _systemChannelId = v),
            onNotifications: (v) => _edit(() => _notifications = v),
          ),
        );
      case SpaceSettingsPages.access:
        return withError(
          _AccessPage(
            spaceId: widget.spaceId,
            serverKey: _serverKey,
            isPublic: _public,
            guestAccess: _guestAccess,
            verification: _verification,
            nsfw: _nsfw,
            contentFilter: _contentFilter,
            rulesChannelId: _rulesChannelId,
            onPublic: (v) => _edit(() => _public = v),
            onGuestAccess: (v) => _edit(() => _guestAccess = v),
            onVerification: (v) => _edit(() => _verification = v),
            onNsfw: (v) => _edit(() => _nsfw = v),
            onContentFilter: (v) => _edit(() => _contentFilter = v),
            onRulesChannel: (v) => _edit(() => _rulesChannelId = v),
          ),
        );
      case SpaceSettingsPages.emoji:
        return EmojiSettingsPage(spaceId: widget.spaceId);
      case SpaceSettingsPages.stickers:
        return StickerSettingsPage(spaceId: widget.spaceId);
      case SpaceSettingsPages.soundboard:
        return SoundboardSettingsView(
          serverKey: _serverKey,
          spaceId: widget.spaceId,
          openUpload: widget.openSoundUpload,
        );
      case SpaceSettingsPages.members:
        return _MembersPage(spaceId: widget.spaceId, serverKey: _serverKey);
      case SpaceSettingsPages.roles:
        return RolesSettingsPage(spaceId: widget.spaceId);
      case SpaceSettingsPages.invites:
        return InvitesSettingsPage(spaceId: widget.spaceId);
      case SpaceSettingsPages.integrations:
        return WebhooksSettingsPage(spaceId: widget.spaceId);
      case SpaceSettingsPages.arcade:
        return _ArcadePage(spaceId: widget.spaceId, serverKey: _serverKey);
      case SpaceSettingsPages.auditLog:
        return AuditLogSettingsPage(spaceId: widget.spaceId);
      case SpaceSettingsPages.bans:
        return BansSettingsPage(spaceId: widget.spaceId);
      case SpaceSettingsPages.automod:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SettingsPageHeader(
              title: 'AutoMod',
              description:
                  'Give your mods a break while keeping your server safe! '
                  'Set up rules for attachments and review what AutoMod held '
                  'back.',
              bottom: 24,
            ),
            Expanded(child: AutomodPanel(scope: widget.spaceId)),
          ],
        );
      case SpaceSettingsPages.reports:
        return ReportsSettingsPage(spaceId: widget.spaceId);
    }
    return const SizedBox.shrink();
  }
}
