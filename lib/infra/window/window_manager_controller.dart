import 'package:window_manager/window_manager.dart';
import 'package:jump_player/domain/window/window_controller.dart';

class WindowManagerController implements WindowController {
  @override
  Future<void> setFullScreen(bool value) => windowManager.setFullScreen(value);

  @override
  Future<bool> isFullScreen() => windowManager.isFullScreen();
}
