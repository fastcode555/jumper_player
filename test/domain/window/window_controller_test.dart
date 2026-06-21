import 'package:flutter_test/flutter_test.dart';
import 'package:jump_player/domain/window/window_controller.dart';

void main() {
  test('FakeWindowController toggles fullscreen', () async {
    final w = FakeWindowController();
    expect(await w.isFullScreen(), isFalse);
    await w.setFullScreen(true);
    expect(await w.isFullScreen(), isTrue);
    expect(w.fullScreen, isTrue);
  });
}
