import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/soundboard/controllers/soundboard_activity.dart';
import 'package:bonfire/features/soundboard/views/sound_emoji.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The user IDs playing a soundboard sound right now. Call tiles and channel
/// rows add them to the speaking set: the reference client rings whoever
/// plays a sound as if they spoke.
Set<String> watchSoundboardPlayers(WidgetRef ref) => ref.watch(
  soundboardActivityControllerProvider.select((a) => a.keys.toSet()),
);

/// The reference client's cue on the avatar of whoever plays a soundboard
/// sound: the sound's emoji, a little larger than the avatar, rises from
/// below it,
/// overshoots, settles over the avatar's lower half while the clip lasts,
/// then sinks away. Sized by [size] (the avatar's diameter); place it centred
/// on the avatar in a `Stack` that does not clip.
class SoundboardAvatarCue extends ConsumerStatefulWidget {
  const SoundboardAvatarCue({
    super.key,
    required this.userId,
    required this.size,
  });

  final String userId;
  final double size;

  @override
  ConsumerState<SoundboardAvatarCue> createState() =>
      _SoundboardAvatarCueState();
}

class _SoundboardAvatarCueState extends ConsumerState<SoundboardAvatarCue>
    with TickerProviderStateMixin {
  late final AnimationController _enter;
  late final AnimationController _exit;

  /// Vertical offset of the emoji, in avatar diameters, while it enters:
  /// from below the avatar up past its top, then down to rest.
  static final _rise = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 0.9,
        end: -0.3,
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 60,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: -0.3,
        end: 0.05,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 40,
    ),
  ]);

  AccordSound? _sound;
  int? _token;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _exit = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    final current = ref.read(
      soundboardActivityControllerProvider,
    )[widget.userId];
    if (current != null) _start(current);
  }

  @override
  void dispose() {
    _enter.dispose();
    _exit.dispose();
    super.dispose();
  }

  void _start(SoundboardActivity activity) {
    _token = activity.token;
    _sound = activity.sound;
    _exit.value = 0;
    _enter.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      soundboardActivityControllerProvider.select((a) => a[widget.userId]),
      (previous, next) {
        if (next != null && next.token != _token) {
          setState(() => _start(next));
        } else if (next == null && _token != null) {
          _token = null;
          _exit.forward(from: 0).whenComplete(() {
            if (mounted && _token == null) setState(() => _sound = null);
          });
        }
      },
    );
    final sound = _sound;
    if (sound == null) return const SizedBox.shrink();
    final size = widget.size;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: Listenable.merge([_enter, _exit]),
        builder: (context, child) {
          final rest = _rise.evaluate(_enter);
          final dy = rest + (0.9 - rest) * Curves.easeIn.transform(_exit.value);
          return Opacity(
            opacity: (_enter.value * 4).clamp(0.0, 1.0) * (1 - _exit.value),
            child: Transform.translate(
              offset: Offset(0, dy * size),
              child: child,
            ),
          );
        },
        child: SoundEmoji(
          key: const Key('soundboard-avatar-cue'),
          sound: sound,
          serverKey: ref.watchActiveServerKey() ?? '',
          // The glyph about 1.25× the avatar, as in the reference animation
          // (a Unicode glyph fills ~86 % of its box).
          size: size * 1.45,
        ),
      ),
    );
  }
}
