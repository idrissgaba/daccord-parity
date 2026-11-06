import 'dart:async';
import 'dart:math' as math;

import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';

/// Tracks whether the settings page on screen holds unsaved edits, and lets
/// its frame refuse to close or switch pages while it does.
///
/// The reference client keeps you on a page with pending edits: closing (✕,
/// Escape) or picking another page only turns the "Careful — you have
/// unsaved changes!" bar red and shakes it.
class UnsavedChangesController extends ChangeNotifier {
  bool _dirty = false;
  bool _disposed = false;
  bool _warning = false;
  int _shakes = 0;
  Timer? _warningTimer;

  /// Whether the current page has edits that are neither saved nor reset.
  bool get dirty => _dirty;
  set dirty(bool value) {
    if (_disposed || _dirty == value) return;
    _dirty = value;
    if (!value) _clearWarning();
    notifyListeners();
  }

  /// Whether the bar is in its red warning state.
  bool get warning => _warning;

  /// Bumped on every refused leave; the bar shakes when it changes.
  int get shakes => _shakes;

  /// Returns true when the page may be left; otherwise warns and returns
  /// false.
  bool attemptLeave() {
    if (!_dirty) return true;
    _warning = true;
    _shakes++;
    _warningTimer?.cancel();
    _warningTimer = Timer(const Duration(milliseconds: 1500), () {
      if (_disposed) return;
      _warning = false;
      notifyListeners();
    });
    notifyListeners();
    return false;
  }

  void _clearWarning() {
    _warningTimer?.cancel();
    _warning = false;
  }

  @override
  void dispose() {
    _disposed = true;
    _warningTimer?.cancel();
    super.dispose();
  }
}

/// Provides the frame's [UnsavedChangesController] to the page it shows.
class UnsavedChangesScope extends InheritedNotifier<UnsavedChangesController> {
  const UnsavedChangesScope({
    super.key,
    required UnsavedChangesController controller,
    required super.child,
  }) : super(notifier: controller);

  static UnsavedChangesController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<UnsavedChangesScope>()
      ?.notifier;
}

/// Refuses a route pop while [controller] is dirty and warns instead.
class UnsavedChangesPopGuard extends StatelessWidget {
  const UnsavedChangesPopGuard({
    super.key,
    required this.controller,
    required this.child,
  });

  final UnsavedChangesController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, child) => PopScope(
        canPop: !controller.dirty,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) controller.attemptLeave();
        },
        child: child!,
      ),
      child: child,
    );
  }
}

/// Lays [child] out with the unsaved-changes bar floating 20 px above its
/// bottom edge while [dirty], and reports [dirty] to the enclosing
/// [UnsavedChangesScope] (when there is one) so the frame can guard leaving.
class UnsavedChangesHost extends StatefulWidget {
  const UnsavedChangesHost({
    super.key,
    required this.dirty,
    required this.onReset,
    required this.onSave,
    required this.child,
    this.saving = false,
    this.barWidth = 700,
    this.alignment = Alignment.bottomLeft,
    this.inset = EdgeInsets.zero,
  });

  final bool dirty;
  final VoidCallback onReset;
  final VoidCallback? onSave;
  final bool saving;
  final Widget child;

  /// The bar's width; it shrinks with narrower hosts.
  final double barWidth;

  /// Where the bar sits along the bottom edge.
  final AlignmentGeometry alignment;

  /// Extra room around the bar inside the host.
  final EdgeInsets inset;

  @override
  State<UnsavedChangesHost> createState() => _UnsavedChangesHostState();
}

class _UnsavedChangesHostState extends State<UnsavedChangesHost> {
  UnsavedChangesController? _scope;
  UnsavedChangesController? _own;

