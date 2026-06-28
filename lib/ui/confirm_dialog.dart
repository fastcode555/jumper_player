import 'package:flutter/material.dart';

Future<bool> showConfirmDialog(BuildContext context,
    {required String title, required String message}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消')),
        FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除')),
      ],
    ),
  );
  return ok ?? false;
}
