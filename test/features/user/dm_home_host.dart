import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/user/views/accord_direct_messages.dart';
import 'package:bonfire/features/voice/views/voice_view.dart'
    show voiceViewExpanded;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The direct-messages home as the home screen lays it out — the conversation
/// column beside the Friends page or the open conversation — under an
/// "open dms" button that opens it the way the rail and every "Message"
/// action do ([showAccordDirectMessages]).
///
/// Like the home screen, a full-screen call hides everything around the
/// conversation while keeping each widget in its place.
///
/// [dmHome] is a single app-wide instance: call [resetDmHomeAfter] in each
/// test that opens it.
class DmHomeHost extends StatelessWidget {
  const DmHomeHost({super.key, this.sidebarOnly = false, this.initialChannel});

  /// The conversation "open dms" opens on; none = the Friends page.
  final AccordChannel? initialChannel;

  /// Only the conversation column, for phone widths where the home screen
  /// shows one pane at a time.
  final bool sidebarOnly;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: ValueListenableBuilder<bool>(
      valueListenable: voiceViewExpanded,
      builder: (context, expanded, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (expanded)
            const SizedBox.shrink()
          else
            TextButton(
              onPressed: () => showAccordDirectMessages(
                context,
                initialChannel: initialChannel,
              ),
              child: const Text('open dms'),
            ),
          Expanded(
            child: sidebarOnly
                ? const DmHomeSidebar()
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (expanded)
                        const SizedBox.shrink()
                      else
                        const SizedBox(width: 240, child: DmHomeSidebar()),
                      const Expanded(
                        key: ValueKey('dm-home-main'),
                        child: DmHomeMain(),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    ),
  );
}

/// Puts the shared [dmHome] back to its initial state when the test ends.
void resetDmHomeAfter() => addTearDown(dmHome.reset);
