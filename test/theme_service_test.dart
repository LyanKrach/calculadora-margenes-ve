import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:calculadora_margenes_ve/services/theme_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ThemeService', () {
    test('inicializa por defecto en modo oscuro y permite cambiar a claro / sistema', () async {
      final service = ThemeService.instance;
      await service.init();
      expect(service.themeModeNotifier.value, ThemeMode.dark);

      await service.setThemeMode(ThemeMode.light);
      expect(service.themeModeNotifier.value, ThemeMode.light);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_theme_mode'), 'light');

      await service.setThemeMode(ThemeMode.system);
      expect(service.themeModeNotifier.value, ThemeMode.system);
      expect(prefs.getString('app_theme_mode'), 'system');

      await service.setThemeMode(ThemeMode.dark);
      expect(service.themeModeNotifier.value, ThemeMode.dark);
    });

    test('lightTheme y darkTheme configuran useMaterial3 con color verde de marca', () {
      expect(ThemeService.lightTheme.useMaterial3, isTrue);
      expect(ThemeService.darkTheme.useMaterial3, isTrue);
      expect(ThemeService.brandSeedColor, const Color(0xFF22C55E));
    });
  });
}