  UnsavedChangesController get _controller =>
      _scope ?? (_own ??= UnsavedChangesController());

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = context
        .getInheritedWidgetOfExactType<UnsavedChangesScope>()
        ?.notifier;
    if (scope != _scope) {
      _scope = scope;
      _report();
    }
  }

  @override
  void initState() {
    super.initState();
    _report();
  }

  @override
  void didUpdateWidget(covariant UnsavedChangesHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dirty != widget.dirty) _report();
  }

  void _report() {
    final dirty = widget.dirty;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.dirty = dirty;
    });
  }

  @override
  void dispose() {
    // A page that goes away never leaves its frame locked.
    final scope = _scope;
    if (scope != null && scope.dirty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => scope.dirty = false);
    }
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: widget.child),
        Positioned(
          left: widget.inset.left,
          right: widget.inset.right,
          bottom: 20 + widget.inset.bottom,
          child: Align(
            alignment: widget.alignment,
            child: ListenableBuilder(
              listenable: _controller,
              builder: (context, _) => UnsavedChangesBar(
                visible: widget.dirty,
                warning: _controller.warning,
                shakes: _controller.shakes,
                saving: widget.saving,
                width: widget.barWidth,
                onReset: widget.onReset,
                onSave: widget.onSave,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Which of the reference client's two unsaved-changes bars to draw.
enum UnsavedChangesBarStyle {
  /// Server, channel and role settings: 700×54, "Careful – you have unsaved
  /// changes!", a text Reset and a green Save Changes.
  settings,

  /// The Edit Profile modal: 500×50, 12 px corners, "Don't forget to save
  /// your changes!", a grey Reset and an accent Save.
  profile,
}

/// The reference client's "Careful — you have unsaved changes!" bar: 700×54,
/// `#2C2D32`, 8 px corners, a hairline border and a soft shadow; Reset as a
/// link-blue text button and a green "Save Changes". It slides up when
/// [visible], turns `#4F000F` with a red border while [warning], and shakes
/// whenever [shakes] changes.
class UnsavedChangesBar extends StatelessWidget {
  const UnsavedChangesBar({
    super.key,
    required this.visible,
    required this.onReset,
    required this.onSave,
    this.warning = false,
    this.shakes = 0,
    this.saving = false,
    this.width = 700,
    this.style = UnsavedChangesBarStyle.settings,
  });

  final bool visible;
  final bool warning;
  final int shakes;
  final bool saving;
  final double width;
  final UnsavedChangesBarStyle style;
  final VoidCallback onReset;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final profile = style == UnsavedChangesBarStyle.profile;
    final bar = AnimatedContainer(
      key: const Key('unsaved-changes-bar'),
      duration: const Duration(milliseconds: 200),
      height: profile ? 50 : 54,
      constraints: BoxConstraints(maxWidth: profile ? 500 : width),
      padding: profile
          ? const EdgeInsets.fromLTRB(12, 9, 9, 9)
          : const EdgeInsets.fromLTRB(16, 10, 10, 10),
      decoration: BoxDecoration(
        color: warning ? const Color(0xFF4F000F) : const Color(0xFF2C2D32),
        borderRadius: BorderRadius.circular(profile ? 12 : 8),
        border: Border.all(
          color: warning
              ? colors.red
              : const Color(0xFF94949C).withValues(alpha: 0.12),
        ),
        boxShadow: [
          profile
              ? const BoxShadow(
                  color: Color(0x3D000000),
                  blurRadius: 24,
                  offset: Offset(0, 12),
                )
              : const BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 10,
                  offset: Offset(0, 2),
                ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              profile
                  ? 'Don’t forget to save your changes!'
                  : 'Careful – you have unsaved changes!',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: profile ? 14 : 16,
                fontWeight: profile ? FontWeight.w400 : FontWeight.w500,
                height: (profile ? 18 : 20) / (profile ? 14 : 16),
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 10),
          _BarButton(
            key: const Key('unsaved-changes-reset'),
            label: 'Reset',
            onTap: saving ? null : onReset,
            background: profile
                ? const Color(0xFF94949C).withValues(alpha: 0.12)
                : null,
            foreground: profile ? Colors.white : const Color(0xFF8CA0FD),
          ),
          const SizedBox(width: 8),
          _BarButton(
            key: const Key('unsaved-changes-save'),
            label: profile ? 'Save' : 'Save Changes',
            onTap: saving ? null : onSave,
            background: profile ? colors.primary : const Color(0xFF008545),
            foreground: Colors.white,
            busy: saving,
          ),
        ],
      ),
    );
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        offset: visible ? Offset.zero : const Offset(0, 1.6),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: visible ? 1 : 0,
          child: TweenAnimationBuilder<double>(
            key: ValueKey(shakes),
            tween: Tween(begin: shakes == 0 ? 1 : 0, end: 1),
            duration: const Duration(milliseconds: 400),
            builder: (context, t, child) => Transform.translate(
              // Three damped swings, like the reference client's nudge.
              offset: Offset(math.sin(t * math.pi * 6) * 8 * (1 - t), 0),
              child: child,
            ),
            child: bar,
          ),
        ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    super.key,
    required this.label,
    required this.onTap,
    required this.foreground,
    this.background,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onTap;
  final Color foreground;
  final Color? background;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background ?? Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 32,
          constraints: const BoxConstraints(minWidth: 60),
          padding: const EdgeInsets.symmetric(horizontal: 11),
          alignment: Alignment.center,
          child: busy
              ? SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: foreground,
                  ),
                )
              : Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 18 / 14,
                    color: foreground,
                  ),
                ),
        ),
      ),
    );
  }
}
