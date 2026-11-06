import 'package:bonfire/theme/app_icons.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'dart:typed_data';
import 'package:bonfire/shared/utils/rest_result_ext.dart';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/shared/components/async_state_views.dart';
import 'package:bonfire/shared/components/color_swatch_chip.dart';
import 'package:bonfire/shared/components/image_crop_dialog.dart';
import 'package:bonfire/shared/components/ticker_aware_circle_avatar.dart';
import 'package:bonfire/shared/components/context_menu.dart';
import 'package:bonfire/shared/components/unsaved_changes_bar.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bonfire/features/member/views/profile_extras.dart'
    show profileColor, profileThemePalette;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the reference client's Edit Profile modal: the editing panel at the
/// left (profile switcher, avatar, avatar background, profile theme) and the
/// profile card at the right, whose display name, pronouns and bio are edited
/// in place. Changes wait for the "Don't forget to save your changes!" bar.
/// Calls `users.updateMe` and updates the global user cache so the change is
/// visible everywhere the current user is rendered.
///
/// [serverKey] targets a specific server connection's account — its own
/// display name / bio / avatar on that instance (a *per-server* profile). When
/// null the active connection is used.
Future<void> showAccordProfileEdit(BuildContext context, {String? serverKey}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: const Color(0xB8000000),
    transitionDuration: const Duration(milliseconds: 150),
    transitionBuilder: (_, animation, _, child) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween(begin: 0.96, end: 1.0).animate(animation),
        child: child,
      ),
    ),
    pageBuilder: (_, _, _) => _ProfileEdit(serverKey: serverKey),
  );
}

class _ProfileEdit extends ConsumerStatefulWidget {
  const _ProfileEdit({this.serverKey});


  /// The server connection to edit, or null for the active connection.
  final String? serverKey;

  @override
  ConsumerState<_ProfileEdit> createState() => _ProfileEditState();
}

class _ProfileEditState extends ConsumerState<_ProfileEdit> {
  final _displayName = TextEditingController();
  final _bio = TextEditingController();
  final _pronouns = TextEditingController();
  final UnsavedChangesController _unsaved = UnsavedChangesController();

  /// The values as loaded (or last saved), for Reset and the dirty check.
  ({
    String name,
    String bio,
    String pronouns,
    int? primary,
    int? accent,
    int? accentColor,
  })?
  _initial;

  /// Profile theme colours (`0xRRGGBB`), null when unset.
  int? _themePrimary;
  int? _themeAccent;
  bool _extrasLoaded = false;
  bool _busy = false;
  bool _loaded = false;
  String? _error;

  /// Bytes of a freshly-picked avatar awaiting save. When non-null, save uses
  /// it as a data URI; otherwise the current server-side avatar is unchanged.
  Uint8List? _newAvatarBytes;

  /// The chosen imageless-avatar background color (stored as the user's
  /// `accent_color`). `null` means "transparent" — the avatar falls back to the
  /// deterministic [accordAvatarColor] derived from the user ID.
  int? _accentColor;

  /// The profile loaded from the targeted server (drives the avatar preview).
  AccordUser? _loadedUser;

  /// The targeted connection (the named server, or the active one).
  AccordConnection? get _conn {
    final connections = ref.read(connectionsControllerProvider);
    return connections.connectionFor(widget.serverKey ?? connections.activeKey);
  }

  /// Whether the edited connection is the active one (gates cache propagation,
  /// which is keyed to the active server's user/member caches).
  bool get _isActiveServer {
    final activeKey = ref.read(connectionsControllerProvider).activeKey;
    return widget.serverKey == null || widget.serverKey == activeKey;
  }

  AccordClient? get _client => widget.serverKey == null
      ? ref.accordClient
      : ref.read(accordAuthProvider.notifier).clientForKey(widget.serverKey!);

  @override
  void initState() {
    super.initState();
    for (final c in [_displayName, _bio, _pronouns]) {
      c.addListener(_changed);
    }
    _loadInitial();
  }

