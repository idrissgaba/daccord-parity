import 'package:flutter/material.dart';

@immutable
class BonfireThemeExtension extends ThemeExtension<BonfireThemeExtension> {
  static BonfireThemeExtension of(BuildContext context) =>
      Theme.of(context).extension<BonfireThemeExtension>()!;

  const BonfireThemeExtension({
    required this.foreground,
    required this.background,
    required this.dirtyWhite,
    required this.gray,
    required this.darkGray,
    required this.primary,
    required this.red,
    required this.green,
    required this.yellow,
    Color? raised,
    Color? interactive,
  }) : _raised = raised,
       _interactive = interactive;

  final Color foreground;
  final Color background;
  final Color dirtyWhite;
  final Color gray;
  final Color darkGray;
  final Color primary;
  final Color red;
  final Color green;
  final Color yellow;

  final Color? _raised;
  final Color? _interactive;

  /// A panel sitting on top of [foreground]: the user panel, the composer, a
  /// card. Falls back to a slightly lifted [foreground] for presets that don't
  /// define one.
  Color get raised => _raised ?? Color.lerp(foreground, dirtyWhite, 0.06)!;

  /// Secondary icons and controls: lighter than [gray] (muted text) but not
  /// high-emphasis. Falls back to [gray].
  Color get interactive => _interactive ?? gray;

  /// 1 px separators and borders drawn on any of the three surfaces.
  Color get hairline => interactive.withValues(alpha: 0.12);

  /// The grey the row overlays are made of: between muted text and icons.
  Color get _overlayBase => Color.lerp(gray, interactive, 0.5)!;

  /// The translucent fill behind a hovered row, tile or button.
  Color get hover => _overlayBase.withValues(alpha: 0.1);

  /// The translucent fill behind the selected row (channel, member, tab).
  Color get selection => _overlayBase.withValues(alpha: 0.2);

  @override
  BonfireThemeExtension copyWith({
    Color? foreground,
    Color? background,
    Color? dirtyWhite,
    Color? gray,
    Color? darkGray,
    Color? primary,
    Color? red,
    Color? green,
    Color? yellow,
    Color? raised,
    Color? interactive,
  }) {
    return BonfireThemeExtension(
      foreground: foreground ?? this.foreground,
      background: background ?? this.background,
      dirtyWhite: dirtyWhite ?? this.dirtyWhite,
      gray: gray ?? this.gray,
      darkGray: darkGray ?? this.darkGray,
      primary: primary ?? this.primary,
      red: red ?? this.red,
      green: green ?? this.green,
      yellow: yellow ?? this.yellow,
      raised: raised ?? _raised,
      interactive: interactive ?? _interactive,
    );
  }

  @override
  BonfireThemeExtension lerp(covariant BonfireThemeExtension? other, double t) {
    if (other == null) return this;
    return BonfireThemeExtension(
      foreground: Color.lerp(foreground, other.foreground, t)!,
      background: Color.lerp(background, other.background, t)!,
      dirtyWhite: Color.lerp(dirtyWhite, other.dirtyWhite, t)!,
      gray: Color.lerp(gray, other.gray, t)!,
      darkGray: Color.lerp(darkGray, other.darkGray, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      red: Color.lerp(red, other.red, t)!,
      green: Color.lerp(green, other.green, t)!,
      yellow: Color.lerp(yellow, other.yellow, t)!,
      raised: Color.lerp(raised, other.raised, t),
      interactive: Color.lerp(interactive, other.interactive, t),
    );
  }
}
