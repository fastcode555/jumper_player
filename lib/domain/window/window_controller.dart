abstract class WindowController {
  Future<void> setFullScreen(bool value);
  Future<bool> isFullScreen();
}

class FakeWindowController implements WindowController {
  bool fullScreen = false;

  @override
  Future<void> setFullScreen(bool value) async {
    fullScreen = value;
  }

  @override
  Future<bool> isFullScreen() async => fullScreen;
}
