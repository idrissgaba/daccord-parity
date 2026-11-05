import 'package:bonfire/features/messaging/views/message_pane/message_pane.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Ctrl+B / I / U wrap the selection and keep it selected', () {
    const value = TextEditingValue(
      text: 'say hello now',
      selection: TextSelection(baseOffset: 4, extentOffset: 9),
    );
    final bold = wrapSelection(value, '**')!;
    expect(bold.text, 'say **hello** now');
    expect(bold.selection.textInside(bold.text), 'hello');
    expect(wrapSelection(value, '*')!.text, 'say *hello* now');
    expect(wrapSelection(value, '__')!.text, 'say __hello__ now');
  });

  test('nothing selected, nothing wrapped', () {
    const value = TextEditingValue(
      text: 'abc',
      selection: TextSelection.collapsed(offset: 1),
    );
    expect(wrapSelection(value, '**'), isNull);
  });

  test('no composer mounted, no shortcut taken', () {
    expect(requestComposerShortcut(ComposerShortcut.emoji), isFalse);
  });
}
