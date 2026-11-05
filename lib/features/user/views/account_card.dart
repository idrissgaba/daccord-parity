import 'dart:async';

import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/events/controllers/presence.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/member/views/accord_member_avatar.dart';
import 'package:bonfire/features/member/views/profile_card.dart';
import 'package:bonfire/features/member/views/profile_extras.dart'
    show profileColor;
import 'package:bonfire/features/member/controllers/profile_extras.dart';
import 'package:bonfire/features/messaging/views/emoji_picker.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/features/user/controllers/self_presence.dart';
import 'package:bonfire/shared/components/context_menu.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/theme/app_icons.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

part 'account_card/status_dialog.dart';
part 'account_card/card_rows.dart';

/// "Edit Profile": the profile page of the settings (its modal form comes
/// with the settings lot).
void openEditProfile(BuildContext context) => context.push('/settings');

/// The reference client's label for a presence status.
String statusLabel(String status) => switch (status) {
  'idle' => 'Idle',
  'dnd' => 'Do Not Disturb',
  'invisible' || 'offline' => 'Invisible',
  _ => 'Online',
};

/// The status glyph of a status choice, in the reference client's shapes: a
/// green dot, a yellow moon, a red dot with a bar, a grey ring (12 px).
Widget statusDot(String status) => Builder(
  builder: (context) {
    final colors = BonfireThemeExtension.of(context);
    final (icon, color) = switch (status) {
      'idle' => (AppIcons.nightlightRound, colors.yellow),
      'dnd' => (AppIcons.removeCircle, colors.red),
      'invisible' || 'offline' => (AppIcons.circleOutlined, colors.gray),
      _ => (AppIcons.circle, colors.green),
    };
    return Icon(icon, size: 12, color: color);
  },
);

/// The status submenu: Online · Idle ›, Do Not Disturb › ("You will not
/// receive desktop notifications"), Invisible › ("You will appear offline"),
/// each timed with For 15 Minutes … For 3 Days, Forever.
List<AccordMenuEntry> statusMenuEntries(WidgetRef ref, String serverKey) {
  final presence = ref.read(selfPresenceControllerProvider.notifier);
  AccordMenuEntry timed(String status, {String? subtitle}) => AccordMenuEntry(
    key: Key('status-$status'),
    label: statusLabel(status),
    subtitle: subtitle,
    leading: statusDot(status),
    onSelected: () => presence.setStatus(serverKey, status),
    submenu: [
      for (final d in kStatusDurations)
        AccordMenuEntry(
          label: d.label,
          onSelected: () =>
              presence.setStatus(serverKey, status, until: untilFrom(d.duration)),
        ),
    ],
  );
  return [
    AccordMenuEntry(
      key: const Key('status-online'),
      label: 'Online',
      leading: statusDot('online'),
      onSelected: () => presence.setStatus(serverKey, 'online'),
    ),
    const AccordMenuEntry.divider(),
    timed('idle'),
    timed('dnd', subtitle: 'You will not receive desktop notifications'),
    timed('invisible', subtitle: 'You will appear offline'),
  ];
}

/// Opens the account card above the user panel (a click on your name):
/// banner, avatar, status bubble, name, then Edit Profile · status › and
/// Switch Accounts › · Copy User ID. "Badges", "Orbs" and the Nitro offer are
/// omitted (§4). [anchor] is the panel's rect.
Future<void> showAccountCard(BuildContext context, {required Rect anchor}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close account card',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 100),
    pageBuilder: (dialogContext, _, _) => Stack(
      children: [
        Positioned(
          left: 8,
          bottom: MediaQuery.sizeOf(dialogContext).height - anchor.top + 8,
          child: const _AccountCard(),
        ),
      ],
    ),
    transitionBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}

class _AccountCard extends ConsumerWidget {
  const _AccountCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final serverKey = ref.watchActiveServerKey() ?? '';
    final userId = ref.watchUserId() ?? '';
    final user = ref.watch(
      accordUsersControllerProvider(serverKey).select((u) => u[userId]),
    );
    final sessionName = ref.watch(
      accordAuthProvider.select(
        (s) => s is AccordAuthLoggedIn ? s.session.username : null,
      ),
    );
    final status = ref.watch(
      activePresencesProvider.select((p) => accordPresenceStatus(p, userId)),
    );
    final customStatus = ref.watch(
      activePresencesProvider.select((p) => accordCustomStatus(p, userId)),
    );
    final extras = ref
        .watch(profileExtrasProvider(serverKey, userId))
        .asData
        ?.value;
    final name = accordUserName(user, fallback: sessionName ?? userId);
    final avatarUrl = user == null ? null : accordAvatarUrl(user, ref.watchCdnUrl());
    final card = profileCardColor(colors);
    final shownStatus = status == 'offline' ? 'invisible' : status;

