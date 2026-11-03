# phosphor_flutter (local fork)

Vendored from [phosphor_flutter 2.1.0](https://pub.dev/packages/phosphor_flutter)
(MIT, see `LICENSE`), for two reasons:

- upstream declares its icons as `PhosphorIconData extends IconData`, and
  `IconData` is a `final` class on the Flutter this app builds with, so the
  package no longer compiles. The generated constants are rewritten as plain
  `IconData(codePoint, fontFamily: 'Phosphor<Style>', fontPackage:
  'phosphor_flutter', matchTextDirection: true)`; the `PhosphorIcon` widget
  and the duotone helpers that depended on the subclass are dropped.
- only the **Fill** and **Bold** weights are used (`lib/theme/app_icons.dart`),
  so the other four fonts (about 2 MB) are left out of the bundle.

The font files are upstream's, unchanged. To update, re-run
`tool/vendor_phosphor.py` against a newer upstream release.
