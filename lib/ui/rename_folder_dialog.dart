import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:jump_player/domain/library/library_models.dart';
import 'package:jump_player/state/library_actions.dart';

String _baseName(String path) {
  final norm = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
  final i = norm.lastIndexOf('/');
  return i >= 0 ? norm.substring(i + 1) : norm;
}

Future<void> showRenameFolderDialog(BuildContext context, SeriesGroup group) {
  return showDialog<void>(
    context: context,
    builder: (_) => _RenameFolderDialog(group: group),
  );
}

class _RenameFolderDialog extends ConsumerStatefulWidget {
  const _RenameFolderDialog({required this.group});
  final SeriesGroup group;

  @override
  ConsumerState<_RenameFolderDialog> createState() =>
      _RenameFolderDialogState();
}

class _RenameFolderDialogState extends ConsumerState<_RenameFolderDialog> {
  late final TextEditingController _c =
      TextEditingController(text: _baseName(widget.group.dirPath));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final messenger = ScaffoldMessenger.of(context);
    final actions = ref.read(libraryActionsProvider);
    final name = _c.text.trim();
    if (name.isEmpty) return;
    try {
      await actions.renameFolder(widget.group, name);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('重命名文件夹失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('重命名文件夹'),
      content: TextField(
        controller: _c,
        autofocus: true,
        decoration: const InputDecoration(hintText: '新文件夹名'),
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
