import 'dart:async';
import 'dart:math' as math;

import 'package:bonfire/features/notifications/services/sound.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/settings/views/accord_settings_screen.dart';
import 'package:bonfire/features/settings/views/settings_anchors.dart';
import 'package:bonfire/features/settings/views/settings_sound_row.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/features/voice/services/global_key_watcher.dart';
import 'package:bonfire/features/voice/services/mic_test.dart';
import 'package:bonfire/features/voice/utils/afk_logic.dart';
import 'package:bonfire/features/voice/utils/audio_output_support.dart';
import 'package:bonfire/shared/app_info.dart';
import 'package:bonfire/shared/components/accord_slider.dart';
import 'package:bonfire/shared/utils/external_url.dart';
import 'package:bonfire/shared/components/settings_controls.dart';
import 'package:bonfire/theme/app_icons.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';

/// Opens Settings › Voice & Video.
Future<void> showVoiceSettings(BuildContext context) =>
    showUserSettings(context, page: SettingsPage.voiceVideo);

/// The voice sounds the reference client lists first, then the rest behind
/// "Show N more sounds".
const List<String> _kVoiceSoundsFirst = ['deafen', 'undeafen', 'mute', 'unmute'];
const List<String> _kVoiceSoundsMore = [
  'voice_join',
  'voice_leave',
  'peer_join',
  'peer_leave',
  'stream_start',
  'stream_stop',
  'ring_outgoing',
];

/// Settings › Voice & Video, laid out as the reference client's page: Voice
/// (microphone and speaker side by side, their volumes, Mic Test, Input
/// Profile, Input Sensitivity, noise suppression, echo cancellation,
/// push-to-talk, advanced voice settings), Camera (preview, device,
/// quality), Streaming, Sounds, Soundboard and Advanced. Each section is an
/// anchor of the settings sidebar.
class VoiceVideoSettingsPage extends ConsumerStatefulWidget {
  const VoiceVideoSettingsPage({super.key, this.onOpenNotifications});

  /// "Related Settings › Notifications".
  final VoidCallback? onOpenNotifications;

  @override
  ConsumerState<VoiceVideoSettingsPage> createState() =>
      _VoiceVideoSettingsPageState();
}

