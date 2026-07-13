/// lib/features/glasses_voice/screens/glasses_voice_screen.dart
///
/// The assistant's main surface (Section 10). Layout intent:
///   - connection status is a permanent banner at the top — never hidden in a
///     settings screen, never ambiguous;
///   - the animated [PipelineOrb] is the emotional center: its motion/color IS
///     the listening/thinking/speaking state;
///   - transcript and reply render as a conversation, errors as a designed
///     card instead of a raw snackbar string;
///   - stream/dev controls are demoted to a collapsed "Device controls" row.
library;

import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter_meta_wearables_dat/flutter_meta_wearables_dat.dart';

import '../../../app/theme.dart';
import '../../home/data/home_repository.dart';
import '../data/glasses_pipeline.dart';
import '../widgets/pipeline_orb.dart';

class GlassesVoiceScreen extends StatefulWidget {
  const GlassesVoiceScreen({super.key});

  @override
  State<GlassesVoiceScreen> createState() => _GlassesVoiceScreenState();
}

class _GlassesVoiceScreenState extends State<GlassesVoiceScreen> {
  final MetaWearablesCamera _camera = MetaWearablesCamera.instance;
  late final GlassesAssistantPipeline _pipeline = GlassesAssistantPipeline(
    audio: MetaWearablesAudio.instance,
  );

  StreamSubscription<GlassesConnectionState>? _cameraStateSub;
  StreamSubscription<GlassesAudioState>? _audioStateSub;
  StreamSubscription<PipelineState>? _pipelineSub;

