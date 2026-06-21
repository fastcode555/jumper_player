import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:jump_player/app.dart';
import 'package:jump_player/domain/playback/player_engine.dart';
import 'package:jump_player/infra/playback/media_kit_player_engine.dart';
import 'package:jump_player/state/playback_providers.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final PlayerEngine engine = MediaKitPlayerEngine();
  runApp(
    ProviderScope(
      overrides: [playerEngineProvider.overrideWithValue(engine)],
      child: const JumpPlayerApp(),
    ),
  );
}
