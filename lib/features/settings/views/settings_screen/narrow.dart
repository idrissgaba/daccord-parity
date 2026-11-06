part of '../accord_settings_screen.dart';

/// Phones and narrow windows: the pages as one list (you at the top, the
/// groups, Log Out), each page opening on its own screen with the same body
/// as the desktop modal.
class _NarrowSettings extends StatefulWidget {
  const _NarrowSettings({
    required this.initialPage,
    required this.onLogOut,
    required this.onClose,
  });

  final SettingsPage? initialPage;
  final VoidCallback onLogOut;
  final VoidCallback onClose;

  @override
  State<_NarrowSettings> createState() => _NarrowSettingsState();
}

class _NarrowSettingsState extends State<_NarrowSettings> {
  @override
  void initState() {
    super.initState();
    final page = widget.initialPage;
    if (page != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _open(page);
      });
    }
  }

  void _open(SettingsPage page) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _NarrowSettingsPage(
          page: page,
          onOpenPage: (next) {
            Navigator.of(context).pop();
            _open(next);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final rows = <Widget>[];
    SettingsGroup? group;
    for (final page in visibleSettingsPages()) {
      if (group != null && page.group != group) {
        rows.add(const _SidebarSeparator());
        if (page.group.label != null) {
          rows.add(_SidebarHeading(page.group.label!));
        }
      }
      group = page.group;
      rows
        ..add(
          _SidebarItem(
            key: ValueKey('settings-nav-${page.name}'),
            icon: page.icon,
            label: page.label,
            selected: false,
            onTap: () => _open(page),
          ),
        )
        ..add(const SizedBox(height: 4));
    }
    rows
      ..add(
        _SidebarItem(
          key: const ValueKey('settings-nav-logout'),
          icon: AppIcons.logout,
          label: 'Log Out',
          selected: false,
          danger: true,
          onTap: widget.onLogOut,
        ),
      )
      ..add(const _SidebarFooter());
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        title: const Text('Settings'),
        leading: IconButton(
          key: const Key('settings-close'),
          icon: const Icon(AppIcons.arrowBack),
          onPressed: widget.onClose,
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          key: const ValueKey('settings-page-list'),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            const _SidebarHeader(),
            const SizedBox(height: 12),
            ...rows,
          ],
        ),
      ),
    );
  }
}

class _NarrowSettingsPage extends StatelessWidget {
  const _NarrowSettingsPage({required this.page, required this.onOpenPage});

  final SettingsPage page;
  final ValueChanged<SettingsPage> onOpenPage;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Scaffold(
      backgroundColor: colors.raised,
      appBar: AppBar(backgroundColor: colors.raised, title: Text(page.label)),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 48),
          child: _SettingsPageBody(page: page, onOpenPage: onOpenPage),
        ),
      ),
    );
  }
}