  GlassesConnectionState _cameraState = GlassesConnectionState.idle;
  GlassesAudioState _audioState = const GlassesAudioState(
    GlassesAudioMode.idle,
    GlassesAudioRoute.none,
    false,
  );
  PipelineState _pipelineState = const PipelineState(PipelinePhase.idle);
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Preload + warm the on-device model while the user is still connecting
    // the glasses, so the first voice turn doesn't pay the ~30s model load.
    unawaited(HomeRepository().ensureModelLoaded().catchError((Object e) {
      dev.log('Model preload failed (first turn will retry): $e',
          name: 'GlassesVoiceScreen');
    }));
    _cameraStateSub = _camera.connectionState.listen((state) {
      if (mounted) setState(() => _cameraState = state);
    });
    _audioStateSub = _pipeline.audio.audioState.listen((state) {
      if (mounted) setState(() => _audioState = state);
    });
    _pipelineSub = _pipeline.states.listen((state) {
      if (mounted) setState(() => _pipelineState = state);
    });
  }

  @override
  void dispose() {
    _cameraStateSub?.cancel();
    _audioStateSub?.cancel();
    _pipelineSub?.cancel();
    _pipeline.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      // Pipeline errors surface through _pipelineState.error and render as a
      // card; connection/stream errors still get a transient snackbar.
      if (mounted && _pipelineState.phase != PipelinePhase.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() => _run(() async {
        final connected = await _camera.connect();
        if (!connected) throw StateError('Could not connect to the glasses.');
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Glasses Assistant'),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome_outlined),
            tooltip: 'Memories',
            onPressed: () => Navigator.pushNamed(context, '/memories'),
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_alt_outlined),
            tooltip: 'Type instead',
            onPressed: () => Navigator.pushNamed(context, '/home'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.s4,
                AppTheme.s2,
                AppTheme.s4,
                0,
              ),
              child: _ConnectionBanner(
                cameraState: _cameraState,
                audioState: _audioState,
                busy: _busy,
                onConnect: _connect,
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppTheme.s4),
                child: Column(
                  children: [
                    const SizedBox(height: AppTheme.s4),
                    PipelineOrb(phase: _pipelineState.phase),
                    const SizedBox(height: AppTheme.s4),
                    _PhaseCaption(phase: _pipelineState.phase),
                    const SizedBox(height: AppTheme.s5),
                    if (_pipelineState.transcript != null)
                      _SpeechBubble(
                        label: 'YOU',
                        text: _pipelineState.transcript!,
                        alignEnd: true,
                      ),
                    if (_pipelineState.reply != null) ...[
                      const SizedBox(height: AppTheme.s3),
                      _SpeechBubble(
                        label: 'ASSISTANT',
                        text: _pipelineState.reply!,
                        alignEnd: false,
                      ),
                    ],
                    if (_pipelineState.phase == PipelinePhase.error &&
                        _pipelineState.error != null) ...[
                      const SizedBox(height: AppTheme.s3),
                      _ErrorCard(error: _pipelineState.error!),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppTheme.s4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _run(_pipeline.runTurn),
                    icon: _busy
                        ? SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: theme.colorScheme.onPrimary,
                            ),
                          )
                        : const Icon(Icons.mic),
                    label: Text(_busy ? 'One moment…' : 'Ask the glasses'),
                  ),
                  const SizedBox(height: AppTheme.s2),
                  _DeviceControls(busy: _busy, camera: _camera, run: _run),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Connection banner — always visible, one glance answers "will voice work?".
// ---------------------------------------------------------------------------

enum _LinkStatus { connected, connecting, disconnected, error }

class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({
    required this.cameraState,
    required this.audioState,
    required this.busy,
    required this.onConnect,
  });

  final GlassesConnectionState cameraState;
  final GlassesAudioState audioState;
  final bool busy;
  final VoidCallback onConnect;

  _LinkStatus get _status {
    switch (cameraState) {
      case GlassesConnectionState.connected:
      case GlassesConnectionState.streaming:
        return _LinkStatus.connected;
      case GlassesConnectionState.connecting:
        return _LinkStatus.connecting;
      case GlassesConnectionState.error:
        return _LinkStatus.error;
      case GlassesConnectionState.idle:
        return _LinkStatus.disconnected;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phaseColors = theme.extension<PhaseColors>()!;

    final (color, label, detail) = switch (_status) {
      _LinkStatus.connected => (
          phaseColors.speaking,
          'Glasses connected',
          audioState.route == GlassesAudioRoute.hfpMicSpeaker &&
                  audioState.isRouteSettled
              ? 'Mic ready'
              : 'Audio: ${audioState.route.name}',
        ),
      _LinkStatus.connecting => (
          phaseColors.thinking,
          'Connecting…',
          'Looking for your glasses',
        ),
      _LinkStatus.error => (
          phaseColors.error,
          'Connection error',
          'Voice commands won\'t work until reconnected',
        ),
      _LinkStatus.disconnected => (
          phaseColors.idle,
          'Not connected',
          'Connect to use voice commands',
        ),
    };

    final showAction = _status == _LinkStatus.disconnected ||
        _status == _LinkStatus.error;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.s4,
        vertical: AppTheme.s3,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          _StatusDot(color: color, pulsing: _status == _LinkStatus.connecting),
          const SizedBox(width: AppTheme.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.titleMedium),
                Text(detail, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          if (showAction)
            TextButton(
              onPressed: busy ? null : onConnect,
              child: Text(_status == _LinkStatus.error ? 'Retry' : 'Connect'),
            ),
        ],
      ),
    );
  }
}

class _StatusDot extends StatefulWidget {
  const _StatusDot({required this.color, required this.pulsing});

  final Color color;
  final bool pulsing;

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    lowerBound: 0.35,
  );

  @override
  void initState() {
    super.initState();
    if (widget.pulsing) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_StatusDot old) {
    super.didUpdateWidget(old);
    if (widget.pulsing && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.pulsing && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: widget.pulsing
          ? _controller
          : const AlwaysStoppedAnimation(1),
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: 0.5),
              blurRadius: 8,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Phase caption, conversation bubbles, error card, demoted device controls.
// ---------------------------------------------------------------------------

class _PhaseCaption extends StatelessWidget {
  const _PhaseCaption({required this.phase});

  final PipelinePhase phase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (title, hint) = switch (phase) {
      PipelinePhase.idle => ('Ready', 'Tap the mic and speak'),
      PipelinePhase.listening => ('Listening…', 'Go ahead, I\'m all ears'),
      PipelinePhase.thinking => ('Thinking…', 'Working it out on-device'),
      PipelinePhase.speaking => ('Speaking', 'Replying through your glasses'),
      PipelinePhase.error => ('Something went wrong', 'Details below'),
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: Column(
        key: ValueKey(phase),
        children: [
          Text(title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: AppTheme.s1),
          Text(hint, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _SpeechBubble extends StatelessWidget {
  const _SpeechBubble({
    required this.label,
    required this.text,
    required this.alignEnd,
  });

  final String label;
  final String text;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.s4,
            vertical: AppTheme.s3,
          ),
          decoration: BoxDecoration(
            color: alignEnd
                ? theme.colorScheme.surfaceContainerHighest
                : theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppTheme.radius),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelSmall),
              const SizedBox(height: AppTheme.s1),
              Text(text, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final errorColor = theme.extension<PhaseColors>()!.error;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.s4),
      decoration: BoxDecoration(
        color: errorColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: errorColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: errorColor, size: 20),
          const SizedBox(width: AppTheme.s3),
          Expanded(
            child: Text(
              _friendly(error),
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  /// StateErrors in the pipeline already carry user-facing text; strip the
  /// exception-type prefix so the card reads like a product, not a stack trace.
  String _friendly(Object error) {
    final s = '$error';
    const prefixes = ['Bad state: ', 'StateError: ', 'Exception: '];
    for (final p in prefixes) {
      if (s.startsWith(p)) return s.substring(p.length);
    }
    return s;
  }
}

class _DeviceControls extends StatelessWidget {
  const _DeviceControls({
    required this.busy,
    required this.camera,
    required this.run,
  });

  final bool busy;
  final MetaWearablesCamera camera;
  final Future<void> Function(Future<void> Function()) run;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TextButton.icon(
          onPressed: busy
              ? null
              : () => run(() async {
                    final started = await camera.startStream();
                    if (!started) {
                      throw StateError('Could not start the camera stream.');
                    }
                  }),
          icon: const Icon(Icons.play_arrow_outlined, size: 18),
          label: const Text('Start stream'),
        ),
        const SizedBox(width: AppTheme.s2),
        TextButton.icon(
          onPressed: busy ? null : () => run(camera.stopStream),
          icon: const Icon(Icons.stop_outlined, size: 18),
          label: const Text('Stop stream'),
        ),
      ],
    );
  }
}
