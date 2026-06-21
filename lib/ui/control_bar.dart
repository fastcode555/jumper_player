import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:jump_player/state/library_actions.dart';
import 'package:jump_player/state/playback_providers.dart';
import 'package:jump_player/state/playback_queue.dart';
import 'package:jump_player/state/window_providers.dart';

class ControlBar extends ConsumerWidget {
  const ControlBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.watch(playerEngineProvider);
    final isPlaying = ref.watch(isPlayingProvider).value ?? false;
    final queue = ref.watch(playbackQueueProvider);
    final isFullScreen = ref.watch(isFullScreenProvider);

    return Container(
      height: 56,
      color: Colors.black87,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: '打开文件',
            color: Colors.white,
            icon: const Icon(Icons.insert_drive_file_outlined),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final result =
                  await FilePicker.platform.pickFiles(type: FileType.video);
              if (result == null || result.files.isEmpty) return;
              final path = result.files.first.path;
              if (path == null) return;
              try {
                await engine.open(path);
                await engine.play();
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(content: Text('无法播放该文件：$e')),
                );
              }
            },
          ),
          IconButton(
            tooltip: '打开文件夹',
            color: Colors.white,
            icon: const Icon(Icons.folder_open),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final path = await FilePicker.platform.getDirectoryPath();
              if (path == null) return;
              try {
                await ref.read(libraryActionsProvider).openFolder(path);
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(content: Text('无法扫描该文件夹：$e')),
                );
              }
            },
          ),
          IconButton(
            tooltip: '上一集',
            color: Colors.white,
            icon: const Icon(Icons.skip_previous),
            onPressed: queue.hasPrevious
                ? ref.read(playbackQueueProvider.notifier).previous
                : null,
          ),
          IconButton(
            tooltip: isPlaying ? '暂停' : '播放',
            color: Colors.white,
            iconSize: 36,
            icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
            onPressed: () async {
              isPlaying ? await engine.pause() : await engine.play();
            },
          ),
          IconButton(
            tooltip: '下一集',
            color: Colors.white,
            icon: const Icon(Icons.skip_next),
            onPressed: queue.hasNext
                ? ref.read(playbackQueueProvider.notifier).next
                : null,
          ),
          IconButton(
            tooltip: '全屏',
            color: Colors.white,
            icon: Icon(isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen),
            onPressed: () async {
              final next = !isFullScreen;
              await ref.read(windowControllerProvider).setFullScreen(next);
              ref.read(isFullScreenProvider.notifier).state = next;
            },
          ),
        ],
      ),
    );
  }
}
