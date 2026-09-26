import 'package:flutter/material.dart';
import 'features/practice/practice_screen.dart';
import 'features/progress/progress_screen.dart';

/// Root widget. No network, no cloud — everything on-device.
class SpeakCardsApp extends StatefulWidget {
  const SpeakCardsApp({super.key});
  @override
  State<SpeakCardsApp> createState() => _SpeakCardsAppState();
}

class _SpeakCardsAppState extends State<SpeakCardsApp> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SpeakCards',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      home: Scaffold(
        body: IndexedStack(
          index: _tab,
          children: const [PracticeScreen(), ProgressScreen()],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.mic_rounded),
              label: 'Practice',
            ),
            NavigationDestination(
              icon: Icon(Icons.insights_rounded),
              label: 'Progress',
            ),
          ],
        ),
      ),
    );
  }
}
