import 'package:accordkit/accordkit.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/features/events/controllers/connection.dart';
import 'package:bonfire/features/events/controllers/presence.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/member/views/accord_member_avatar.dart';
import 'package:bonfire/features/member/views/accord_member_popout.dart';
import 'package:bonfire/features/member/views/remote_origin_badge.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/features/spaces/models/home_layout.dart';
import 'package:bonfire/features/user/views/accord_direct_messages.dart';
import 'package:bonfire/features/voice/controllers/voice_states.dart';
import 'package:bonfire/shared/components/async_state_views.dart';
import 'package:bonfire/shared/components/server_unreachable.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/theme/app_icons.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The right-hand member roster for the Accord home view. Groups the space's
/// cached members under their highest hoisted role, then "Online", then
/// "Offline" (drawn at 30 %), tinting each name by its highest colored role,
/// with the owner's crown and a status line (custom status or "In voice")
/// under the name, as in other chat apps. Driven by the
/// [AccordMembersController] cache.
class AccordMemberList extends ConsumerWidget {
  const AccordMemberList({super.key, required this.spaceId});

  final String? spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final id = spaceId;

    final body = id == null ? const SizedBox.shrink() : _Roster(spaceId: id);

    return Container(
      key: const Key('member-list'),
      width: kMemberListWidth,
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(left: BorderSide(color: colors.hairline, width: 1)),
      ),
      child: body,
    );
  }
}

class _Roster extends ConsumerWidget {
  const _Roster({required this.spaceId});

  final String spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serverKey = ref.watchActiveServerKey() ?? '';
    final members = ref.watch(
      accordMembersControllerProvider(serverKey, spaceId),
    );
    // One selector for everything read off the cached space, so a rebuild
    // only walks spacesControllerProvider's list once instead of twice.
    final spaceInfo = ref.watch(
      spacesControllerProvider.select((spaces) {
        final space = spaces?.firstWhereOrNull((s) => s.id == spaceId);
        return (
          roles: space?.roles ?? const <AccordRole>[],
          memberCount: space?.memberCount,
          presenceCount: space?.presenceCount,
          ownerId: space?.ownerId ?? '',
        );
      }),
    );
    final roles = spaceInfo.roles;
    final cdnUrl = ref.watchCdnUrl();
    final presences = ref.watch(activePresencesProvider);
    // Who is in a voice channel of this space, for the "In voice" line.
    final inVoice = ref.watch(
      voiceStatesControllerProvider(serverKey).select(
        (cache) => {
          for (final bucket in cache.values)
            for (final state in bucket.values)
              if (state.spaceId == spaceId) state.userId,
        },
      ),
    );

    if (members == null) {
      // The roster fetch itself failed (timeout / non-2xx / network) — surface
      // a retry instead of spinning forever. onRetry clears the failed flag
      // itself, then invalidates the controller to re-run `_load`.
      if (ref.watch(membersLoadFailedProvider(serverKey, spaceId))) {
        return ServerUnreachable(
          title: "Couldn't load members",
          message: 'Something went wrong fetching the member list.',
          onRetry: () {
            ref
                .read(membersLoadFailedProvider(serverKey, spaceId).notifier)
                .set(false);
            ref.invalidate(accordMembersControllerProvider(serverKey, spaceId));
          },
        );
      }
      final connectionStatus = ref.watch(
        connectionsControllerProvider.select(
          (connections) =>
              connections.active?.status ?? ConnectionStatus.disconnected,
        ),
      );
      if (connectionStatus.isUnreachable) {
        return ServerUnreachable(
          onRetry: () => ref.accordClient?.ensureConnected(),
        );
      }
      return const LoadingView();
    }

    final sections = _buildSections(
      members.values.toList(),
      roles,
      presences,
      memberCount: spaceInfo.memberCount,
      presenceCount: spaceInfo.presenceCount,
    );

