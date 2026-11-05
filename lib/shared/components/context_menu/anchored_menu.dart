part of '../context_menu.dart';

/// Fade-in of an anchored menu; the reference client's menus appear almost at
/// once.
const _kAnchoredMenuDuration = Duration(milliseconds: 100);

Future<void> _showAnchored(
  BuildContext context,
  List<AccordMenuEntry> entries,
  Offset position, {
  required bool preferAbove,
  required bool anchorLeft,
  double anchorX = 0,
  double? width,
}) async {
  final navigator = Navigator.of(context);
  final themes = InheritedTheme.capture(from: context, to: navigator.context);
  final selected = await navigator.push<AccordMenuEntry>(
    _AccordMenuRoute(
      entries: _collapseDividers(entries),
      position: position,
      preferAbove: preferAbove,
      anchorLeft: anchorLeft,
      anchorX: anchorX,
      width: width,
      themes: themes,
    ),
  );
  selected?.onSelected?.call();
}

class _AccordMenuRoute extends PopupRoute<AccordMenuEntry> {
  _AccordMenuRoute({
    required this.entries,
    required this.position,
    required this.preferAbove,
    required this.anchorLeft,
    required this.anchorX,
    required this.width,
    required this.themes,
  });

  final List<AccordMenuEntry> entries;
  final Offset position;
  final bool preferAbove;
  final bool anchorLeft;
  final double anchorX;
  final double? width;
  final CapturedThemes themes;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Dismiss menu';

  @override
  Duration get transitionDuration => _kAnchoredMenuDuration;