class _VoiceVideoSettingsPageState
    extends ConsumerState<VoiceVideoSettingsPage> {
  List<MediaDevice> _audioInputs = const [];
  List<MediaDevice> _audioOutputs = const [];
  List<MediaDevice> _videoInputs = const [];
  bool _loadingDevices = true;

  MicTest? _micTest;
  bool _micStarting = false;
  String? _micError;

  /// The call's microphone level while connected (the meter's source then).
  _CallLevel? _callLevel;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  @override
  void dispose() {
    _micTest?.stop();
    _callLevel?.dispose();
    super.dispose();
  }

  ValueListenable<double>? _levelSource(bool connected) {
    if (!connected) {
      _callLevel?.dispose();
      _callLevel = null;
      return _micTest?.level;
    }
    return _callLevel ??= _CallLevel(ref.read(voiceControllerProvider.notifier));
  }

  Future<void> _loadDevices() async {
    try {
      final inputs = await Hardware.instance.audioInputs();
      final outputs = await Hardware.instance.audioOutputs();
      final cameras = await Hardware.instance.videoInputs();
      if (!mounted) return;
      setState(() {
        _audioInputs = inputs;
        _audioOutputs = outputs;
        _videoInputs = cameras;
        _loadingDevices = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingDevices = false);
    }
  }

  Future<void> _toggleMicTest() async {
    final running = _micTest;
    if (running != null) {
      setState(() => _micTest = null);
      await running.stop();
      return;
    }
    final settings = ref.read(settingsControllerProvider);
    setState(() {
      _micStarting = true;
      _micError = null;
    });
    try {
      final test = await MicTest.start(
        deviceId: settings.audioInputDeviceId,
        noiseSuppression: settings.voiceNoiseSuppression,
        echoCancellation: settings.voiceEchoCancellation,
        autoGainControl: settings.voiceAutoGainControl,
      );
      if (!mounted) {
        await test.stop();
        return;
      }
      setState(() {
        _micTest = test;
        _micStarting = false;
      });
      // Device names appear once the browser has granted the microphone.
      unawaited(_loadDevices());
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _micStarting = false;
        _micError =
            'You do not have any input devices enabled. You must grant '
            'Daccord access to your microphone in order to be able to '
            'observe input sensitivity.';
      });
    }
  }

  /// Restarts a running test so it uses the newly chosen device or filters.
  Future<void> _restartMicTest() async {
    if (_micTest == null) return;
    await _toggleMicTest();
    if (mounted) await _toggleMicTest();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    final connected = ref.watch(
      voiceControllerProvider.select((v) => v.isConnected),
    );
    final cameraInCall = ref.watch(
      voiceControllerProvider.select((v) => v.selfVideo),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsAnchor(
          id: 'voice',
          child: _VoiceSection(
            settings: settings,
            controller: controller,
            audioInputs: _audioInputs,
            audioOutputs: _audioOutputs,
            loadingDevices: _loadingDevices,
            connected: connected,
            micTest: _micTest,
            level: _levelSource(connected),
            micStarting: _micStarting,
            micError: _micError,
            onToggleMicTest: _toggleMicTest,
            onRestartMicTest: _restartMicTest,
          ),
        ),
        const SettingsDivider(),
        SettingsAnchor(
          id: 'camera',
          child: _CameraSection(
            settings: settings,
            controller: controller,
            cameras: _videoInputs,
            loadingDevices: _loadingDevices,
            cameraInCall: cameraInCall,
          ),
        ),
        const SettingsDivider(),
        SettingsAnchor(
          id: 'streaming',
          child: _StreamingSection(settings: settings, controller: controller),
        ),
        const SettingsDivider(),
        SettingsAnchor(
          id: 'voice-sounds',
          child: _SoundsSection(onOpenNotifications: widget.onOpenNotifications),
        ),
        const SettingsDivider(),
        SettingsAnchor(
          id: 'soundboard',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SettingsSectionTitle('Soundboard'),
              _LabelledSlider(
                key: const Key('soundboard-volume-setting'),
                label: 'Soundboard Volume',
                description: 'Control how loud sounds are for you personally.',
                value: settings.soundboardVolume,
                onChanged: controller.setSoundboardVolume,
              ),
            ],
          ),
        ),
        const SettingsDivider(),
        SettingsAnchor(
          id: 'voice-advanced',
          child: _AdvancedSection(settings: settings, controller: controller),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Voice
// ---------------------------------------------------------------------------

class _VoiceSection extends StatelessWidget {
  const _VoiceSection({
    required this.settings,
    required this.controller,
    required this.audioInputs,
    required this.audioOutputs,
    required this.loadingDevices,
    required this.connected,
    required this.micTest,
    required this.level,
    required this.micStarting,
    required this.micError,
    required this.onToggleMicTest,
    required this.onRestartMicTest,
  });

  final AccordSettings settings;
  final SettingsController controller;
  final List<MediaDevice> audioInputs;
  final List<MediaDevice> audioOutputs;
  final bool loadingDevices;
  final bool connected;
  final MicTest? micTest;
  final ValueListenable<double>? level;
  final bool micStarting;
  final String? micError;
  final VoidCallback onToggleMicTest;
  final VoidCallback onRestartMicTest;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final profile = settings.voiceInputProfile;
    final testing = micTest != null;
    // In a call the meter follows the call's own microphone.
    final levelSource = level;

    Widget twoColumns(Widget left, Widget right) => LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 480) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [left, const SizedBox(height: 24), right],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: 16),
            Expanded(child: right),
          ],
        );
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsSectionTitle('Voice'),
        twoColumns(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SettingsFieldLabel('Microphone'),
              _DeviceSelect(
                key: const Key('audio-input-dropdown'),
                icon: AppIcons.micNone,
                devices: audioInputs,
                loading: loadingDevices,
                selectedId: settings.audioInputDeviceId,
                fallbackLabel: 'Microphone',
                onChanged: (id) {
                  controller.setAudioInputDevice(id);
                  onRestartMicTest();
                },
              ),
            ],
          ),
          canPickAudioOutputDevice
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SettingsFieldLabel('Speaker'),
                    _DeviceSelect(
                      key: const Key('audio-output-dropdown'),
                      icon: AppIcons.headset,
                      devices: audioOutputs,
                      loading: loadingDevices,
                      selectedId: settings.audioOutputDeviceId,
                      fallbackLabel: 'Speaker',
                      onChanged: controller.setAudioOutputDevice,
                    ),
                  ],
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: 24),
        twoColumns(
          _LabelledSlider(
            key: const Key('input-volume-slider'),
            label: 'Microphone Volume',
            value: settings.inputVolume / 200,
            onChanged: (v) => controller.setInputVolume((v * 200).round()),
          ),
          _LabelledSlider(
            key: const Key('output-volume-slider'),
            label: 'Speaker Volume',
            value: settings.outputVolume / 200,
            onChanged: (v) => controller.setOutputVolume((v * 200).round()),
          ),
        ),
        const SizedBox(height: 32),
        Row(
          children: [
            SizedBox(
              width: 117,
              child: AccordButton(
                key: const Key('mic-test-button'),
                label: testing ? 'Stop Testing' : 'Mic Test',
                onPressed: connected || micStarting ? null : onToggleMicTest,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _MicTestMeter(
                level: levelSource,
                threshold: settings.speakingThreshold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 36),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Need help? Check out our '),
              TextSpan(
                text: 'troubleshooting guide',
                style: const TextStyle(color: Color(0xFF4D96EE)),
                recognizer: TapGestureRecognizer()
                  ..onTap = () => openTrustedUrl(kDaccordHelpUrl),
              ),
              const TextSpan(text: '.'),
            ],
          ),
          style: SettingsText.description(colors),
        ),
        const SettingsDivider(top: 50, bottom: 52),
        const _FieldHeading('Input Profile'),
        const SizedBox(height: 16),
        for (final (value, label, description) in const [
          (
            VoiceInputProfile.voiceIsolation,
            'Voice Isolation',
            'Just your beautiful voice: let Daccord cut through the noise',
          ),
          (
            VoiceInputProfile.studio,
            'Studio',
            'Pure audio: open mic with no processing',
          ),
          (
            VoiceInputProfile.custom,
            'Custom',
            'Advanced mode: give me all the buttons and dials!',
          ),
        ]) ...[
          AccordRadioRow(
            key: Key('input-profile-${value.name}'),
            label: label,
            description: description,
            selected: profile == value,
            onTap: () {
              controller.setVoiceInputProfile(value);
              onRestartMicTest();
            },
          ),
          const SizedBox(height: 14),
        ],
        const SizedBox(height: 24),
        const _FieldHeading(
          'Input Sensitivity',
          'Controls how much sound Daccord transmits from your mic.',
        ),
        const SizedBox(height: 16),
        _SensitivitySlider(
          value: settings.inputSensitivity / 100,
          level: levelSource,
          onChanged: (v) => controller.setInputSensitivity((v * 100).round()),
        ),
        if (micError != null) ...[
          const SizedBox(height: 16),
          _WarningBox(micError!),
        ],
        if (profile == VoiceInputProfile.custom) ...[
          const SizedBox(height: 32),
          SettingsRow(
            label: 'Noise Suppression',
            description: 'Reduces background noise from your mic.',
            trailing: SizedBox(
              width: 205,
              child: AccordSelect<bool>(
                key: const Key('noise-suppression-select'),
                value: settings.voiceNoiseSuppression,
                options: const [
                  AccordSelectOption(true, 'Standard'),
                  AccordSelectOption(false, 'None'),
                ],
                onChanged: (v) {
                  controller.setVoiceNoiseSuppression(v);
                  onRestartMicTest();
                },
              ),
            ),
          ),
          const SizedBox(height: 32),
          SettingsSwitchRow(
            key: const Key('echo-cancellation-switch'),
            label: 'Echo Cancellation',
            value: settings.voiceEchoCancellation,
            onChanged: (v) {
              controller.setVoiceEchoCancellation(v);
              onRestartMicTest();
            },
          ),
        ],
        const SizedBox(height: 32),
        SettingsSwitchRow(
          key: const Key('push-to-talk-switch'),
          label: 'Push-to-talk',
          description: GlobalKeyWatcher().supported
              ? 'Your mic only transmits while you hold the key — even while '
                    'another app has focus — or the talk button in the voice '
                    'panel.'
              : 'Your mic only transmits while you hold the key (with the app '
                    'focused) or the talk button in the voice panel.',
          value: settings.pushToTalk,
          onChanged: controller.setPushToTalk,
        ),
        if (settings.pushToTalk) ...[
          const SizedBox(height: 32),
          SettingsRow(
            key: const Key('push-to-talk-key'),
            label: 'Shortcut',
            descriptionWidget: Text(settings.pushToTalkKeyLabel),
            trailing: AccordButton(
              label: 'Edit Keybind',
              tone: AccordButtonTone.secondary,
              onPressed: () async {
                final key = await _captureKey(context);
                if (key != null) controller.setPushToTalkKey(key.$1, key.$2);
              },
            ),
          ),
        ],
        const SizedBox(height: 32),
        SettingsExpander(
          key: const Key('advanced-voice-expander'),
          label: 'Show Advanced Voice Settings',
          description: 'Automatic Gain Control and High Quality Audio',
          children: [
            SettingsSwitchRow(
              key: const Key('auto-gain-switch'),
              label: 'Automatic Gain Control',
              description: 'Keeps your voice at a steady level.',
              value: settings.voiceAutoGainControl,
              onChanged: profile == VoiceInputProfile.custom
                  ? (v) {
                      controller.setVoiceAutoGainControl(v);
                      onRestartMicTest();
                    }
                  : null,
            ),
            SettingsSwitchRow(
              key: const Key('high-quality-audio-switch'),
              label: 'High Quality Audio',
              description:
                  'Sends your microphone at 128 kbps instead of 96 — for '
                  'music or instruments. Choose the Studio profile for the '
                  'cleanest result. Applies when you next join a voice '
                  'channel.',
              value: settings.voiceHighQualityAudio,
              onChanged: controller.setVoiceHighQualityAudio,
            ),
          ],
        ),
      ],
    );
  }
}