    // Flatten sections into one lazily-built row list so a large roster only
    // materializes the rows on screen.
    final rows = <Widget Function()>[
      for (final section in sections) ...[
        () => _SectionHeader(
          label: section.label,
          count: section.count ?? section.members.length,
        ),
        for (final member in section.members)
          () => _MemberRow(
            member: member,
            roles: roles,
            cdnUrl: cdnUrl,
            spaceId: spaceId,
            status: accordPresenceStatus(presences, member.userId),
            customStatus: accordCustomStatus(presences, member.userId),
            isOwner: member.userId == spaceInfo.ownerId,
            inVoice: inVoice.contains(member.userId),
          ),
      ],
    ];

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: rows.length,
      itemBuilder: (context, index) => rows[index](),
    );
  }
}

/// One roster group: a hoisted role's members, the online bucket, or the
/// offline bucket.
class _RosterSection {
  _RosterSection({required this.label, required this.position}) : members = [];

  final String label;

  /// Role position for ordering; the online bucket uses [_onlinePosition] so
  /// it sorts after every role, the offline one [_offlinePosition] so it is
  /// last.
  final int position;
  final List<AccordMember> members;
  int? count;
}

const int _onlinePosition = -1;
const int _offlinePosition = -2;

/// Buckets online [members] under their highest hoisted role (falling back to
/// an "Online" group); all offline members collapse into a single trailing
/// "Offline" section. Sections sort by role position descending, then
/// "Online", then "Offline" last; members within a section sort by name.
List<_RosterSection> _buildSections(
  List<AccordMember> members,
  List<AccordRole> roles,
  PresenceMap presences, {
  Object? memberCount,
  Object? presenceCount,
}) {
  final byKey = <String, _RosterSection>{};
  final onlineSection = _RosterSection(
    label: 'Online',
    position: _onlinePosition,
  );
  final offlineSection = _RosterSection(
    label: 'Offline',
    position: _offlinePosition,
  );

  for (final member in members) {
    if (!accordIsVisibleStatus(
      accordPresenceStatus(presences, member.userId),
    )) {
      offlineSection.members.add(member);
      continue;
    }
    final role = memberHoistRole(member, roles);
    if (role == null) {
      onlineSection.members.add(member);
      continue;
    }
    final section = byKey.putIfAbsent(
      role.id,
      () => _RosterSection(label: role.name, position: role.position),
    );
    section.members.add(member);
  }

  offlineSection.count = rosterOfflineCount(
    memberCount: memberCount,
    presenceCount: presenceCount,
    loadedOfflineCount: offlineSection.members.length,
  );

  final sections = byKey.values.toList()
    ..sort((a, b) => b.position.compareTo(a.position));
  if (onlineSection.members.isNotEmpty) sections.add(onlineSection);
  if ((offlineSection.count ?? 0) > 0) sections.add(offlineSection);

  final sortNames = {
    for (final member in members)
      member: accordMemberName(member).toLowerCase(),
  };
  for (final section in sections) {
    section.members.sort((a, b) => sortNames[a]!.compareTo(sortNames[b]!));
  }
  return sections;
}

/// The roster loads every page, so counts use the same current rows and
/// presence grace as grouping rather than an older space-summary snapshot.
int rosterOfflineCount({
  required Object? memberCount,
  required Object? presenceCount,
  required int loadedOfflineCount,
}) => loadedOfflineCount;

/// "Role — N": 14 px medium grey, in a 42 px box that puts 24 px of air above
/// the first row of the group.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Container(
      height: 42,
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
      alignment: Alignment.bottomLeft,
      child: Text(
        '$label — $count',
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyMedium!.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: colors.gray,
        ),
      ),
    );
  }
}

class _MemberRow extends ConsumerWidget {
  const _MemberRow({
    required this.member,
    required this.roles,
    required this.cdnUrl,
    required this.spaceId,
    required this.status,
    required this.customStatus,
    required this.isOwner,
    required this.inVoice,
  });

