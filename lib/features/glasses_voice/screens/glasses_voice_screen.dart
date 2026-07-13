/// lib/features/glasses_voice/screens/glasses_voice_screen.dart
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_meta_wearables_dat/flutter_meta_wearables_dat.dart';

import '../data/glasses_voice_assistant.dart';

class GlassesVoiceScreen extends StatefulWidget {
  const GlassesVoiceScreen({super.key});

  @override
  State<GlassesVoiceScreen> createState() => _GlassesVoiceScreenState();
}

class _GlassesVoiceScreenState extends State<GlassesVoiceScreen> {
  final MetaWearablesCamera _camera = MetaWearablesCamera.instance;
  late final GlassesVoiceAssistant _assistant = GlassesVoiceAssistant(
    audio: MetaWearablesAudio.instance,
  );

  StreamSubscription<GlassesConnectionState>? _cameraStateSub;
  StreamSubscription<GlassesAudioState>? _audioStateSub;

  GlassesConnectionState _cameraState = GlassesConnectionState.idle;
  GlassesAudioState _audioState = const GlassesAudioState(
    GlassesAudioMode.idle,
    GlassesAudioRoute.none,
    false,
  );
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _cameraStateSub = _camera.connectionState.listen((state) {
      if (mounted) setState(() => _cameraState = state);
    });
    _audioStateSub = _assistant.audio.audioState.listen((state) {
      if (mounted) setState(() => _audioState = state);
    });
  }

  @override
  void dispose() {
    _cameraStateSub?.cancel();
    _audioStateSub?.cancel();
    _assistant.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      _showError('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Glasses'),
        actions: [
          IconButton(
            icon: const Icon(Icons.home_outlined),
            tooltip: 'Home',
            onPressed: () => Navigator.pushNamed(context, '/home'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatusBadge(label: 'Camera', value: _cameraState.name),
            const SizedBox(height: 8),
            _StatusBadge(
              label: 'Audio',
              value:
                  '${_audioState.mode.name} · ${_audioState.route.name}'
                  '${_audioState.isRouteSettled ? ' · settled' : ''}',
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                      final connected = await _camera.connect();
                      if (!connected) throw StateError('Camera connect failed');
                    }),
              child: const Text('Connect camera'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                      final started = await _camera.startStream();
                      if (!started) throw StateError('Stream start failed');
                    }),
              child: const Text('Start stream'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy ? null : () => _run(_camera.stopStream),
              child: const Text('Stop stream'),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () => _run(_assistant.startConversationTurn),
              child: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Ask the glasses'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
