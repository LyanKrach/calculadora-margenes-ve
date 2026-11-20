import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:calculadora_margenes_ve/screens/calculator_screen.dart';
import 'package:calculadora_margenes_ve/screens/result_screen.dart';
import 'package:calculadora_margenes_ve/theme/app_theme.dart';

class _OfflineHttpClient extends Fake implements HttpClient {
  @override
  bool autoUncompress = true;
  @override
  Duration idleTimeout = const Duration(seconds: 15);

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    throw const SocketException('Test offline');
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);
  @override
  Future<HttpClientRequest> postUrl(Uri url) => openUrl('POST', url);
}

class _OfflineHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _OfflineHttpClient();
}

void main() {
  setUpAll(() async {
    HttpOverrides.global = _OfflineHttpOverrides();
    await initializeDateFormatting('es_VE');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Rediseño v4 estilo ArbiCalc: Calculadora sin scroll + ResultScreen', () {
    testWidgets('Calculadora no tiene scroll vertical y muestra carrusel horizontal de tasas con badge Hoy', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const CalculatorScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Ningún SingleChildScrollView en CalculatorScreen
      expect(find.byType(SingleChildScrollView), findsNothing);

      // 2. Ningún Scrollable vertical en CalculatorScreen (solo el carrusel horizontal de tasas)
      final scrollables = tester.widgetList<Scrollable>(find.byType(Scrollable));
      final verticalScrollables = scrollables.where(
        (s) =>
            s.axisDirection == AxisDirection.down ||
            s.axisDirection == AxisDirection.up,
      );
      expect(verticalScrollables, isEmpty);
      expect(scrollables.isNotEmpty, isTrue);

      // 3. Las 4 tarjetas de tasa están en el carrusel horizontal y BCV muestra badge "Hoy"
      expect(find.text('BCV dólar'), findsOneWidget);
      expect(find.text('Binance USDT'), findsOneWidget);
      expect(find.text('Euro BCV'), findsOneWidget);
      expect(find.text('Personalizada'), findsOneWidget);
      expect(find.text('Hoy'), findsWidgets);

      // 4. Botón fijo "Calcular precio" visible sin necesidad de scroll
      expect(find.text('Calcular precio'), findsOneWidget);
      expect(find.byKey(const Key('calc_submit_button')), findsOneWidget);
    });

    testWidgets('Al pulsar "Calcular precio" navega a ResultScreen y el switch Detalles empieza apagado', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const CalculatorScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Pulsar botón Calcular precio
      await tester.tap(find.byKey(const Key('calc_submit_button')));
      await tester.pumpAndSettle();

      // Verifica navegación a ResultScreen
      expect(find.byType(ResultScreen), findsOneWidget);
      expect(find.text('Resultado'), findsOneWidget);
      expect(find.text('PRECIO DE VENTA'), findsOneWidget);
      expect(find.text('Copiar precio'), findsOneWidget);
      expect(find.text('Mensaje cliente'), findsOneWidget);
      expect(find.text('WhatsApp'), findsOneWidget);
      expect(find.text('Guardar como preset'), findsOneWidget);

      // Switch Detalles empieza apagado por defecto
      final detailsSwitchFinder = find.byKey(const Key('result_details_switch'));
      expect(detailsSwitchFinder, findsOneWidget);
      final detailsSwitch = tester.widget<Switch>(detailsSwitchFinder);
      expect(detailsSwitch.value, isFalse);

      // Con Detalles apagado no se muestran el desglose, la tabla comparativa ni la calculadora inversa
      expect(find.text('Desglose paso a paso'), findsNothing);
      expect(find.text('Calculadora inversa'), findsNothing);

      // Al encender Detalles se muestran el desglose numerado, la tabla comparativa y la calculadora inversa
      await tester.tap(detailsSwitchFinder);
      await tester.pumpAndSettle();

      expect(tester.widget<Switch>(detailsSwitchFinder).value, isTrue);
      expect(find.text('Desglose paso a paso'), findsOneWidget);
      expect(find.text('1. Costo en Bs'), findsOneWidget);
      expect(find.textContaining('Tabla comparativa por margen'), findsOneWidget);
      expect(find.text('Calculadora inversa'), findsOneWidget);
    });

    testWidgets('Botón "Volver" regresa a la Calculadora conservando todos los datos (tasa, costo, margen, comisiones, redondeo)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const CalculatorScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Cambiar tasa a Binance USDT en el carrusel horizontal
      await tester.tap(find.text('Binance USDT'));
      await tester.pump();

      // 2. Cambiar modo de margen a "Sobre venta"
      await tester.tap(find.text('Sobre venta'));
      await tester.pump();

      // 3. Editar Costo, Margen y Gasto fijo
      final costField = find.ancestor(
        of: find.text('Costo del producto (\$)'),
        matching: find.byType(TextField),
      );
      final marginField = find.ancestor(
        of: find.text('Margen s/venta (%)'),
        matching: find.byType(TextField),
      );
      final fixedField = find.ancestor(
        of: find.text('Gasto fijo (Bs)'),
        matching: find.byType(TextField),
      );
      await tester.enterText(costField, '25');
      await tester.enterText(marginField, '30');
      await tester.enterText(fixedField, '150');
      await tester.pump();

      // 4. Seleccionar chips de comisión y campo Otra
      await tester.tap(find.widgetWithText(FilterChip, '0.3% Pago Móvil'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilterChip, '1.5% Binance P2P'));
      await tester.pump();
      final otherField = find.ancestor(
        of: find.text('Otra'),
        matching: find.byType(TextField),
      );
      await tester.enterText(otherField, '0.5');
      await tester.pump();

      // 5. Seleccionar chip de redondeo Bs 50
      await tester.tap(find.text('Bs 50'));
      await tester.pump();

      // 6. Pulsar "Calcular precio" para ir a ResultScreen
      await tester.tap(find.byKey(const Key('calc_submit_button')));
      await tester.pumpAndSettle();

      expect(find.byType(ResultScreen), findsOneWidget);
      expect(find.textContaining('Binance USDT'), findsOneWidget);

      // 7. Pulsar botón fijo "Volver" abajo
      final backBtn = find.byKey(const Key('result_back_button'));
      expect(backBtn, findsOneWidget);
      await tester.tap(backBtn);
      await tester.pumpAndSettle();

      // 8. Verificar que regresó a CalculatorScreen y conservó todos los datos
      expect(find.byType(ResultScreen), findsNothing);
      expect(find.byType(CalculatorScreen), findsOneWidget);

      expect(tester.widget<TextField>(costField).controller?.text, '25');
      expect(tester.widget<TextField>(marginField).controller?.text, '30');
      expect(tester.widget<TextField>(fixedField).controller?.text, '150');

      final provField = find.ancestor(
        of: find.text('Plataforma / Prov.'),
        matching: find.byType(TextField),
      );
      final gatewayField = find.ancestor(
        of: find.text('Pago Móvil / Pasarela'),
        matching: find.byType(TextField),
      );
      expect(tester.widget<TextField>(provField).controller?.text, '1.5');
      expect(tester.widget<TextField>(gatewayField).controller?.text, '0.3');
      expect(tester.widget<TextField>(otherField).controller?.text, '0.5');

      final roundSegment = tester.widget<SegmentedButton<int>>(
        find.byType(SegmentedButton<int>),
      );
      expect(roundSegment.selected, {50});

      // Tasa Binance USDT sigue activa en el encabezado de Tasa del día
      expect(find.textContaining('Binance USDT ·'), findsOneWidget);
    });
  });
}
