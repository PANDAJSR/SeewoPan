import 'package:flutter/material.dart';

import 'home_shell_page.dart';

class SeewoPanApp extends StatelessWidget {
  const SeewoPanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SeewoPan',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomeShellPage(),
    );
  }
}
