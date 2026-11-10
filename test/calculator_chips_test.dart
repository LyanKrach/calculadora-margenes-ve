import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:calculadora_margenes_ve/screens/calculator_screen.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_VE');
  });

  testWidgets('Chips de comisiones: asignación directa y toggle a vacío (determinista)', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: CalculatorScreen(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // Buscar primer chip: 0.3% Pago Móvil
    final pagoMovilFinder = find.widgetWithText(FilterChip, '0.3% Pago Móvil');
    expect(pagoMovilFinder, findsOneWidget);

    // 1. Tocar chip: debe asignar 0.3 al campo de pasarela / pago móvil y marcar selected = true
    await tester.tap(pagoMovilFinder);
    await tester.pump();

    final chip = tester.widget<FilterChip>(find.byType(FilterChip).first);
    expect(chip.selected, isTrue);
    expect(find.widgetWithText(TextField, '0.3'), findsOneWidget);

    // 2. Tocar nuevamente el chip: debe limpiar a '' y marcar selected = false
    await tester.tap(pagoMovilFinder);
    await tester.pump();

    final chipAfterToggleOff = tester.widget<FilterChip>(find.byType(FilterChip).first);
    expect(chipAfterToggleOff.selected, isFalse);
    expect(find.widgetWithText(TextField, '0.3'), findsNothing);

    final gatewayField = tester.widget<TextField>(
      find.ancestor(
        of: find.text('Pago Móvil / Pasarela'),
        matching: find.byType(TextField),
      ),
    );
    expect(gatewayField.controller?.text, '');

    // 3. Tocar chip de 1.5% Binance P2P
    final binanceFinder = find.widgetWithText(FilterChip, '1.5% Binance P2P');
    await tester.tap(binanceFinder);
    await tester.pump();

    final binanceChip = tester.widget<FilterChip>(binanceFinder);
    expect(binanceChip.selected, isTrue);
    expect(find.widgetWithText(TextField, '1.5'), findsOneWidget);

    // 4. Tocar 2.0% Operativa (mismo campo de plataforma): debe asignar 2 y desmarcar 1.5%
    final operativaFinder = find.widgetWithText(FilterChip, '2.0% Operativa');
    await tester.ensureVisible(operativaFinder);
    await tester.tap(operativaFinder);
    await tester.pump();

    final operativaChip = tester.widget<FilterChip>(operativaFinder);
    expect(operativaChip.selected, isTrue);

    final binanceChipAfter = tester.widget<FilterChip>(binanceFinder);
    expect(binanceChipAfter.selected, isFalse);
    expect(find.widgetWithText(TextField, '2'), findsOneWidget);
  });
}
