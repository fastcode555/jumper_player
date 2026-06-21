import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:jump_player/domain/window/window_controller.dart';

final windowControllerProvider = Provider<WindowController>((ref) {
  throw UnimplementedError('windowControllerProvider must be overridden at startup');
});

final isFullScreenProvider = StateProvider<bool>((ref) => false);
