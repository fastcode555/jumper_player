import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'package:jump_player/app.dart';
import 'package:jump_player/domain/playback/player_engine.dart';
import 'package:jump_player/domain/window/window_controller.dart';
import 'package:jump_player/infra/playback/media_kit_player_engine.dart';
import 'package:jump_player/infra/window/window_manager_controller.dart';
import 'package:jump_player/state/playback_providers.dart';
import 'package:jump_player/state/window_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await windowManager.ensureInitialized();
  // Match the dark UI: render the native macOS title bar with a dark
  // background and light text instead of the default white bar.
  await windowManager.setBrightness(Brightness.dark);
  final PlayerEngine engine = MediaKitPlayerEngine();
  final WindowController window = WindowManagerController();
  runApp(
    ProviderScope(
      overrides: [
        playerEngineProvider.overrideWithValue(engine),
        windowControllerProvider.overrideWithValue(window),
      ],
      child: const JumpPlayerApp(),
    ),
  );
}
