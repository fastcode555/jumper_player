import 'package:flutter/material.dart';
import 'package:jump_player/ui/player_page.dart';

class JumpPlayerApp extends StatelessWidget {
  const JumpPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jump Player',
      theme: ThemeData.dark(useMaterial3: true),
      home: const PlayerPage(),
    );
  }
}
