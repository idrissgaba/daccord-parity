part of 'accord_home.dart';

/// The 32 px bar across the top of the desktop home screen: the open
/// channel's name in the middle (with its space's icon), the inbox and help
/// buttons on the right. On Windows the native frame is hidden and the bar
/// also carries the window controls and moves the window, as in the
/// reference client; elsewhere the platform keeps its own frame above it.
class HomeTitleBar extends StatelessWidget {
  const HomeTitleBar({
    super.key,
    required this.title,
    required this.space,
    required this.cdnUrl,
  });

  final String title;
  final AccordSpace? space;
  final String? cdnUrl;

  /// Whether the bar replaces the native frame (and so draws window buttons).
  static bool get ownsWindowFrame => !kIsWeb && UniversalPlatform.isWindows;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    final space = this.space;
    final iconUrl = space == null ? null : accordSpaceIconUrl(space, cdnUrl);
    final content = SizedBox(
      height: kHomeTitleBarHeight,
      child: Stack(
        children: [
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (iconUrl != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: CachedNetworkImage(
                      imageUrl: iconUrl,
                      width: 16,
                      height: 16,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => const SizedBox.shrink(),
                    ),
                  )
                else
                  Icon(
                    space == null ? AppIcons.chatBubble : AppIcons.tag,
                    size: 14,
                    color: colors.interactive,
                  ),
                const SizedBox(width: 8),
                Text(
                  title,
                  key: const Key('home-title-bar-title'),
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium!.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: colors.dirtyWhite,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: Row(
              children: [
                // The popover hangs from the button's own box.
                Builder(
                  builder: (buttonContext) => _TitleBarButton(
                    key: const Key('home-title-bar-inbox'),
                    tooltip: 'Inbox',
                    icon: AppIcons.tray,
                    onPressed: () => showInboxPopover(buttonContext),
                  ),
                ),
                // Glyph centres 36 px apart, as in the reference client.
                const SizedBox(width: 8),
                _TitleBarButton(
                  key: const Key('home-title-bar-help'),
                  tooltip: 'Help',
                  icon: AppIcons.helpOutline,
                  onPressed: () => launchUrl(
                    Uri.parse(kDaccordHelpUrl),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
                if (ownsWindowFrame) ...[
                  const SizedBox(width: 8),
                  const _WindowButtons(),
                ] else
                  // The reference client's help glyph is centred 24 px from
                  // the edge (24 px boxes, 12 px apart, 12 px margin).
                  const SizedBox(width: 10),
              ],
            ),
          ),
        ],
      ),
    );
    final bar = ColoredBox(color: colors.foreground, child: content);
    if (!ownsWindowFrame) return bar;
    return DragToMoveArea(child: bar);
  }
}

/// An 18 px icon button of the title bar, in the bar's muted tint.
class _TitleBarButton extends StatelessWidget {
  const _TitleBarButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 32),
      icon: Icon(icon, size: 18, color: colors.interactive),
    );
  }
}

/// Minimise / maximise / close, drawn by the app when it owns the frame.
class _WindowButtons extends StatefulWidget {
  const _WindowButtons();

  @override
  State<_WindowButtons> createState() => _WindowButtonsState();
}

class _WindowButtonsState extends State<_WindowButtons> with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.isMaximized().then((value) {
      if (mounted) setState(() => _maximized = value);
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    Widget button(
      IconData icon,
      String tooltip,
      VoidCallback onPressed, {
      bool danger = false,
    }) => Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        hoverColor: danger ? colors.red : colors.hover,
        child: SizedBox(
          width: 40,
          height: kHomeTitleBarHeight,
          child: Icon(icon, size: 14, color: colors.interactive),
        ),
      ),
    );
    return Row(
      children: [
        button(AppIcons.remove, 'Minimize', windowManager.minimize),
        button(
          _maximized ? AppIcons.fullscreenExit : AppIcons.checkBoxOutlineBlank,
          _maximized ? 'Restore' : 'Maximize',
          () => _maximized
              ? windowManager.unmaximize()
              : windowManager.maximize(),
        ),
        button(AppIcons.close, 'Close', windowManager.close, danger: true),
      ],
    );
  }
}
