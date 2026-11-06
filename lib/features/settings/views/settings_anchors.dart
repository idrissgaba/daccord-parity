import 'package:flutter/widgets.dart';

/// The anchors of the settings page on screen, so the sidebar's sub-items
/// ("Voice", "Camera", "Streaming" …) can scroll the page to a section and
/// follow the one being read.
class SettingsAnchors extends InheritedWidget {
  const SettingsAnchors({super.key, required this.keys, required super.child});

  /// Section id → the key of its [SettingsAnchor].
  final Map<String, GlobalKey> keys;

  static SettingsAnchors? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SettingsAnchors>();

  @override
  bool updateShouldNotify(SettingsAnchors oldWidget) => false;
}

/// Marks [child] as the section [id] of the current settings page.
class SettingsAnchor extends StatefulWidget {
  const SettingsAnchor({super.key, required this.id, required this.child});

  final String id;
  final Widget child;

  @override
  State<SettingsAnchor> createState() => _SettingsAnchorState();
}

class _SettingsAnchorState extends State<SettingsAnchor> {
  final GlobalKey _key = GlobalKey();
  SettingsAnchors? _registry;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _registry = SettingsAnchors.maybeOf(context);
    _registry?.keys[widget.id] = _key;
  }

  @override
  void dispose() {
    final keys = _registry?.keys;
    if (keys != null && keys[widget.id] == _key) keys.remove(widget.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      KeyedSubtree(key: _key, child: widget.child);
}
