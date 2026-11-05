import 'dart:math' as math;

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/events/controllers/presence.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/controllers/profile_extras.dart';
import 'package:bonfire/features/member/utils/member_actions.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/member/views/accord_member_avatar.dart';
import 'package:bonfire/features/member/views/profile_card.dart';
import 'package:bonfire/features/member/views/profile_extras.dart'
    show profileColor;
import 'package:bonfire/features/member/views/remote_origin_badge.dart';
import 'package:bonfire/features/member/views/user_context_menu.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/features/spaces/utils/space_display.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/features/user/views/accord_direct_messages.dart';
import 'package:bonfire/features/user/views/account_card.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/shared/utils/server_timestamp.dart';
import 'package:bonfire/theme/app_icons.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'full_profile/sections.dart';

/// The right column's tabs.
enum FullProfileTab { activity, mutualFriends, mutualServers }

/// Opens the full profile ("View Full Profile", "Profile" in a user menu):
/// the card at the left (banner, avatar, name, Message / add friend / "…",
/// Member Since, Friends Since, Note) and Activity · Mutual Friends · Mutual
/// Servers at the right. [focusNote] puts the caret in the note ("Add
/// Note").
Future<void> showFullProfile(
  BuildContext context, {
  required String userId,
  String? spaceId,
  bool focusNote = false,
  FullProfileTab initialTab = FullProfileTab.activity,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    builder: (_) => _FullProfileDialog(
      userId: userId,
      spaceId: spaceId,
      focusNote: focusNote,
      initialTab: initialTab,
    ),
  );
}

class _FullProfileDialog extends ConsumerStatefulWidget {
  const _FullProfileDialog({
    required this.userId,
    required this.spaceId,
    required this.focusNote,
    required this.initialTab,
  });

  final String userId;
  final String? spaceId;
  final bool focusNote;
  final FullProfileTab initialTab;

  @override
  ConsumerState<_FullProfileDialog> createState() => _FullProfileDialogState();
}

class _FullProfileDialogState extends ConsumerState<_FullProfileDialog> {
  late FullProfileTab _tab = widget.initialTab;
  final _note = TextEditingController();
  final _noteFocus = FocusNode();
  String? _savedNote;
  int? _relationship;
  String _friendsSince = '';
  List<AccordUser> _mutualFriends = const [];

  String get _serverKey => ref.readActiveServerKey() ?? '';

