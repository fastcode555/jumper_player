import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:jump_player/state/playback_providers.dart';

class PlayerPage extends ConsumerWidget {
  const PlayerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.watch(playerEngineProvider);
    final isPlaying = ref.watch(isPlayingProvider).value ?? false;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () async {
                final result = await FilePicker.platform.pickFiles(
                  type: FileType.video,
                );
                final path = result?.files.single.path;
                if (path != null) {
                  await engine.open(path);
                  await engine.play();
                }
              },
              child: const Text('打开文件'),
            ),
            IconButton(
              color: Colors.white,
              iconSize: 48,
              icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
              onPressed: () =>
                  isPlaying ? engine.pause() : engine.play(),
            ),
          ],
        ),
      ),
    );
  }
}
