import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AutoAdvanceController extends StateNotifier<bool> {
  AutoAdvanceController() : super(true) {
    _load();
  }

  static const String _key = 'auto_advance_v1';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) state = prefs.getBool(_key) ?? true;
  }

  Future<void> set(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }

  Future<void> toggle() => set(!state);
}

final autoAdvanceProvider =
    StateNotifierProvider<AutoAdvanceController, bool>(
        (ref) => AutoAdvanceController());
