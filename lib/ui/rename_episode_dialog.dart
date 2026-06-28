import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:jump_player/domain/library/library_models.dart';
import 'package:jump_player/state/library_actions.dart';

String _baseName(String fileName) {
  final i = fileName.lastIndexOf('.');
  return i > 0 ? fileName.substring(0, i) : fileName;
}

Future<void> showRenameEpisodeDialog(BuildContext context, Episode ep) {
  return showDialog<void>(
    context: context,
    builder: (_) => _RenameDialog(episode: ep),
  );
}

class _RenameDialog extends ConsumerStatefulWidget {
  const _RenameDialog({required this.episode});
  final Episode episode;
  @override
  ConsumerState<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends ConsumerState<_RenameDialog> {
  late final TextEditingController _c =
      TextEditingController(text: _baseName(widget.episode.fileName));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final messenger = ScaffoldMessenger.of(context);
    final name = _c.text.trim();
    if (name.isEmpty) return;
    try {
      await ref.read(libraryActionsProvider).renameEpisode(widget.episode, name);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('重命名失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('重命名'),
      content: TextField(
        controller: _c,
        autofocus: true,
        decoration: const InputDecoration(hintText: '新文件名（自动保留扩展名）'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消')),
        FilledButton(onPressed: _submit, child: const Text('确定')),
      ],
    );
  }
}
