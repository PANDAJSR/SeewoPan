import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_shell_page.dart';

class SeewoPanApp extends StatefulWidget {
  const SeewoPanApp({super.key});

  @override
  State<SeewoPanApp> createState() => _SeewoPanAppState();
}

class _SeewoPanAppState extends State<SeewoPanApp> {
  static const _themeModeStorageKey = 'seewopan.theme_mode';

  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadThemeMode();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SeewoPan',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: _themeMode,
      home: HomeShellPage(
        themeMode: _themeMode,
        onThemeModeChanged: _saveThemeMode,
      ),
    );
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final rawValue = prefs.getString(_themeModeStorageKey);
    final loadedThemeMode = _themeModeFromStorage(rawValue);

    if (!mounted) {
      return;
    }

    setState(() {
      _themeMode = loadedThemeMode;
    });
  }

  Future<void> _saveThemeMode(ThemeMode value) async {
    if (value == _themeMode) {
      return;
    }

    setState(() {
      _themeMode = value;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeStorageKey, _themeModeToStorage(value));
  }

  ThemeMode _themeModeFromStorage(String? value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  String _themeModeToStorage(ThemeMode value) {
    switch (value) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}
