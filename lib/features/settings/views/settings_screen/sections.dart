part of '../accord_settings_screen.dart';

/// Lets the user pick which connected server's profile to edit (in the
/// Accord menu, at [position]), then opens the per-server profile editor.
void _pickServerProfile(BuildContext context, WidgetRef ref, Offset? position) {
  final connections = ref.read(connectionsControllerProvider).connections;
  showAccordContextMenu(
    context,
    globalPosition: position,
    title: 'Per-server Profile',
    entries: [
      for (final conn in connections)
        AccordMenuEntry(
          label: conn.session.server.name ?? conn.session.server.baseUrl,
          subtitle: conn.session.username,
          onSelected: () => showAccordProfileEdit(context, serverKey: conn.key),
        ),
    ],
  );
}

/// Editable master-server directory URL (default https://master.daccord.gg),
/// used to browse public spaces without an account.
class _MasterServerField extends ConsumerStatefulWidget {
  const _MasterServerField();

  @override
  ConsumerState<_MasterServerField> createState() => _MasterServerFieldState();
}

class _MasterServerFieldState extends ConsumerState<_MasterServerField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: ref.read(settingsControllerProvider).masterServerUrl,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    ref
        .read(settingsControllerProvider.notifier)
        .setMasterServerUrl(_controller.text);
    final applied = ref.read(settingsControllerProvider).masterServerUrl;
    _controller.text = applied;
    FocusScope.of(context).unfocus();
    showInfoSnack(context, 'Master server URL saved');
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Master server URL',
              hintText: AccordSettings.defaultMasterServerUrl,
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _save(),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