    return Material(
      type: MaterialType.transparency,
      child: Container(
        key: const Key('account-card'),
        width: 300,
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 105 + 44,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  ProfileBanner(
                    height: 105,
                    topRadius: 7,
                    color: extras?.themePrimary != null
                        ? profileColor(extras!.themePrimary!)
                        : null,
                    avatarUrl: avatarUrl,
                  ),
                  Positioned(
                    left: 12,
                    top: 57,
                    child: ProfileAvatarCutout(
                      size: 80,
                      ring: 4,
                      avatarUrl: avatarUrl,
                      initial: accordInitial(name),
                      backgroundColor: accordAvatarColor(user, userId),
                      status: status,
                      cardColor: card,
                    ),
                  ),
                  Positioned(
                    left: 106,
                    top: 99,
                    child: CustomStatusBubble(
                      key: const Key('account-card-status-bubble'),
                      text: customStatus,
                      prompt: statusPromptOfTheDay(),
                      onTap: () {
                        Navigator.of(context).pop();
                        showCustomStatusDialog(context, ref);
                      },
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      height: 24 / 20,
                      color: colors.dirtyWhite,
                    ),
                  ),
                  const SizedBox(height: 3),
                  if ((user?.username ?? '').isNotEmpty)
                    Text(
                      user!.username,
                      style: TextStyle(
                        fontSize: 14,
                        height: 18 / 14,
                        color: colors.dirtyWhite,
                      ),
                    ),
                  const SizedBox(height: 16),
                  _CardGroup(
                    children: [
                      _CardRow(
                        key: const Key('account-card-edit-profile'),
                        icon: AppIcons.edit,
                        label: 'Edit Profile',
                        onTap: (_) {
                          Navigator.of(context).pop();
                          openEditProfile(context);
                        },
                      ),
                      _CardRow(
                        key: const Key('account-card-status'),
                        leading: statusDot(shownStatus),
                        label: statusLabel(shownStatus),
                        chevron: true,
                        opensOnHover: true,
                        onTap: (rowRect) => showAccordContextMenu(
                          context,
                          // Over the card's edge by 10 px, its first row
                          // level with this one.
                          globalPosition: Offset(
                            rowRect.right + 12,
                            rowRect.top - 2,
                          ),
                          width: 300,
                          entries: statusMenuEntries(ref, serverKey),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _CardGroup(
                    children: [
                      _CardRow(
                        key: const Key('account-card-switch'),
                        icon: AppIcons.accountCircleOutlined,
                        label: 'Switch Accounts',
                        chevron: true,
                        opensOnHover: true,
                        onTap: (rowRect) async {
                          final entries = await _switchAccountEntries(
                            context,
                            ref,
                          );
                          if (!context.mounted) return;
                          showAccordContextMenu(
                            context,
                            globalPosition: Offset(
                              rowRect.right + 12,
                              rowRect.top - 2,
                            ),
                            entries: entries,
                          );
                        },
                      ),
                      _CardRow(
                        key: const Key('account-card-copy-id'),
                        icon: AppIcons.idCard,
                        label: 'Copy User ID',
                        onTap: (_) {
                          Clipboard.setData(ClipboardData(text: userId));
                          Navigator.of(context).pop();
                        },
                      ),
                    ],
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

/// Switch Accounts ›: the saved accounts (the current one ticked), then
/// Manage Accounts.
Future<List<AccordMenuEntry>> _switchAccountEntries(
  BuildContext context,
  WidgetRef ref,
) async {
  final auth = ref.read(accordAuthProvider.notifier);
  final colors = BonfireThemeExtension.of(context);
  final accounts = await auth.listAccounts();
  final state = ref.read(accordAuthProvider);
  final current = state is AccordAuthLoggedIn ? state.session : null;
  bool same(AccordSession a) => current != null && a.key == current.key;
  return [
    for (final account in accounts)
      AccordMenuEntry(
        label: account.username.isEmpty
            ? account.server.homeDomain
            : account.username,
        leading: AccordMemberAvatar(
          avatarUrl: null,
          initial: accordInitial(account.username),
          radius: 10,
          backgroundColor: accordIdColor(account.userId),
          initialStyle: const TextStyle(fontSize: 9),
        ),
        trailing: same(account)
            ? Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: colors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(AppIcons.check, size: 12, color: Colors.white),
              )
            : null,
        onSelected: same(account) ? () {} : () => auth.switchTo(account),
      ),
    const AccordMenuEntry.divider(),
    AccordMenuEntry(
      label: 'Manage Accounts',
      onSelected: () {
        Navigator.of(context).maybePop();
        context.push('/switcher');
      },
    ),
  ];
}