/// The call's microphone level as a listenable, polled like the call meter.
class _CallLevel extends ChangeNotifier implements ValueListenable<double> {
  _CallLevel(this._voice) {
    _timer = Timer.periodic(const Duration(milliseconds: 70), (_) {
      final next = _voice.localAudioLevel;
      if ((next - _value).abs() > 0.002) {
        _value = next;
        notifyListeners();
      }
    });
  }

  final VoiceController _voice;
  late final Timer _timer;
  double _value = 0;

  @override
  double get value => _value;

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }
}

/// A widget that repaints with an input level.
abstract class _LevelWidget extends StatefulWidget {
  const _LevelWidget({required this.level});

  final ValueListenable<double>? level;
}

abstract class _LevelState<T extends _LevelWidget> extends State<T> {
  double _level = 0;

  @override
  void initState() {
    super.initState();
    widget.level?.addListener(_onLevel);
  }

  @override
  void didUpdateWidget(covariant T oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.level != widget.level) {
      oldWidget.level?.removeListener(_onLevel);
      widget.level?.addListener(_onLevel);
      _level = widget.level?.value ?? 0;
    }
  }

  @override
  void dispose() {
    widget.level?.removeListener(_onLevel);
    super.dispose();
  }

  void _onLevel() {
    if (mounted) setState(() => _level = widget.level?.value ?? 0);
  }

  /// Perceptual (sqrt) mapping so quiet speech still visibly moves the bar.
  double get displayLevel => math.sqrt(_level.clamp(0.0, 1.0));
}

