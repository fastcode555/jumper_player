import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:jump_player/state/library_actions.dart';
import 'package:jump_player/state/playback_queue.dart';
import 'package:jump_player/ui/confirm_dialog.dart';
import 'package:jump_player/ui/rename_episode_dialog.dart';
import 'package:jump_player/ui/rename_folder_dialog.dart';

final expandedGroupsProvider = StateProvider<Set<String>>((ref) => {});

class EpisodeSidebar extends ConsumerWidget {
  const EpisodeSidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playbackQueueProvider);
    final controller = ref.read(playbackQueueProvider.notifier);
    final expanded = ref.watch(expandedGroupsProvider);
    final groups = state.series?.groups ?? const [];

    final rows = <Widget>[];
    var globalIndex = 0;

    for (final group in groups) {
      final groupStartIndex = globalIndex;
      final episodeCount = group.episodes.length;

      // determine if this group contains the current episode
      final currentIndex = state.currentIndex;
      final containsCurrent = currentIndex >= 0 &&
          currentIndex >= groupStartIndex &&
          currentIndex < groupStartIndex + episodeCount;

      final isExpanded = expanded.contains(group.dirPath) || containsCurrent;
      final actions = ref.read(libraryActionsProvider);
      final isRoot = actions.isRootGroup(group);

      // Group header
      rows.add(InkWell(
        onTap: () {
          ref.read(expandedGroupsProvider.notifier).update((s) {
            final copy = Set<String>.from(s);
            if (copy.contains(group.dirPath)) {
              copy.remove(group.dirPath);
            } else {
              copy.add(group.dirPath);
            }
            return copy;
          });
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 4, 4),
          child: Row(
            children: [
              Icon(
                isExpanded ? Icons.expand_less : Icons.expand_more,
                color: Colors.white70,
                size: 18,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  group.title,
                  style: const TextStyle(
                      color: Colors.white70, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              PopupMenuButton<String>(
                key: Key('folder-menu-${group.dirPath}'),
                icon: const Icon(Icons.more_vert, color: Colors.white70, size: 18),
                onSelected: (v) async {
                  final a = ref.read(libraryActionsProvider);
                  if (v == 'reveal') {
                    a.revealFolder(group);
                  } else if (v == 'rename') {
                    // ignore: use_build_context_synchronously
                    await showRenameFolderDialog(context, group);
                  } else if (v == 'delete') {
                    // ignore: use_build_context_synchronously
                    final ok = await showConfirmDialog(context,
                        title: '删除文件夹',
                        message: '确定要把「${group.title}」移入废纸篓？');
                    if (ok) await a.deleteFolder(group);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'reveal', child: Text('打开所在位置')),
                  if (!isRoot) ...[
                    const PopupMenuItem(value: 'rename', child: Text('重命名')),
                    const PopupMenuItem(value: 'delete', child: Text('删除')),
                  ],
                ],
              ),
            ],
          ),
        ),
      ));

      for (final ep in group.episodes) {
        final idx = globalIndex;
        if (isExpanded) {
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
              onSelected: (v) async {
                final messenger = ScaffoldMessenger.of(context);
                final a = ref.read(libraryActionsProvider);
                if (v == 'reveal') {
                  a.revealEpisode(ep);
                } else if (v == 'rename') {
                  // ignore: use_build_context_synchronously
                  await showRenameEpisodeDialog(context, ep);
                } else if (v == 'delete') {
                  try {
                    await a.deleteEpisode(ep);
                  } catch (e) {
                    messenger.showSnackBar(
                        SnackBar(content: Text('删除失败：$e')));
                  }
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'reveal', child: Text('打开所在位置')),
                PopupMenuItem(value: 'rename', child: Text('重命名')),
                PopupMenuItem(value: 'delete', child: Text('删除')),
              ],
            ),
            onTap: () => controller.playAt(idx),
          ));
        }
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
