import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:jump_player/state/playback_queue.dart';

class EpisodeSidebar extends ConsumerWidget {
  const EpisodeSidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playbackQueueProvider);
    final controller = ref.read(playbackQueueProvider.notifier);

    return Container(
      width: 280,
      color: Colors.black.withValues(alpha: 0.85),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    state.series?.name ?? '未载入剧集',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  color: Colors.white,
                  icon: const Icon(Icons.skip_previous),
                  onPressed: state.hasPrevious ? controller.previous : null,
                ),
                IconButton(
                  color: Colors.white,
                  icon: const Icon(Icons.skip_next),
                  onPressed: state.hasNext ? controller.next : null,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: state.episodes.length,
              itemBuilder: (context, i) {
                final ep = state.episodes[i];
                final selected = i == state.currentIndex;
                return ListTile(
                  dense: true,
                  selected: selected,
                  selectedTileColor: Colors.white24,
                  title: Text(
                    ep.fileName,
                    style: TextStyle(
                      color: selected ? Colors.amber : Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => controller.playAt(i),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