/// The reference client's Mic Test meter: a 28 px row of 4 px bars, lit
/// green as far as the input reaches.
class _MicTestMeter extends _LevelWidget {
  const _MicTestMeter({required super.level, required this.threshold});

  final double threshold;

  @override
  State<_MicTestMeter> createState() => _MicTestMeterState();
}

class _MicTestMeterState extends _LevelState<_MicTestMeter> {
  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return SizedBox(
      key: const Key('mic-test-meter'),
      height: 28,
      child: CustomPaint(
        painter: _BarsPainter(
          level: displayLevel,
          lit: colors.green,
          unlit: const Color(0xFF46474F),
        ),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({required this.level, required this.lit, required this.unlit});

  final double level;
  final Color lit;
  final Color unlit;

  @override
  void paint(Canvas canvas, Size size) {
    const bar = 4.0;
    const gap = 4.0;
    final count = ((size.width + gap) / (bar + gap)).floor();
    final litCount = (level * count).round();
    final paint = Paint();
    for (var i = 0; i < count; i++) {
      paint.color = i < litCount ? lit : unlit;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * (bar + gap), 0, bar, size.height),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.level != level || old.lit != lit || old.unlit != unlit;
}

/// Input Sensitivity: a 4 px track, yellow below the threshold and green
/// above it, the live input drawn over it, and a white 16 px thumb.
class _SensitivitySlider extends _LevelWidget {
  const _SensitivitySlider({
    required this.value,
    required super.level,
    required this.onChanged,
  });

  /// 0–1 sensitivity (0 = most sensitive).
  final double value;
  final ValueChanged<double> onChanged;

  @override
  State<_SensitivitySlider> createState() => _SensitivitySliderState();
}

class _SensitivitySliderState extends _LevelState<_SensitivitySlider> {
  void _drag(Offset local, double width) =>
      widget.onChanged((local.dx / width).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Semantics(
          slider: true,
          label: 'Input sensitivity',
          value: '${(widget.value * 100).round()}%',
          child: GestureDetector(
            key: const Key('input-sensitivity-slider'),
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => _drag(d.localPosition, width),
            onHorizontalDragUpdate: (d) => _drag(d.localPosition, width),
            child: SizedBox(
              height: 24,
              child: CustomPaint(
                painter: _SensitivityPainter(
                  value: widget.value,
                  level: displayLevel,
                  below: const Color(0xFFFDB833),
                  above: colors.green,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SensitivityPainter extends CustomPainter {
  _SensitivityPainter({
    required this.value,
    required this.level,
    required this.below,
    required this.above,
  });

  final double value;
  final double level;
  final Color below;
  final Color above;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final x = value * size.width;
    final track = Paint()..strokeWidth = 4;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, y - 2, x, 4),
        const Radius.circular(2),
      ),
      track..color = below,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y - 2, size.width - x, 4),
        const Radius.circular(2),
      ),
      track..color = above,
    );
    if (level > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, y - 2, level * size.width, 4),
          const Radius.circular(2),
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.55),
      );
    }
    canvas
      ..drawCircle(Offset(x, y), 8, Paint()..color = Colors.white)
      ..drawCircle(
        Offset(x, y),
        8,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0x339696A0),
      );
  }

