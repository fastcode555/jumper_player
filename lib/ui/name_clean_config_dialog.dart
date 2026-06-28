// lib/ui/name_clean_config_dialog.dart
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:jump_player/domain/library/name_clean_config.dart';
import 'package:jump_player/state/library_actions.dart';
import 'package:jump_player/state/name_clean_providers.dart';

const Map<BuiltinNoiseRule, String> kRuleLabels = {
  BuiltinNoiseRule.latinBracketTags: '英文括号标签（[GM-Team]/[HEVC]…）',
  BuiltinNoiseRule.resolution: '分辨率（1080p/2160p…）',
  BuiltinNoiseRule.codecSource: '编码/来源（x265/WEB-DL/BluRay…）',
  BuiltinNoiseRule.year: '年份（19xx/20xx）',
};

Future<void> showNameCleanConfigDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const Dialog(child: NameCleanConfigDialog()),
  );
}

class NameCleanConfigDialog extends ConsumerStatefulWidget {
  const NameCleanConfigDialog({super.key});

  @override
  ConsumerState<NameCleanConfigDialog> createState() =>
      _NameCleanConfigDialogState();
}

class _NameCleanConfigDialogState extends ConsumerState<NameCleanConfigDialog> {
  late Set<BuiltinNoiseRule> _rules;
  late List<String> _snippets;
  final _input = TextEditingController();

  @override
  void initState() {
    super.initState();
    final cfg = ref.read(nameCleanConfigProvider);
    _rules = {...cfg.enabledBuiltinRules};
    _snippets = [...cfg.customSnippets];
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _addSnippet() {
    final v = _input.text.trim();
    if (v.isEmpty || _snippets.contains(v)) return;
    setState(() {
      _snippets.add(v);
      _input.clear();
    });
  }

  Future<void> _save() async {
    // Flush any snippet left typed in the input box that the user didn't
    // commit with the "+" button — saving should not silently drop it.
    final pending = _input.text.trim();
    if (pending.isNotEmpty && !_snippets.contains(pending)) {
      _snippets.add(pending);
    }
    final cfg = NameCleanConfig(
      enabledBuiltinRules: _rules,
      customSnippets: _snippets,
    );
    // Capture messenger synchronously before any await to avoid using
    // BuildContext across an async gap.
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(nameCleanConfigProvider.notifier).save(cfg);
    try {
      await ref.read(libraryActionsProvider).reapplyCurrent();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('无法重新生成命名：$e')),
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('命名清洗配置',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final rule in BuiltinNoiseRule.values)
                  SwitchListTile(
                    title: Text(kRuleLabels[rule] ?? rule.name),
                    value: _rules.contains(rule),
                    onChanged: (on) => setState(() {
                      on ? _rules.add(rule) : _rules.remove(rule);
                    }),
                  ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    Expanded(
                      child: TextField(
                        key: const Key('snippet-input'),
                        controller: _input,
                        decoration: const InputDecoration(
                            hintText: '自定义噪声文字，如 HD国语中字无水印'),
                        onSubmitted: (_) => _addSnippet(),
                      ),
                    ),
                    IconButton(
                      key: const Key('snippet-add'),
                      icon: const Icon(Icons.add),
                      onPressed: _addSnippet,
                    ),
                  ]),
                ),
                for (final s in _snippets)
                  ListTile(
                    dense: true,
                    title: Text(s),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => setState(() => _snippets.remove(s)),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('config-save'),
                  onPressed: _save,
                  child: const Text('保存'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
