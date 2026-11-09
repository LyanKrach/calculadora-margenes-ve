import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'screens/calculator_screen.dart';
import 'screens/rates_screen.dart';
import 'screens/settings_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // OBLIGATORIO: sin esto, DateFormat('...', 'es_VE') en la pantalla de
  // Tasas lanza LocaleDataException en runtime ("Locale data has not been
  // initialized"). Lo confirmó `flutter test` el 2026-11-09: NumberFormat
  // sí funciona sin inicializar, DateFormat no.
  await initializeDateFormatting('es_VE');
  Intl.defaultLocale = 'es_VE';
  runApp(const MargenesApp());
}

/// Calculadora de Márgenes VE — Material 3, tema oscuro gamer sobrio.
/// 3 pestañas: Calculadora · Tasas · Ajustes.
class MargenesApp extends StatelessWidget {
  const MargenesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Calculadora de Márgenes VE',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF22C55E), // verde gamer sobrio
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0B0F14),
        cardTheme: const CardThemeData(
          color: Color(0xFF151B23),
          elevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1E2630),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: const HomeScreen(),
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
    RatesScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calculate_outlined),
            selectedIcon: Icon(Icons.calculate),
            label: 'Calculadora',
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
    );
  }
}

// Formatos de moneda/tasa: lib/utils/format.dart (fmtBs, fmtUsd, fmtRate).
// Se movieron ahí para evitar import circular main.dart <-> screens.