  @override
  void dispose() {
    _displayName.dispose();
    _bio.dispose();
    _pronouns.dispose();
    _unsaved.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _snapshot() => _initial = (
    name: _displayName.text,
    bio: _bio.text,
    pronouns: _pronouns.text,
    primary: _themePrimary,
    accent: _themeAccent,
    accentColor: _accentColor,
  );

  bool get _dirty {
    final i = _initial;
    if (i == null) return false;
    return _newAvatarBytes != null ||
        _displayName.text != i.name ||
        _bio.text != i.bio ||
        _pronouns.text != i.pronouns ||
        _themePrimary != i.primary ||
        _themeAccent != i.accent ||
        _accentColor != i.accentColor;
  }

  void _reset() {
    final i = _initial;
    if (i == null) return;
    setState(() {
      _displayName.text = i.name;
      _bio.text = i.bio;
      _pronouns.text = i.pronouns;
      _themePrimary = i.primary;
      _themeAccent = i.accent;
      _accentColor = i.accentColor;
      _newAvatarBytes = null;
    });
  }

  /// Pulls the current profile via `users.getMe` (the cached session only
  /// carries name+avatar, not bio). Falls back to whatever the cache holds.
  Future<void> _loadInitial() async {
    final client = _client;
    if (client == null) return;
    final session = _conn?.session;
    if (session != null) {
      _displayName.text = session.username;
    }
    final result = await client.users.getMe();
    final extras = await client.profiles.get('@me');
    if (!mounted) return;
    final mine = extras.data;
    if (extras.ok && mine is AccordProfileExtras) {
      _pronouns.text = mine.pronouns ?? '';
      _themePrimary = mine.themePrimary;
      _themeAccent = mine.themeAccent;
      _extrasLoaded = true;
    }
    final data = result.data;
    if (result.ok && data is AccordUser) {
      _displayName.text = data.displayName ?? data.username;
      _bio.text = data.bio ?? '';
      final accent = data.accentColor;
      if (accent is int && accent > 0) {
        _accentColor = 0xFF000000 | (accent & 0xFFFFFF);
      }
      _loadedUser = data;
      // Only seed the shared user cache when editing the active server (the
      // cache belongs to it); a background server's user shouldn't leak in.
      if (_isActiveServer) {
        ref
            .read(
              accordUsersControllerProvider(
                ref.readActiveServerKey() ?? '',
              ).notifier,
            )
            .upsert(data);
      }
    }
    _snapshot();
    setState(() => _loaded = true);
  }

  Future<void> _pickAvatar() async {
    final cropped = await pickAndCropImage(
      context,
      aspectRatio: 1,
      circular: true,
      title: 'Crop avatar',
    );
    if (cropped == null || !mounted) return;
    setState(() {
      _newAvatarBytes = cropped;
      // An uploaded image hides the colored fallback, so reset the picker to
      // transparent — the chosen color only applies to imageless avatars.
      _accentColor = null;
    });
  }

  Future<void> _save() async {
    final client = _client;
    if (client == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final body = <String, dynamic>{
      'display_name': _displayName.text.trim(),
      'bio': _bio.text.trim(),
      // null clears the accent server-side, falling back to the auto color.
      'accent_color': _accentColor == null ? null : (_accentColor! & 0xFFFFFF),
    };
    final avatarBytes = _newAvatarBytes;
    if (avatarBytes != null) {
      body['avatar'] = AccordCDN.buildDataUri(avatarBytes, 'avatar.png');
    }
    final result = await client.users.updateMe(body);
    if (!mounted) return;
    if (result.ok && _extrasLoaded) {
      final extras = await client.profiles.updateMine({
        'pronouns': _pronouns.text.trim(),
        'theme_primary': _themePrimary,
        'theme_accent': _themeAccent,
      });
      if (!mounted) return;
      if (!extras.ok) {
        setState(() {
          _busy = false;
          _error = extras.errorOr('Failed to save pronouns and theme');
        });
        return;
      }
    }
    setState(() => _busy = false);
    if (!result.ok) {
      setState(() => _error = result.errorOr('Failed to save profile'));
      return;
    }
    final updated = result.data;
    // Only propagate to the shared user/member caches when editing the active
    // server — those caches belong to it. A per-server edit of a background
    // connection just persists server-side and takes effect when it's active.
    if (updated is AccordUser && _isActiveServer) {
      ref
          .read(
            accordUsersControllerProvider(
              ref.readActiveServerKey() ?? '',
            ).notifier,
          )
          .upsert(updated);
      // The member caches hold their own AccordUser per member; propagate the
      // change so message authors and the roster update, not just surfaces that
      // read the global user cache.
      for (final key in activeMemberSpaces) {
        if (key.serverKey != ref.readActiveServerKey()) continue;
        ref
            .read(
              accordMembersControllerProvider(
                key.serverKey,
                key.spaceId,
              ).notifier,
            )
            .applyUserUpdate(updated);
      }
    }
    // The reference client keeps the editor open: the bar goes away.
    if (mounted) {
      setState(() {
        _newAvatarBytes = null;
        _snapshot();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    // Rebuild on connection changes so the resolved session stays current.
    final connections = ref.watch(connectionsControllerProvider);
    final session = _conn?.session;
    // Prefer the profile loaded from the targeted server; fall back to the
    // active user cache when editing the active server.
    final me =
        _loadedUser ??
        (_isActiveServer && session != null
            ? ref.watch(
                accordUsersControllerProvider(
                  ref.readActiveServerKey() ?? '',
                ).select((m) => m[session.userId]),
              )
            : null);
    final avatarUrl = me == null
        ? null
        : accordAvatarUrl(me, session?.server.cdnUrl);
    final previewBg = _accentColor != null
        ? Color(_accentColor!)
        : accordIdColor(session?.userId ?? '');
    final dirty = _dirty;
    if (dirty != _unsaved.dirty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _unsaved.dirty = _dirty;
      });
    }
    final size = MediaQuery.sizeOf(context);
    final width = (size.width - 80).clamp(0.0, 1202.0);
    final height = (size.height - 96).clamp(0.0, size.height - 16);
    final ImageProvider? avatar = _newAvatarBytes != null
        ? MemoryImage(_newAvatarBytes!)
        : (avatarUrl != null ? CachedNetworkImageProvider(avatarUrl) : null);
    final profileLabel = widget.serverKey == null
        ? 'Main Profile'
        : (session?.server.name ?? session?.server.baseUrl ?? 'Profile');

    final panel = _EditPanel(
      profileLabel: profileLabel,
      connections: connections.hasMultiple ? connections.connections : const [],
      onPickProfile: (key) {
        if (!_unsaved.attemptLeave()) return;
        Navigator.of(context).pop();
        showAccordProfileEdit(context, serverKey: key);
      },
      avatar: avatar,
      initial: accordInitial(session?.username),
      previewBg: previewBg,
      busy: _busy,
      onPickAvatar: _pickAvatar,
      accentColor: _accentColor,
      userId: session?.userId ?? '',
      onAccentColor: (c) => setState(() => _accentColor = c),
      extrasLoaded: _extrasLoaded,
      themePrimary: _themePrimary,
      themeAccent: _themeAccent,
      onThemePrimary: (c) => setState(() => _themePrimary = c),
      onThemeAccent: (c) => setState(() => _themeAccent = c),
    );

    final card = _ProfileCard(
      displayName: _displayName,
      bio: _bio,
      pronouns: _extrasLoaded ? _pronouns : null,
      username: session?.username ?? '',
      avatar: avatar,
      initial: accordInitial(session?.username),
      previewBg: previewBg,
      banner: _themePrimary != null
          ? profileColor(_themePrimary!)
          : const Color(0xFFDCDFE4),
      busy: _busy,
      onPickAvatar: _pickAvatar,
    );

    return UnsavedChangesPopGuard(
      controller: _unsaved,
      child: Center(
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            key: const Key('profile-edit-modal'),
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: colors.foreground,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x3D000000),
                  blurRadius: 24,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: !_loaded
                ? const Center(child: LoadingView())
                : Stack(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(width: 241, child: panel),
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: colors.background,
                                borderRadius: const BorderRadius.horizontal(
                                  right: Radius.circular(16),
                                ),
                                border: Border.all(
                                  color: const Color(0x339696A0),
                                ),
                              ),
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(
                                  48,
                                  48,
                                  48,
                                  120,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(width: 400, child: card),
                                    if (_error != null) ...[
                                      const SizedBox(height: 12),
                                      InlineError(_error!, centered: false),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Tooltip(
                          message: 'Close',
                          child: InkWell(
                            key: const Key('profile-edit-close'),
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => Navigator.of(context).maybePop(),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: colors.raised,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: colors.hairline),
                              ),
                              child: Icon(
                                AppIcons.close,
                                size: 16,
                                color: colors.dirtyWhite,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 24,
                        child: Center(
                          child: ListenableBuilder(
                            listenable: _unsaved,
                            builder: (context, _) => UnsavedChangesBar(
                              style: UnsavedChangesBarStyle.profile,
                              visible: dirty,
                              warning: _unsaved.warning,
                              shakes: _unsaved.shakes,
                              saving: _busy,
                              onReset: _reset,
                              onSave: _save,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// The modal's left panel: "Main Profile ▾" (or the per-server profile being
/// edited) and the sections the right-hand card can't edit in place.
class _EditPanel extends StatelessWidget {
  const _EditPanel({
    required this.profileLabel,
    required this.connections,
    required this.onPickProfile,
    required this.avatar,
    required this.initial,
    required this.previewBg,
    required this.busy,
    required this.onPickAvatar,
    required this.accentColor,
    required this.userId,
    required this.onAccentColor,
    required this.extrasLoaded,
    required this.themePrimary,
    required this.themeAccent,
    required this.onThemePrimary,
    required this.onThemeAccent,
  });

  final String profileLabel;
  final List<AccordConnection> connections;
  final ValueChanged<String?> onPickProfile;
  final ImageProvider? avatar;
  final String initial;
  final Color previewBg;
  final bool busy;
  final VoidCallback onPickAvatar;
  final int? accentColor;
  final String userId;
  final ValueChanged<int?> onAccentColor;
  final bool extrasLoaded;
  final int? themePrimary;
  final int? themeAccent;
  final ValueChanged<int?> onThemePrimary;
  final ValueChanged<int?> onThemeAccent;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final heading = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      height: 18 / 14,
      color: colors.dirtyWhite,
    );
    Widget section(String title, Widget child) => Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: heading),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        SizedBox(
          height: 64,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Builder(
              builder: (context) => InkWell(
                key: const Key('profile-edit-switch'),
                borderRadius: BorderRadius.circular(4),
                onTapUp: connections.isEmpty
                    ? null
                    : (d) => showAccordContextMenu(
                        context,
                        globalPosition: d.globalPosition,
                        entries: [
                          AccordMenuEntry(
                            label: 'Main Profile',
                            onSelected: () => onPickProfile(null),
                          ),
                          const AccordMenuEntry.divider(),
                          for (final conn in connections)
                            AccordMenuEntry(
                              label:
                                  conn.session.server.name ??
                                  conn.session.server.baseUrl,
                              subtitle: conn.session.username,
                              onSelected: () => onPickProfile(conn.key),
                            ),
                        ],
                      ),
                onTap: connections.isEmpty ? null : () {},
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        profileLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: colors.dirtyWhite,
                        ),
                      ),
                    ),
                    if (connections.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Icon(
                        AppIcons.expandMore,
                        size: 16,
                        color: colors.dirtyWhite,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        section(
          'Avatar',
          InkWell(
            key: const Key('profile-edit-avatar'),
            borderRadius: BorderRadius.circular(8),
            onTap: busy ? null : onPickAvatar,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: const Color(0xFF94949C).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: TickerAwareCircleAvatar(
                radius: 36,
                backgroundColor: previewBg,
                foregroundImage: avatar,
                child: avatar == null
                    ? Text(
                        initial,
                        style: TextStyle(
                          fontSize: 24,
                          color: accordOnColor(previewBg),
                        ),
                      )
                    : null,
              ),
            ),
          ),
        ),
        section(
          'Avatar Background',
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ColorSwatchChip(
                color: accordIdColor(userId),
                selected: accentColor == null,
                transparent: true,
                label: 'Transparent (auto)',
                onTap: busy ? null : () => onAccentColor(null),
              ),
              for (final (argb, _) in avatarColorPalette)
                ColorSwatchChip(
                  color: Color(argb),
                  selected: accentColor == argb,
                  label: null,
                  onTap: busy ? null : () => onAccentColor(argb),
                ),
            ],
          ),
        ),
        if (extrasLoaded)
          section(
            'Profile Theme',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ThemeColorRow(
                  label: 'Primary',
                  value: themePrimary,
                  onChanged: onThemePrimary,
                ),
                _ThemeColorRow(
                  label: 'Accent',
                  value: themeAccent,
                  onChanged: onThemeAccent,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The profile card at the right: banner, avatar, then the display name,
/// pronouns and bio, each edited in place like the reference client's card.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.displayName,
    required this.bio,
    required this.pronouns,
    required this.username,
    required this.avatar,
    required this.initial,
    required this.previewBg,
    required this.banner,
    required this.busy,
    required this.onPickAvatar,
  });

  final TextEditingController displayName;
  final TextEditingController bio;
  final TextEditingController? pronouns;
  final String username;
  final ImageProvider? avatar;
  final String initial;
  final Color previewBg;
  final Color banner;
  final bool busy;
  final VoidCallback onPickAvatar;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final muted = TextStyle(fontSize: 14, height: 18 / 14, color: colors.dirtyWhite);
    return Container(
      decoration: BoxDecoration(
        color: colors.raised,
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(height: 140, color: banner),
              Positioned(
                left: 20,
                top: 72,
                child: GestureDetector(
                  onTap: busy ? null : onPickAvatar,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: colors.raised,
                      shape: BoxShape.circle,
                    ),
                    child: TickerAwareCircleAvatar(
                      radius: 54,
                      backgroundColor: previewBg,
                      foregroundImage: avatar,
                      child: avatar == null
                          ? Text(
                              initial,
                              style: TextStyle(
                                fontSize: 36,
                                color: accordOnColor(previewBg),
                              ),
                            )
                          : null,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 82, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InlineField(
                  key: const Key('profile-display-name'),
                  controller: displayName,
                  enabled: !busy,
                  hint: username,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    height: 32 / 24,
                    color: colors.dirtyWhite,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(username, style: muted),
                    if (pronouns != null) ...[
                      Text('  •  ', style: muted),
                      Expanded(
                        child: _InlineField(
                          key: const Key('profile-pronouns'),
                          controller: pronouns!,
                          enabled: !busy,
                          hint: 'Add pronouns',
                          maxLength: 40,
                          style: muted,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  'Bio',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 16 / 12,
                    color: colors.dirtyWhite,
                  ),
                ),
                const SizedBox(height: 4),
                _InlineField(
                  key: const Key('profile-bio'),
                  controller: bio,
                  enabled: !busy,
                  hint: 'Describe yourself',
                  maxLines: 6,
                  style: muted,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Text edited in place: plain until hovered or focused, then the settings
/// field's well and an accent outline while focused.
class _InlineField extends StatefulWidget {
  const _InlineField({
    super.key,
    required this.controller,
    required this.enabled,
    required this.hint,
    required this.style,
    this.maxLines = 1,
    this.maxLength,
  });

  final TextEditingController controller;
  final bool enabled;
  final String hint;
  final TextStyle style;
  final int maxLines;
  final int? maxLength;

  @override
  State<_InlineField> createState() => _InlineFieldState();
}

class _InlineFieldState extends State<_InlineField> {
  final FocusNode _focus = FocusNode();
  bool _hover = false;

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
    final colors = BonfireThemeExtension.of(context);
    final active = _focus.hasFocus || _hover;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: active ? Colors.black.withValues(alpha: 0.12) : null,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _focus.hasFocus ? colors.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: TextField(
          controller: widget.controller,
          focusNode: _focus,
          enabled: widget.enabled,
          minLines: 1,
          maxLines: widget.maxLines,
          maxLength: widget.maxLength,
          cursorColor: colors.dirtyWhite,
          style: widget.style,
          decoration: InputDecoration(
            isCollapsed: true,
            border: InputBorder.none,
            counterText: '',
            hintText: widget.hint,
            hintStyle: widget.style.copyWith(
              color: colors.gray,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

/// A row of profile theme colour swatches, plus "none".
class _ThemeColorRow extends StatelessWidget {
  const _ThemeColorRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall!.copyWith(color: colors.dirtyWhite),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              InkWell(
                onTap: () => onChanged(null),
                customBorder: const CircleBorder(),
                child: CircleAvatar(
                  radius: 13,
                  backgroundColor: colors.darkGray,
                  child: Icon(
                    value == null ? AppIcons.check : AppIcons.block,
                    size: 14,
                    color: colors.gray,
                  ),
                ),
              ),
              for (final color in profileThemePalette)
                InkWell(
                  onTap: () => onChanged(color),
                  customBorder: const CircleBorder(),
                  child: CircleAvatar(
                    radius: 13,
                    backgroundColor: profileColor(color),
                    child: value == color
                        ? const Icon(AppIcons.check, size: 14, color: Colors.white)
                        : null,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
