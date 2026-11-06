import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';

/// The reference client's plain slider: a 4 px rounded track, the filled
/// part in the accent colour, a 16 px white knob, no halo or value bubble.
/// Used by the soundboard volume popover and the "Upload a Sound" dialog.
class AccordSlider extends StatelessWidget {
  const AccordSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    this.min = 0.0,
    this.max = 1.0,
    this.semanticLabel,
  });

  final double value;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;
  final double min;
  final double max;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 4,
        padding: EdgeInsets.zero,
        activeTrackColor: colors.primary,
        inactiveTrackColor: const Color(0xFF474851),
        thumbColor: Colors.white,
        overlayShape: SliderComponentShape.noOverlay,
        thumbShape: const RoundSliderThumbShape(
          enabledThumbRadius: 8,
          elevation: 0,
          pressedElevation: 0,
        ),
        trackShape: const RoundedRectSliderTrackShape(),
        showValueIndicator: ShowValueIndicator.never,
      ),
      child: SizedBox(
        height: 16,
        child: Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
          semanticFormatterCallback: semanticLabel == null
              ? null
              : (v) =>
                    '$semanticLabel ${((v - min) / (max - min) * 100).round()}%',
        ),
      ),
    );
  }
}
