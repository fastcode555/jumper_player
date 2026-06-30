import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:jump_player/state/playback_providers.dart';
import 'package:jump_player/state/playback_queue.dart';
import 'package:jump_player/state/skip_providers.dart';

class SkipSettingsBar extends ConsumerStatefulWidget {
  const SkipSettingsBar({super.key});
  @override
  ConsumerState<SkipSettingsBar> createState() => _SkipSettingsBarState();
}

class _SkipSettingsBarState extends ConsumerState<SkipSettingsBar> {
  final _intro = TextEditingController();
  final _outro = TextEditingController();
  String? _dirPath;

  @override
  void dispose() {
    _intro.dispose();
    _outro.dispose();
    super.dispose();
  }

  void _syncFields(String dirPath) {
    if (_dirPath == dirPath) return;
    _dirPath = dirPath;
    final cfg = ref.read(skipConfigProvider.notifier).configFor(dirPath);
    _intro.text = cfg.introSeconds.toString();
    _outro.text = cfg.outroSeconds.toString();
  }

  int _posSeconds() =>
      (ref.read(positionProvider).value ?? Duration.zero).inSeconds;
  int _durSeconds() =>
      (ref.read(durationProvider).value ?? Duration.zero).inSeconds;

  @override
  Widget build(BuildContext context) {
    final dirPath = ref.watch(
        playbackQueueProvider.select((s) => s.currentGroupDirPath));
    if (dirPath == null) return const SizedBox.shrink();
    _syncFields(dirPath);
    final notifier = ref.read(skipConfigProvider.notifier);
    // Keep the position/duration stream subscriptions alive: a StreamProvider
    // only starts listening to its underlying stream once it is
    // watched/listened to at least once.
    ref.watch(positionProvider);
    ref.watch(durationProvider);

    Widget field(String label, TextEditingController ctl, String markKey,
        VoidCallback onMark, ValueChanged<String> onSubmit) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: const TextStyle(color: Colors.white70)),
        const SizedBox(width: 4),
        SizedBox(
          width: 48,
          child: TextField(
            controller: ctl,
            style: const TextStyle(color: Colors.white),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            decoration: const InputDecoration(isDense: true),
            onSubmitted: onSubmit,
          ),
        ),
        const Text('s', style: TextStyle(color: Colors.white70)),
        TextButton(
          key: Key(markKey),
          onPressed: onMark,
          child: const Text('标记'),
        ),
      ]);
    }

    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(children: [
        field('片头', _intro, 'mark-intro', () {
          final p = _posSeconds();
          notifier.setIntro(dirPath, p);
          setState(() => _intro.text = p.toString());
        }, (v) => notifier.setIntro(dirPath, int.tryParse(v) ?? 0)),
        const SizedBox(width: 16),
        field('片尾', _outro, 'mark-outro', () {
          final m = (_durSeconds() - _posSeconds()).clamp(0, 1 << 31);
          notifier.setOutro(dirPath, m);
          setState(() => _outro.text = m.toString());
        }, (v) => notifier.setOutro(dirPath, int.tryParse(v) ?? 0)),
      ]),
    );
  }
}
