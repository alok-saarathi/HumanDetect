import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Portrait only: the camera frame rotation logic assumes it.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const HumanDetectApp());
}

class HumanDetectApp extends StatelessWidget {
  const HumanDetectApp({super.key});

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness brightness) => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF0F766E),
        brightness: brightness,
      ),
      useMaterial3: true,
    );
    return MaterialApp(
      title: 'HumanDetect lab',
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: const HomeScreen(),
    );
  }
}