  @override
  void initState() {
    super.initState();
    _noteFocus.addListener(() {
      if (!_noteFocus.hasFocus) _saveNote();
    });
    if (widget.focusNote) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _noteFocus.requestFocus(),
      );
    }
    _load();
  }

  @override
  void dispose() {
    _saveNote();
    _note.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final client = ref.accordClient;
    if (client == null || widget.userId == ref.readUserId()) return;
    final rels = await client.users.listRelationships();
    final mutual = await client.users.getMutualFriends(widget.userId);
    if (!mounted) return;
    setState(() {
      final data = rels.data;
      if (data is List) {
        for (final r in data.whereType<AccordRelationship>()) {
          if (r.user?.id == widget.userId) {
            _relationship = r.type;
            _friendsSince = r.type == AccordRelationshipType.friend
                ? r.since
                : '';
          }
        }
      }
      final m = mutual.data;
      _mutualFriends = m is List
          ? m.whereType<AccordUser>().toList()
          : const [];
    });
  }

  Future<void> _saveNote() async {
    final saved = _savedNote;
    if (saved == null) return;
    final note = _note.text.trim();
    if (note == saved) return;
    final client = ref.accordClient;
    if (client == null) return;
    _savedNote = note;
    final result = await client.profiles.setNote(widget.userId, note);
    if (!result.ok && mounted) {
      showInfoSnack(context, result.errorMessageOr('Could not save the note'));
    }
  }

  /// The spaces of this connection the user is known to share with you:
  /// those whose member list holds them. Accord has no mutual-servers
  /// endpoint, so a space never opened this session isn't counted (§4).
  List<AccordSpace> _mutualSpaces() {
    final spaces = ref.watch(spacesControllerProvider) ?? const <AccordSpace>[];
    return [
      for (final s in spaces)
        if (ref.watch(
          accordMembersControllerProvider(
            _serverKey,
            s.id,
          ).select((m) => m?.containsKey(widget.userId) ?? false),
        ))
          s,
    ];
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
    final user = member?.user ?? cachedUser;
    final extrasState = ref.watch(
      profileExtrasProvider(serverKey, widget.userId),
    );
    final extras = extrasState.asData?.value;
    final streamer = ref.watch(
      settingsControllerProvider.select((s) => s.streamerMode),
    );
    // The note shows once the profile answered (or failed: it starts empty).
    if (_savedNote == null && (extrasState.hasValue || extrasState.hasError)) {
      _savedNote = extras?.note ?? '';
      _note.text = _savedNote!;
    }
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
    final cdnUrl = ref.watchCdnUrl();
    final isSelf = widget.userId == ref.watchUserId();
    final name = member != null
        ? accordMemberName(member)
        : accordUserName(cachedUser, fallback: widget.userId);
    final avatarUrl = member != null
        ? accordMemberAvatarUrl(member, cdnUrl)
        : accordAvatarUrl(cachedUser, cdnUrl);
    final mutualSpaces = isSelf ? const <AccordSpace>[] : _mutualSpaces();
    final card = profileCardColor(colors);
    final space = spaceId == null
        ? null
        : ref
              .watch(spacesControllerProvider)
              ?.firstWhereOrNull((s) => s.id == spaceId);

    return Dialog(
      backgroundColor: colors.background,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.hairline),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => SizedBox(
          width: constraints.maxWidth.clamp(0, 962).toDouble(),
          height: constraints.maxHeight.clamp(0, 773).toDouble(),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(48, 48, 32, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      // 400 as the reference client's; a narrow window
                      // shares the room.
                      width: math.min(400, (constraints.maxWidth - 80) / 2),
                      child: _ProfileCard(
                        cardColor: card,
                        bannerColor: extras?.themePrimary != null
                            ? profileColor(extras!.themePrimary!)
                            : null,
                        avatarUrl: avatarUrl,
                        avatarColor: accordAvatarColor(user, widget.userId),
                        name: name,
                        username: user?.username ?? '',
                        pronouns: extras?.pronouns,
                        remoteDomain:
                            accordMemberOrigin(member) ??
                            accordUserOrigin(user),
                        status: status,
                        customStatus: customStatus,
                        isSelf: isSelf,
                        bio: user?.bio,
                        memberSince: parseServerTimestamp(
                          user?.createdAt ?? '',
                        ),
                        joinedSpace: member == null
                            ? null
                            : parseServerTimestamp(member.joinedAt),
                        space: space,
                        friendsSince: parseServerTimestamp(_friendsSince),
                        relationship: _relationship,
                        note: isSelf || streamer || _savedNote == null
                            ? null
                            : _note,
                        noteFocus: _noteFocus,
                        onMessage: isSelf
                            ? null
                            : () {
                                Navigator.of(context).pop();
                                openAccordDirectMessage(
                                  context,
                                  ref,
                                  widget.userId,
                                );
                              },
                        onFriend: isSelf
                            ? null
                            : () async {
                                await changeRelationship(
                                  context,
                                  ref,
                                  widget.userId,
                                  _relationship,
                                );
                                _load();
                              },
                        onEditProfile: isSelf
                            ? () {
                                Navigator.of(context).pop();
                                openEditProfile(context);
                              }
                            : null,
                        onMore: (position) => showUserContextMenu(
                          context,
                          ref,
                          userId: widget.userId,
                          user: user,
                          spaceId: spaceId,
                          globalPosition: position,
                          origin: UserMenuOrigin.profile,
                        ),
                      ),
                    ),
                    const SizedBox(width: 32),
                    Expanded(
                      child: _ProfileTabs(
                        tab: _tab,
                        onTab: (t) => setState(() => _tab = t),
                        name: name,
                        isSelf: isSelf,
                        mutualFriends: _mutualFriends,
                        mutualSpaces: mutualSpaces,
                        cdnUrl: cdnUrl,
                        onMessage: isSelf
                            ? null
                            : () {
                                Navigator.of(context).pop();
                                openAccordDirectMessage(
                                  context,
                                  ref,
                                  widget.userId,
                                );
                              },
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: IconButton(
                  key: const Key('full-profile-close'),
                  tooltip: 'Close',
                  style: IconButton.styleFrom(
                    backgroundColor: menuButtonColor(colors),
                    fixedSize: const Size(32, 32),
                    minimumSize: const Size(32, 32),
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  iconSize: 18,
                  color: colors.dirtyWhite,
                  icon: const Icon(AppIcons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The 32 px square buttons of the profile (close, add friend, "…").
Color menuButtonColor(BonfireThemeExtension colors) => Color.alphaBlend(
  colors.dirtyWhite.withValues(alpha: 0.06),
  colors.background,
);
