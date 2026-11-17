import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';

/// Servicio singleton para gestionar y persistir el tema de la aplicación
/// (Modo Claro, Modo Oscuro o Predeterminado del Sistema).
class ThemeService {
  ThemeService._();
  static final ThemeService instance = ThemeService._();

  static const String _prefKey = 'app_theme_mode';

  final ValueNotifier<ThemeMode> themeModeNotifier =
      ValueNotifier<ThemeMode>(ThemeMode.dark);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey);
    if (saved == 'light') {
      themeModeNotifier.value = ThemeMode.light;
    } else if (saved == 'system') {
      themeModeNotifier.value = ThemeMode.system;
    } else {
      themeModeNotifier.value = ThemeMode.dark;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeModeNotifier.value = mode;
    final prefs = await SharedPreferences.getInstance();
    final str = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.system => 'system',
      ThemeMode.dark => 'dark',
    };
    await prefs.setString(_prefKey, str);
  }

  /// Paleta verde esmeralda / gamer (#22C55E)
  static const Color brandSeedColor = AppTheme.brandSeedColor;

  static ThemeData get lightTheme => AppTheme.lightTheme;

  static ThemeData get darkTheme => AppTheme.darkTheme;
}