  @override
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return themes.wrap(
      _AnchoredMenu(
        entries: entries,
        position: position,
        preferAbove: preferAbove,
        anchorLeft: anchorLeft,
        anchorX: anchorX,
        width: width,
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => FadeTransition(opacity: animation, child: child);
}

/// One open panel: the root menu or a submenu, with where it sits.
class _Panel {
  _Panel(this.entries, this.rect, {this.parentIndex = -1});

  final List<AccordMenuEntry> entries;
  final Rect rect;

  /// The row of the parent panel this submenu belongs to (-1 for the root).
  final int parentIndex;

  /// The highlighted row (hover or keyboard), or -1.
  int highlighted = -1;
}

class _AnchoredMenu extends StatefulWidget {
  const _AnchoredMenu({
    required this.entries,
    required this.position,
    required this.preferAbove,
    required this.anchorLeft,
    required this.anchorX,
    required this.width,
  });

  final List<AccordMenuEntry> entries;
  final Offset position;
  final bool preferAbove;
  final bool anchorLeft;
  final double anchorX;
  final double? width;

  @override
  State<_AnchoredMenu> createState() => _AnchoredMenuState();
}

class _AnchoredMenuState extends State<_AnchoredMenu> {
  final List<_Panel> _panels = [];
  final FocusNode _focus = FocusNode(debugLabel: 'accord-menu');
  Size? _screen;

  static const double _margin = 8;

  double _panelHeight(List<AccordMenuEntry> entries) =>
      entries.fold<double>(18, (h, e) => h + e._rowHeight);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final screen = MediaQuery.sizeOf(context);
    if (_screen != screen) {
      _screen = screen;
      _panels
        ..clear()
        ..add(_Panel(widget.entries, _rootRect(screen)));
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Rect _rootRect(Size screen) {
    final width =
        widget.width ??
        _panelWidth(context, widget.entries, minWidth: kAccordMenuMinWidth);
    final height = math.min(
      _panelHeight(widget.entries),
      screen.height - 2 * _margin,
    );
    final p = widget.position;
    double left;
    double top;
    if (widget.preferAbove) {
      // Opened from a button in a bottom bar, the menu stands above the
      // button (8 px clear of it) — centred on it, or with its left edge on
      // the button's when [anchorLeft].
      left = p.dx - (widget.anchorLeft ? 0 : 90);
      top = p.dy - 8 - height;
    } else {
      left = p.dx - width * widget.anchorX;
      top = p.dy;
      // Past the right edge, the menu opens to the left of the pointer.
      if (left + width > screen.width - _margin) left = p.dx - width;
    }
    left = left.clamp(_margin, math.max(_margin, screen.width - _margin - width));
    top = top.clamp(_margin, math.max(_margin, screen.height - _margin - height));
    return Rect.fromLTWH(left, top, width, height);
  }

  /// Opens [entry]'s submenu beside the row at [row] as panel [depth] + 1.
  void _openSubmenu(int depth, AccordMenuEntry entry, Rect row) {
    final screen = _screen!;
    final parent = _panels[depth].rect;
    final entries = _collapseDividers(entry.submenu!);
    final width = _panelWidth(
      context,
      entries,
      minWidth: kAccordSubmenuMinWidth,
    );
    final height = math.min(_panelHeight(entries), screen.height - 2 * _margin);
    // The submenu's left edge sits 5 px over its parent and its first row
    // level with the hovered one (panel border 1 + padding 8 above it).
    var left = parent.right - 5;
    if (left + width > screen.width - _margin) left = parent.left - width + 5;
    var top = row.top - 9;
    top = top.clamp(_margin, math.max(_margin, screen.height - _margin - height));
    setState(() {
      _panels
        ..removeRange(depth + 1, _panels.length)
        ..add(
          _Panel(
            entries,
            Rect.fromLTWH(left, top, width, height),
            parentIndex: _panels[depth].entries.indexOf(entry),
          ),
        );
    });
  }

  void _closeAfter(int depth) {
    if (_panels.length > depth + 1) {
      setState(() => _panels.removeRange(depth + 1, _panels.length));
    }
  }

  void _hover(int depth, int index, Rect rect) {
    final entry = _panels[depth].entries[index];
    setState(() => _panels[depth].highlighted = index);
    if (entry.hasSubmenu && entry.enabled) {
      if (_panels.length > depth + 1 && _panels[depth + 1].parentIndex == index) {
        return;
      }
      _openSubmenu(depth, entry, rect);
    } else {
      _closeAfter(depth);
    }
  }

  void _activate(int depth, int index) {
    final entry = _panels[depth].entries[index];
    if (entry._activatable) {
      Navigator.of(context).pop(entry);
      return;
    }
    if (entry.hasSubmenu) {
      final rect = _rowRect(depth, index);
      _openSubmenu(depth, entry, rect);
      setState(() => _panels.last.highlighted = _firstInteractive(_panels.last));
    }
  }

  /// A row's global rect, computed from the panel layout (keyboard paths
  /// have no hover rect).
  Rect _rowRect(int depth, int index) {
    final panel = _panels[depth];
    var top = panel.rect.top + 9;
    for (var i = 0; i < index; i++) {
      top += panel.entries[i]._rowHeight;
    }
    return Rect.fromLTWH(
      panel.rect.left + 9,
      top,
      panel.rect.width - 18,
      panel.entries[index]._rowHeight,
    );
  }

  int _firstInteractive(_Panel panel) =>
      panel.entries.indexWhere((e) => e._interactive);

  void _move(int delta) {
    final panel = _panels.last;
    final n = panel.entries.length;
    if (n == 0) return;
    var i = panel.highlighted < 0
        ? (delta > 0 ? -1 : n)
        : panel.highlighted;
    for (var step = 0; step < n; step++) {
      i = (i + delta) % n;
      if (i < 0) i += n;
      if (panel.entries[i]._interactive) {
        setState(() => panel.highlighted = i);
        return;
      }
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final depth = _panels.length - 1;
    if (key == LogicalKeyboardKey.arrowDown) {
      _move(1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _move(-1);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      final i = _panels.last.highlighted;
      if (i >= 0 && _panels.last.entries[i].hasSubmenu) {
        _openSubmenu(depth, _panels.last.entries[i], _rowRect(depth, i));
        setState(
          () => _panels.last.highlighted = _firstInteractive(_panels.last),
        );
      }
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      if (depth > 0) _closeAfter(depth - 1);
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      final i = _panels.last.highlighted;
      if (i >= 0) _activate(depth, i);
    } else if (key == LogicalKeyboardKey.escape) {
      if (depth > 0) {
        _closeAfter(depth - 1);
      } else {
        Navigator.of(context).pop();
      }
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Stack(
        children: [
          for (var depth = 0; depth < _panels.length; depth++)
            Positioned.fromRect(
              rect: _panels[depth].rect,
              child: _PanelView(
                panel: _panels[depth],
                openIndex: depth + 1 < _panels.length
                    ? _panels[depth].highlighted
                    : null,
                colors: colors,
                onHover: (index, rect) => _hover(depth, index, rect),
                onTap: (index) => _activate(depth, index),
                onExit: () {
                  // Leaving a leaf panel clears its hover, as the reference
                  // client does; a parent keeps its open row lit.
                  if (depth == _panels.length - 1) {
                    setState(() => _panels[depth].highlighted = -1);
                  }
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _PanelView extends StatelessWidget {
  const _PanelView({
    required this.panel,
    required this.openIndex,
    required this.colors,
    required this.onHover,
    required this.onTap,
    required this.onExit,
  });

  final _Panel panel;
  final int? openIndex;
  final BonfireThemeExtension colors;
  final void Function(int index, Rect rect) onHover;
  final ValueChanged<int> onTap;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < panel.entries.length; i++) {
      final entry = panel.entries[i];
      if (entry.isDivider) {
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Container(height: 1, color: colors.hairline),
          ),
        );
      } else if (entry.isWidget) {
        children.add(
          KeyedSubtree(
            key: entry.key,
            child: SizedBox(height: entry.height, child: entry.child),
          ),
        );
      } else {
        children.add(
          _MenuRow(
            entry: entry,
            highlighted: panel.highlighted == i || openIndex == i,
            onHover: (rect) => onHover(i, rect),
            onTap: () => onTap(i),
          ),
        );
      }
    }
    return MouseRegion(
      onExit: (_) => onExit(),
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          decoration: BoxDecoration(
            color: menuSurfaceColor(colors),
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
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
