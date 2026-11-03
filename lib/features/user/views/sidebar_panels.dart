import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';

/// The raised card at the foot of the sidebar: the voice connection panel
/// (empty while not in a call) above the user panel, sharing one rounded
/// surface, as in the reference client.
class SidebarPanels extends StatelessWidget {
  const SidebarPanels({super.key, required this.voice, required this.user});

  final Widget voice;
  final Widget user;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Material(
      key: const Key('sidebar-panels'),
      color: colors.raised,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [voice, user],
      ),
    );
  }
}
