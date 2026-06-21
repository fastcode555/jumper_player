import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:jump_player/state/playback_providers.dart';
import 'package:jump_player/state/ui_providers.dart';
import 'package:jump_player/ui/control_bar.dart';
import 'package:jump_player/ui/episode_sidebar.dart';

class PlayerPage extends ConsumerWidget {
  const PlayerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(videoControllerProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (controller != null) Video(controller: controller),
                if (ref.watch(sidebarVisibleProvider))
                  const Align(
                    alignment: Alignment.centerRight,
                    child: EpisodeSidebar(),
                  ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: IconButton(
                    tooltip: '剧集列表',
                    color: Colors.white,
                    icon: const Icon(Icons.playlist_play),
                    onPressed: () =>
                        ref.read(sidebarVisibleProvider.notifier).state =
                            !ref.read(sidebarVisibleProvider),
                  ),
                ),
              ],
            ),
          ),
          const ControlBar(),
        ],
      ),
    );
  }
}
