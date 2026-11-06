part of '../soundboard_picker.dart';

/// The speaker at the right of the search field. Clicking it opens the
/// reference client's small "Soundboard Volume" card (156×76 on a raised
/// surface) beside it; the slider sets how loud sounds are for us only — the
/// same value as Settings › Voice & Video › Soundboard.
class _VolumeButton extends ConsumerStatefulWidget {
  const _VolumeButton();

  @override
  ConsumerState<_VolumeButton> createState() => _VolumeButtonState();
}

class _VolumeButtonState extends ConsumerState<_VolumeButton> {
  final _portal = OverlayPortalController();
  final _link = LayerLink();

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final volume = ref.watch(
      settingsControllerProvider.select((s) => s.soundboardVolume),
    );
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (_) => CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.centerRight,
          offset: const Offset(-18, -3),
          child: Align(
            alignment: Alignment.topLeft,
            child: TapRegion(
              groupId: _link,
              onTapOutside: (_) => _portal.hide(),
              child: _VolumeCard(
                volume: volume,
                onChanged: ref
                    .read(settingsControllerProvider.notifier)
                    .setSoundboardVolume,
              ),
            ),
          ),
        ),
        child: TapRegion(
          groupId: _link,
          child: Tooltip(
            message: _portal.isShowing ? '' : 'Soundboard Volume',
            child: InkResponse(
              key: const Key('soundboard-volume'),
              onTap: () => setState(_portal.toggle),
              radius: 16,
              hoverColor: Colors.transparent,
              highlightColor: Colors.transparent,
              splashColor: Colors.transparent,
              child: SizedBox(
                width: 24,
                height: 27,
                child: Icon(
                  volume == 0 ? AppIcons.volumeOff : AppIcons.volumeUp,
                  size: 24,
                  color: colors.interactive,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VolumeCard extends StatelessWidget {
  const _VolumeCard({required this.volume, required this.onChanged});

  final double volume;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Material(
      key: const Key('soundboard-volume-card'),
      color: const Color(0xFF28282D),
      borderRadius: BorderRadius.circular(8),
      elevation: 0,
      child: Container(
        constraints: const BoxConstraints(minWidth: 156),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.hairline),
          boxShadow: const [
            BoxShadow(
              color: Color(0x3D000000),
              blurRadius: 24,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Soundboard Volume',
                maxLines: 1,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 18 / 14,
                  color: colors.dirtyWhite,
                ),
              ),
              const SizedBox(height: 8),
              AccordSlider(
                value: volume,
                onChanged: onChanged,
                semanticLabel: 'Soundboard volume',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
