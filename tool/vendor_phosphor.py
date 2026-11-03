import os, re, shutil, sys
src = sys.argv[1]  # pub cache phosphor_flutter-2.1.0
dst = sys.argv[2]  # packages/phosphor_flutter
if os.path.exists(dst):
    shutil.rmtree(dst)
os.makedirs(os.path.join(dst, 'lib', 'src'))
os.makedirs(os.path.join(dst, 'lib', 'fonts'))
shutil.copy(os.path.join(src, 'LICENSE'), os.path.join(dst, 'LICENSE'))
for style, fname in (('Fill', 'Phosphor-Fill.ttf'), ('Bold', 'Phosphor-Bold.ttf')):
    shutil.copy(os.path.join(src, 'lib', 'fonts', fname), os.path.join(dst, 'lib', 'fonts', fname))
    s = open(os.path.join(src, 'lib', 'src', f'phosphor_icons_{style.lower()}.dart'), encoding='utf-8').read()
    s = s.replace("import 'package:phosphor_flutter/src/phosphor_icon_data.dart';\n", '')
    s = re.sub(
        r"PhosphorFlatIconData\((0x[0-9a-f]+), '%s'\)" % style,
        r"IconData(\1, fontFamily: 'Phosphor%s', fontPackage: 'phosphor_flutter', matchTextDirection: true)" % style,
        s)
    assert 'PhosphorFlatIconData' not in s
    open(os.path.join(dst, 'lib', 'src', f'phosphor_icons_{style.lower()}.dart'), 'w', encoding='utf-8', newline='\n').write(s)
open(os.path.join(dst, 'lib', 'phosphor_flutter.dart'), 'w', encoding='utf-8', newline='\n').write(
"""/// Phosphor icons (MIT, https://phosphoricons.com) as plain Flutter
/// [IconData] constants: the Fill and Bold weights only.
library;

export 'src/phosphor_icons_bold.dart';
export 'src/phosphor_icons_fill.dart';
""")
open(os.path.join(dst, 'pubspec.yaml'), 'w', encoding='utf-8', newline='\n').write(
"""name: phosphor_flutter
description: Phosphor icons (Fill and Bold weights) as plain IconData constants. Local fork, see FORK.md.
version: 2.1.0+daccord.1
publish_to: none

environment:
  sdk: ^3.10.0
  flutter: ">=3.10.0"

dependencies:
  flutter:
    sdk: flutter

flutter:
  fonts:
    - family: PhosphorBold
      fonts:
        - asset: lib/fonts/Phosphor-Bold.ttf
          weight: 400
    - family: PhosphorFill
      fonts:
        - asset: lib/fonts/Phosphor-Fill.ttf
          weight: 400
""")
open(os.path.join(dst, 'FORK.md'), 'w', encoding='utf-8', newline='\n').write(
"""# phosphor_flutter (local fork)

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
""")
print('vendored', dst)