  final AccordMember member;
  final List<AccordRole> roles;
  final String? cdnUrl;
  final String spaceId;
  final String status;
  final String? customStatus;
  final bool isOwner;
  final bool inVoice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final name = accordMemberName(member);
    final avatarUrl = accordMemberAvatarUrl(member, cdnUrl);
    final colorRole = memberColorRole(member, roles);
    final nameColor = colorRole == null
        ? null
        : accordRoleColor(colorRole.color);
    final initial = accordInitial(name);
    // Offline members read as faded, as in the reference roster.
    final dimmed = !accordIsVisibleStatus(status);
    final subtitle = inVoice
        ? 'In voice'
        : (customStatus?.isNotEmpty ?? false)
        ? customStatus
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          hoverColor: colors.hover,
          onTap: () => showAccordMemberPopout(
            context,
            spaceId: spaceId,
            userId: member.userId,
          ),
          onSecondaryTapUp: (d) => _showMemberContextMenu(
            context,
            ref,
            member,
            spaceId,
            d.globalPosition,
          ),
          onLongPress: () =>
              _showMemberContextMenu(context, ref, member, spaceId, null),
          child: Opacity(
            opacity: dimmed ? 0.3 : 1,
            child: SizedBox(
              height: 42,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    AccordMemberAvatar(
                      avatarUrl: avatarUrl,
                      initial: initial,
                      status: status,
                      radius: 16,
                      backgroundColor: accordAvatarColor(
                        member.user,
                        member.userId,
                      ),
                      statusRingColor: colors.background,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  name,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyLarge!.copyWith(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: nameColor ?? colors.gray,
                                  ),
                                ),
                              ),
                              if (isOwner) ...[
                                const SizedBox(width: 4),
                                Tooltip(
                                  message: 'Server Owner',
                                  child: Icon(
                                    AppIcons.crown,
                                    key: const Key('member-owner-crown'),
                                    size: 14,
                                    color: const Color(0xFFEA9800),
                                  ),
                                ),
                              ],
                              if (member.isRemote) ...[
                                const SizedBox(width: 6),
                                RemoteOriginBadge(
                                  domain: member.homeDomain,
                                  showDomain: false,
                                ),
                              ],
                            ],
                          ),
                          if (subtitle != null)
                            Row(
                              children: [
                                if (inVoice) ...[
                                  Icon(
                                    AppIcons.volumeUp,
                                    size: 12,
                                    color: colors.green,
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                Flexible(
                                  child: Text(
                                    subtitle,
                                    key: const Key('member-status-line'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall!.copyWith(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: colors.gray,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Quick-utility right-click / long-press menu for a roster member: view their
/// profile, start a DM, or copy their id/username. Moderation lives in the
/// profile popout reached by tapping the row. [globalPos] is the pointer
/// location for a right-click; it's null for a long-press, where the menu
/// anchors to the overlay centre instead.
Future<void> _showMemberContextMenu(
  BuildContext context,
  WidgetRef ref,
  AccordMember member,
  String spaceId,
  Offset? globalPos,
) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (overlay == null) return;
  final anchor = globalPos ?? overlay.size.center(Offset.zero);
  final currentUserId = ref.readUserId();
  final isSelf = currentUserId != null && currentUserId == member.userId;
  final username = member.user?.username;
  final selected = await showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(
      anchor & const Size(40, 40),
      Offset.zero & overlay.size,
    ),
    items: [
      const PopupMenuItem(value: 'profile', child: Text('View Profile')),
      if (!isSelf)
        const PopupMenuItem(value: 'dm', child: Text('Direct Message')),
      const PopupMenuDivider(),
      const PopupMenuItem(value: 'copyId', child: Text('Copy User ID')),
      if (username != null && username.isNotEmpty)
        const PopupMenuItem(value: 'copyName', child: Text('Copy Username')),
    ],
  );
  if (selected == null || !context.mounted) return;
  switch (selected) {
    case 'profile':
      await showAccordMemberPopout(
        context,
        spaceId: spaceId,
        userId: member.userId,
      );
    case 'dm':
      await openAccordDirectMessage(context, ref, member.userId);
    case 'copyId':
      await Clipboard.setData(ClipboardData(text: member.userId));
      if (context.mounted) showInfoSnack(context, 'User ID copied');
    case 'copyName':
      await Clipboard.setData(ClipboardData(text: username!));
      if (context.mounted) showInfoSnack(context, 'Username copied');
  }
}
