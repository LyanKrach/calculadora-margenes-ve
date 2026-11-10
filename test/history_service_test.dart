import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:calculadora_margenes_ve/models/calculation_item.dart';
import 'package:calculadora_margenes_ve/models/margin_mode.dart';
import 'package:calculadora_margenes_ve/models/rate.dart';
import 'package:calculadora_margenes_ve/screens/calculator_screen.dart';
import 'package:calculadora_margenes_ve/services/history_service.dart';

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

  group('Modelos HistoryEntry y Preset (separados, con "v": 1 y fallback)', () {
    test('round-trip de Preset incluye "v": 1 y recalcula precio con tasa vigente', () {
      final preset = Preset(
        id: 'preset_diamantes_100',
        title: 'Recarga 100 Diamantes',
        costUsd: 10.0,
        marginPercent: 20.0,
        fixedExpenseBs: 50.0,
        commissionPlatform: 0.015,
        commissionPaymentMethod: 0.003,
        commissionOther: 0.002,
        roundStep: 50,
        rateSource: RateSource.binanceUsdt,
        marginMode: MarginMode.onSale,
        createdAt: DateTime.utc(2026, 11, 9, 16, 0),
      );

      final json = preset.toJson();
      expect(json['v'], 1);
      expect(json.containsKey('isPreset'), isFalse);

      final restored = Preset.fromJson(json);
      expect(restored.isValid, isTrue);
      expect(restored.id, 'preset_diamantes_100');
      expect(restored.title, 'Recarga 100 Diamantes');
      expect(restored.costUsd, 10.0);
      expect(restored.marginPercent, 20.0);
      expect(restored.fixedExpenseBs, 50.0);
      expect(restored.commissionPlatform, 0.015);
      expect(restored.commissionPaymentMethod, 0.003);
      expect(restored.commissionOther, 0.002);
      expect(restored.roundStep, 50);
      expect(restored.rateSource, RateSource.binanceUsdt);

      // Recálculo con tasa vigente (1000 Bs/$):
      // Costo = 10000 + 50 = 10050; divisor = 1 - 0.02 - 0.20 = 0.78
      // Exacto = 12884.615 -> redondeado a 50 = 12900
      final priceAt1000 = restored.recalculatePriceBs(1000.0);
      expect(priceAt1000, 12900.0);
    });

    test('round-trip de HistoryEntry congela rateValue y finalPriceBs', () {
      final entry = HistoryEntry(
        id: 'h_1',
        title: 'Cálculo \$10,00 @ BCV Dólar',
        costUsd: 10.0,
        marginPercent: 20.0,
        fixedExpenseBs: 0.0,
        commissionPlatform: 0.02,
        commissionPaymentMethod: 0.0,
        commissionOther: 0.0,
        roundStep: 10,
        rateSource: RateSource.bcvUsd,
        rateValue: 897.54,
        finalPriceBs: 11510.0,
        timestamp: DateTime.utc(2026, 11, 9, 16, 0),
      );

      final json = entry.toJson();
      expect(json['v'], 1);

      final restored = HistoryEntry.fromJson(json);
      expect(restored.isValid, isTrue);
      expect(restored.rateValue, 897.54);
      expect(restored.finalPriceBs, 11510.0);
    });

    test('tolerancia a JSON corrupto en HistoryEntry y Preset', () {
      expect(HistoryEntry.listFromJson('corrupto{{{'), isEmpty);
      expect(Preset.listFromJson('corrupto{{{'), isEmpty);
      expect(HistoryEntry.fromJson({'mal': 123}).isValid, isFalse);
      expect(Preset.fromJson({'mal': 123}).isValid, isFalse);
    });
  });

  group('HistoryService persistencia y poda a 15 elementos', () {
    test('mantiene máximo 15 elementos en historial (más reciente primero)', () async {
      final service = HistoryService();
      for (var i = 1; i <= 18; i++) {
        await service.addHistoryEntry(
          HistoryEntry(
            id: 'id_$i',
            title: 'Item $i',
            costUsd: i.toDouble(),
            marginPercent: 20.0,
            fixedExpenseBs: 0,
            commissionPlatform: 0.02,
            commissionPaymentMethod: 0,
            commissionOther: 0,
            roundStep: 10,
            rateSource: RateSource.bcvUsd,
            rateValue: 900.0,
            finalPriceBs: 1200.0 * i,
            timestamp: DateTime.utc(2026, 11, 9, 12, i),
          ),
        );
      }

      final history = await service.getHistory();
      expect(history.length, 15);
      expect(history.first.id, 'id_18');
      expect(history.last.id, 'id_4');
    });
  });

  group('Widget test: HistoryPresetsSheet sincroniza controllers y tasa seleccionada', () {
    testWidgets('aplicar un Preset desde el BottomSheet sincroniza todos los controllers y la tasa', (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final service = HistoryService();
      await service.savePreset(
        Preset(
          id: 'p_sync',
          title: 'Combo Gamer',
          costUsd: 25.5,
          marginPercent: 30.0,
          fixedExpenseBs: 120.0,
          commissionPlatform: 0.015, // 1.5%
          commissionPaymentMethod: 0.003, // 0.3%
          commissionOther: 0.01, // 1.0%
          roundStep: 50,
          rateSource: RateSource.binanceUsdt,
          marginMode: MarginMode.onSale,
          createdAt: DateTime.utc(2026, 11, 9, 15, 0),
        ),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: CalculatorScreen(),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      // Abrir HistoryPresetsSheet desde el único botón de AppBar
      final sheetBtn = find.byTooltip('Historial y plantillas');
      expect(sheetBtn, findsOneWidget);
      await tester.tap(sheetBtn);
      await tester.pumpAndSettle();

      // Cambiar a la pestaña "Plantillas"
      await tester.tap(find.text('Plantillas'));
      await tester.pumpAndSettle();

      expect(find.text('Combo Gamer'), findsOneWidget);
      await tester.tap(find.text('Combo Gamer'));
      await tester.pumpAndSettle();

      // Verificar aviso de tasa guardada/desactualizada en SnackBar
      expect(find.textContaining('Usando tasa de hace'), findsOneWidget);

      // Verificar que la tarjeta de tasa seleccionada es Binance USDT (con check_circle)
      final binanceTile = find.ancestor(
        of: find.text(RateSource.binanceUsdt.label),
        matching: find.byType(ListTile),
      );
      expect(
        find.descendant(of: binanceTile, matching: find.byIcon(Icons.check_circle)),
        findsOneWidget,
      );

      // Verificar que los 6 controllers numéricos se sincronizaron exactamente
      String textOfField(String label) {
        final tf = tester.widget<TextField>(
          find.ancestor(of: find.text(label), matching: find.byType(TextField)),
        );
        return tf.controller?.text ?? '';
      }

      expect(textOfField('Costo del producto (\$)'), '25.5');
      expect(textOfField('Margen s/venta (%)'), '30');
      expect(textOfField('Gasto fijo (Bs)'), '120');
      expect(textOfField('Plataforma / Prov.'), '1.5');
      expect(textOfField('Pago Móvil / Pasarela'), '0.3');
      expect(textOfField('Otra'), '1');

      // Verificar que el SegmentedButton tiene seleccionado Bs 50
      final segmented = tester.widget<SegmentedButton<int>>(
        find.byType(SegmentedButton<int>),
      );
      expect(segmented.selected, {50});
    });
  });
}
