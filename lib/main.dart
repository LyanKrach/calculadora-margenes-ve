import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'firebase_options.dart';
import 'screens/calculator_screen.dart';
import 'screens/products_screen.dart';
import 'screens/rates_screen.dart';
import 'screens/settings_screen.dart';
import 'services/subscription_service.dart';
import 'services/theme_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {
    // Si falla la inicialización en un entorno sin servicios de Google,
    // la app continúa operando en modo local (SharedPreferences).
  }

  SubscriptionService.instance.ensureStarted();
  await ThemeService.instance.init();

  // OBLIGATORIO: sin esto, DateFormat('...', 'es_VE') en la pantalla de
  // Tasas lanza LocaleDataException en runtime ("Locale data has not been
  // initialized"). Lo confirmó `flutter test` el 2026-11-09: NumberFormat
  // sí funciona sin inicializar, DateFormat no.
  await initializeDateFormatting('es_VE');
  Intl.defaultLocale = 'es_VE';
  runApp(const MargenesApp());
}

/// Calculadora de Márgenes VE — Material 3 con soporte para tema claro y oscuro.
/// 4 pestañas: Calculadora · Productos · Tasas · Ajustes.
class MargenesApp extends StatelessWidget {
  const MargenesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService.instance.themeModeNotifier,
      builder: (context, currentMode, _) {
        return MaterialApp(
          title: 'Calculadora de Márgenes VE',
          debugShowCheckedModeBanner: false,
          themeMode: currentMode,
          theme: ThemeService.lightTheme,
          darkTheme: ThemeService.darkTheme,
          home: const HomeScreen(),
        );
      },
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  static const _pages = [
    CalculatorScreen(),
    ProductsScreen(),
    RatesScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      resizeToAvoidBottomInset: _index != 0,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: isDark
                      ? [const Color(0xFF0C141B), colors.background]
                      : [const Color(0xFFF8FAFC), colors.background],
                  stops: const [0, 0.5],
                ),
              ),
            ),
          ),
          Positioned(
            top: -150,
            right: -100,
            child: IgnorePointer(
              child: Container(
                width: 340,
                height: 340,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      colors.primary.withValues(alpha: isDark ? 0.16 : 0.10),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          IndexedStack(index: _index, children: _pages),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: colors.borderStrong),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.08),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(21),
            child: NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              backgroundColor: Colors.transparent,
              elevation: 0,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.calculate_outlined),
                  selectedIcon: Icon(Icons.calculate),
                  label: 'Calculadora',
                ),
                NavigationDestination(
                  icon: Icon(Icons.inventory_2_outlined),
                  selectedIcon: Icon(Icons.inventory_2),
                  label: 'Productos',
                ),
                NavigationDestination(
                  icon: Icon(Icons.currency_exchange_outlined),
                  selectedIcon: Icon(Icons.currency_exchange),
                  label: 'Tasas',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: 'Ajustes',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Formatos de moneda/tasa: lib/utils/format.dart (fmtBs, fmtUsd, fmtRate).
// Se movieron ahí para evitar import circular main.dart <-> screens.