  @override
  bool shouldRepaint(_SensitivityPainter old) =>
      old.value != value || old.level != level;
}

class _WarningBox extends StatelessWidget {
  const _WarningBox(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Container(
      key: const Key('mic-test-warning'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFDB833).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFDB833)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(
              AppIcons.warningAmberRounded,
              size: 16,
              color: Color(0xFFFDB833),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: SettingsText.description(colors).copyWith(
                color: colors.dirtyWhite,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Camera
// ---------------------------------------------------------------------------

class _CameraSection extends StatefulWidget {
  const _CameraSection({
    required this.settings,
    required this.controller,
    required this.cameras,
    required this.loadingDevices,
    required this.cameraInCall,
  });

  final AccordSettings settings;
  final SettingsController controller;
  final List<MediaDevice> cameras;
  final bool loadingDevices;
  final bool cameraInCall;

  @override
  State<_CameraSection> createState() => _CameraSectionState();
}

class _CameraSectionState extends State<_CameraSection> {
  LocalVideoTrack? _preview;
  bool _starting = false;
  String? _error;

  @override
  void dispose() {
    _preview?.stop();
    super.dispose();
  }

  Future<void> _toggle() async {
    final running = _preview;
    if (running != null) {
      setState(() => _preview = null);
      await running.stop();
      return;
    }
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      final id = widget.settings.videoInputDeviceId;
      final track = await LocalVideoTrack.createCameraTrack(
        CameraCaptureOptions(deviceId: id.isEmpty ? null : id),
      );
      if (!mounted) {
        await track.stop();
        return;
      }
      setState(() {
        _preview = track;
        _starting = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _error = 'No camera could be opened.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final settings = widget.settings;
    final controller = widget.controller;
    final preview = _preview;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsSectionTitle('Camera'),
        Container(
          key: const Key('camera-preview'),
          height: 219,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0x339696A0)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (preview != null)
                Positioned.fill(
                  child: VideoTrackRenderer(
                    preview,
                    fit: VideoViewFit.cover,
                    mirrorMode: VideoViewMirrorMode.mirror,
                  ),
                ),
              if (preview == null)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AccordButton(
                      key: const Key('camera-test-button'),
                      label: 'Test Video',
                      onPressed: widget.cameraInCall || _starting
                          ? null
                          : _toggle,
                    ),
                    if (widget.cameraInCall || _error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _error ?? 'Your camera is already on in the call.',
                        style: SettingsText.description(colors),
                      ),
                    ],
                  ],
                )
              else
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: AccordButton(
                    label: 'Stop Video',
                    small: true,
                    tone: AccordButtonTone.secondary,
                    onPressed: _toggle,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const SettingsFieldLabel('Camera'),
        _DeviceSelect(
          key: const Key('camera-dropdown'),
          icon: AppIcons.cameraAlt,
          devices: widget.cameras,
          loading: widget.loadingDevices,
          selectedId: settings.videoInputDeviceId,
          fallbackLabel: 'Camera',
          onChanged: (id) async {
            controller.setVideoInputDevice(id);
            if (_preview != null) {
              await _toggle();
              if (mounted) await _toggle();
            }
          },
        ),
        const SizedBox(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SettingsFieldLabel('Resolution'),
                  AccordSelect<int>(
                    key: const Key('camera-resolution-dropdown'),
                    value: settings.videoResolution,
                    options: [
                      for (
                        var i = 0;
                        i < AccordSettings.videoResolutionLabels.length;
                        i++
                      )
                        AccordSelectOption(
                          i,
                          AccordSettings.videoResolutionLabels[i],
                        ),
                    ],
                    onChanged: controller.setVideoResolution,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SettingsFieldLabel('Frame Rate'),
                  AccordSelect<int>(
                    key: const Key('camera-fps-dropdown'),
                    value: settings.videoFps,
                    options: [
                      for (final fps in AccordSettings.videoFpsOptions)
                        AccordSelectOption(fps, '$fps fps'),
                    ],
                    onChanged: controller.setVideoFps,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Streaming
// ---------------------------------------------------------------------------

class _StreamingSection extends StatelessWidget {
  const _StreamingSection({required this.settings, required this.controller});

  final AccordSettings settings;
  final SettingsController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsSectionTitle('Streaming'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SettingsFieldLabel('Stream Resolution'),
                  AccordSelect<int>(
                    key: const Key('screen-share-resolution-dropdown'),
                    value: settings.screenShareResolution,
                    options: [
                      for (
                        var i = 0;
                        i < AccordSettings.screenShareResolutionLabels.length;
                        i++
                      )
                        AccordSelectOption(
                          i,
                          AccordSettings.screenShareResolutionLabels[i],
                        ),
                    ],
                    onChanged: controller.setScreenShareResolution,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SettingsFieldLabel('Frame Rate'),
                  AccordSelect<int>(
                    key: const Key('screen-share-fps-dropdown'),
                    value: settings.screenShareFps,
                    options: [
                      for (final fps in AccordSettings.screenShareFpsOptions)
                        AccordSelectOption(fps, '$fps fps'),
                    ],
                    onChanged: controller.setScreenShareFps,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
        SettingsRows(
          children: [
            SettingsSwitchRow(
              key: const Key('screen-share-audio-switch'),
              label: 'Share Audio',
              description:
                  'Sends the sound of the shared tab or screen too. Works in '
                  'Chrome and Edge on a computer; the desktop app shares '
                  'video only for now.',
              value: settings.screenShareAudio,
              onChanged: controller.setScreenShareAudio,
            ),
            SettingsSwitchRow(
              key: const Key('screen-share-motion-switch'),
              label: 'Prioritise Smooth Motion',
              description:
                  'Keeps the frame rate up on a slow connection by softening '
                  'the picture. Turn off to keep text sharp instead.',
              value: settings.screenShareMotionPriority,
              onChanged: controller.setScreenShareMotionPriority,
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sounds
// ---------------------------------------------------------------------------

class _SoundsSection extends StatelessWidget {
  const _SoundsSection({required this.onOpenNotifications});

  final VoidCallback? onOpenNotifications;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final labels = {for (final (n, l) in SoundManager.userSounds) n: l};
    final more = [
      for (final name in _kVoiceSoundsMore)
        if (labels[name] != null) name,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsSectionTitle('Sounds'),
        SettingsRows(
          children: [
            for (final name in _kVoiceSoundsFirst)
              if (labels[name] != null)
                SettingsSoundRow(name: name, label: labels[name]!),
            SettingsExpander(
              label: 'Show ${more.length} more sounds',
              description: 'Voice Connected, Voice Disconnected and more',
              children: [
                for (final name in more)
                  SettingsSoundRow(name: name, label: labels[name]!),
              ],
            ),
          ],
        ),
        if (onOpenNotifications != null) ...[
          const SizedBox(height: 32),
          Text(
            'Related Settings',
            style: SettingsText.label(colors).copyWith(color: colors.gray),
          ),
          const SizedBox(height: 16),
          SettingsLinkCard(
            icon: AppIcons.notificationsNone,
            title: 'Notifications',
            description:
                'Enable/disable sounds for new messages and incoming calls.',
            onTap: onOpenNotifications,
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Advanced
// ---------------------------------------------------------------------------

class _AdvancedSection extends StatelessWidget {
  const _AdvancedSection({required this.settings, required this.controller});

  final AccordSettings settings;
  final SettingsController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsSectionTitle('Advanced'),
        SettingsRows(
          children: [
            SettingsSwitchRow(
              key: const Key('relay-only-switch'),
              label: 'Relay-only Voice',
              description:
                  'Route voice, video and screen sharing through a TURN '
                  'relay. Requires server support and may increase latency. '
                  'Applies on your next connection; leave and rejoin to apply '
                  'now.',
              value: settings.voiceRelayOnly,
              onChanged: controller.setVoiceRelayOnly,
            ),
            SettingsRow(
              label: 'Mark Me Away After',
              description:
                  'While in a voice channel, with no input, mic activity or '
                  'window focus. Shown to other members as an idle status.',
              trailing: SizedBox(
                width: 205,
                child: AccordSelect<int>(
                  key: const Key('afk-timeout-dropdown'),
                  value:
                      afkTimeoutOptionsMinutes.contains(
                        settings.voiceAfkTimeoutMinutes,
                      )
                      ? settings.voiceAfkTimeoutMinutes
                      : defaultAfkTimeoutMinutes,
                  options: [
                    for (final minutes in afkTimeoutOptionsMinutes)
                      AccordSelectOption(minutes, afkTimeoutLabel(minutes)),
                  ],
                  onChanged: controller.setVoiceAfkTimeoutMinutes,
                ),
              ),
            ),
            SettingsSwitchRow(
              key: const Key('afk-auto-move-switch'),
              label: 'Move Me to the AFK Channel',
              description:
                  "When the space has one set. You'll be moved back by "
                  'rejoining the channel you want.',
              value: settings.voiceAfkAutoMove,
              onChanged: settings.voiceAfkTimeoutMinutes > 0
                  ? controller.setVoiceAfkAutoMove
                  : null,
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared bits
// ---------------------------------------------------------------------------

class _FieldHeading extends StatelessWidget {
  const _FieldHeading(this.label, [this.description]);

  final String label;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: SettingsText.label(colors)),
        if (description != null) ...[
          const SizedBox(height: 4),
          Text(description!, style: SettingsText.description(colors)),
        ],
      ],
    );
  }
}

/// A 16/500 label, an optional description, then a 0–1 slider.
class _LabelledSlider extends StatelessWidget {
  const _LabelledSlider({
    super.key,
    required this.label,
    this.description,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String? description;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FieldHeading(label, description),
        const SizedBox(height: 16),
        AccordSlider(
          value: value.clamp(0.0, 1.0),
          onChanged: onChanged,
          semanticLabel: label,
        ),
      ],
    );
  }
}

/// A device select with a leading "Default" option (empty id).
class _DeviceSelect extends StatelessWidget {
  const _DeviceSelect({
    super.key,
    required this.icon,
    required this.devices,
    required this.loading,
    required this.selectedId,
    required this.fallbackLabel,
    required this.onChanged,
  });

  final IconData icon;
  final List<MediaDevice> devices;
  final bool loading;
  final String selectedId;
  final String fallbackLabel;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    // Only offer the saved id if it still exists; otherwise "Default".
    final ids = devices.map((d) => d.deviceId).toSet();
    final value = ids.contains(selectedId) ? selectedId : '';
    return AccordSelect<String>(
      value: value,
      leadingIcon: icon,
      options: [
        const AccordSelectOption('', 'Default'),
        for (var i = 0; i < devices.length; i++)
          if (devices[i].deviceId.isNotEmpty &&
              devices[i].deviceId != 'default')
            AccordSelectOption(
              devices[i].deviceId,
              devices[i].label.isNotEmpty
                  ? devices[i].label
                  : '$fallbackLabel ${i + 1}',
            ),
      ],
      onChanged: loading ? null : onChanged,
    );
  }
}

/// Waits for the next key press and returns its physical USB HID usage and a
/// display label, or null when the dialog is dismissed.
Future<(int, String)?> _captureKey(BuildContext context) {
  return showDialog<(int, String)>(
    context: context,
    builder: (dialogContext) => Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.handled;
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.of(dialogContext).pop();
          return KeyEventResult.handled;
        }
        Navigator.of(
          dialogContext,
        ).pop((event.physicalKey.usbHidUsage, pushToTalkKeyLabel(event)));
        return KeyEventResult.handled;
      },
      child: AlertDialog(
        title: const Text('Push-to-talk key'),
        content: const Text('Press the key to use. Esc cancels.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    ),
  );
}

/// How a bound key is shown: the character it types on the current layout,
/// else the key's name (F-keys, Ctrl, Space…).
String pushToTalkKeyLabel(KeyEvent event) {
  final character = event.character?.trim() ?? '';
  if (character.isNotEmpty) return character.toUpperCase();
  return event.logicalKey.keyLabel.isNotEmpty
      ? event.logicalKey.keyLabel
      : 'Key ${event.physicalKey.usbHidUsage.toRadixString(16)}';
}
