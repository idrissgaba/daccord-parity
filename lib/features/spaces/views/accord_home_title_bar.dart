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
                _TitleBarButton(
                  key: const Key('home-title-bar-inbox'),
                  tooltip: 'Inbox',
                  icon: AppIcons.tray,
                  onPressed: () => showInboxPopover(context),
                ),
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
                ],
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

/// The inbox: unread and mentions are tracked by the notifications lot; until
/// then the popover says so instead of pretending to be empty of news.
Future<void> showInboxPopover(BuildContext context) {
  final colors = BonfireThemeExtension.of(context);
  final box = context.findRenderObject() as RenderBox?;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  final anchor = box == null || overlay == null
      ? Offset.zero
      : box.localToGlobal(
          Offset(box.size.width, box.size.height),
          ancestor: overlay,
        );
  return showDialog<void>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (context) => Stack(
      children: [
        Positioned(
          right: 8,
          top: anchor.dy + 4,
          child: Material(
            color: colors.raised,
            elevation: 8,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: 480,
              height: 360,
              child: Column(
                children: [
                  Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: colors.hairline),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(AppIcons.tray, size: 20, color: colors.dirtyWhite),
                        const SizedBox(width: 8),
                        Text(
                          'Inbox',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        'Nothing here yet',
                        key: const Key('inbox-empty'),
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium!.copyWith(color: colors.gray),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
