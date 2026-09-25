import 'package:flutter/material.dart';
import 'features/practice/practice_screen.dart';

/// Root widget. No network, no cloud — everything on-device.
class SpeakCardsApp extends StatelessWidget {
  const SpeakCardsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SpeakCards',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      home: const PracticeScreen(),
    );
  }
}
