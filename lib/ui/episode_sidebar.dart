import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:jump_player/state/library_actions.dart';
import 'package:jump_player/state/playback_queue.dart';
import 'package:jump_player/ui/rename_episode_dialog.dart';

class EpisodeSidebar extends ConsumerWidget {
  const EpisodeSidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playbackQueueProvider);
    final controller = ref.read(playbackQueueProvider.notifier);
    final groups = state.series?.groups ?? const [];

    final rows = <Widget>[];
    var globalIndex = 0;
    for (final group in groups) {
      rows.add(Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Text(
          group.title,
          style: const TextStyle(
              color: Colors.white70, fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
        ),
      ));
      for (final ep in group.episodes) {
        final idx = globalIndex;
        final selected = idx == state.currentIndex;
        rows.add(ListTile(
          dense: true,
          selected: selected,
          selectedTileColor: Colors.white24,
          title: Text(
            ep.displayName,
            style: TextStyle(color: selected ? Colors.amber : Colors.white),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white70),
            onSelected: (v) {
              if (v == 'reveal') {
                ref.read(libraryActionsProvider).revealEpisode(ep);
              } else if (v == 'rename') {
                showRenameEpisodeDialog(context, ep);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'reveal', child: Text('打开所在位置')),
              PopupMenuItem(value: 'rename', child: Text('重命名')),
            ],
          ),
          onTap: () => controller.playAt(idx),
        ));
        globalIndex++;
      }
    }

    return Container(
      width: 280,
      color: Colors.black.withValues(alpha: 0.85),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              state.series?.name ?? '未载入剧集',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Divider(height: 1),
          Expanded(child: ListView(children: rows)),
        ],
      ),
    );
  }
}
