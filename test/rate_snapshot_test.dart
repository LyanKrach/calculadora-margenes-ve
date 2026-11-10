import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:calculadora_margenes_ve/models/rate_snapshot.dart';
import 'package:calculadora_margenes_ve/services/rates_service.dart';
import 'package:calculadora_margenes_ve/widgets/rates_bar_chart.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_VE');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('RateSnapshot serialización y tolerancia a fallos', () {
    test('round-trip toJson / fromJson incluye "v": 1 y conserva campos', () {
      final original = RateSnapshot(
        timestamp: DateTime.utc(2026, 11, 9, 16, 0),
        bcvUsd: 897.5383,
        binanceUsdt: 1045.00,
        euroBcv: 1001.186,
      );

      final json = original.toJson();
      expect(json['v'], 1);

      final restored = RateSnapshot.fromJson(json);
      expect(restored.isValid, isTrue);
      expect(restored.version, 1);
      expect(restored.timestamp, original.timestamp);
      expect(restored.bcvUsd, closeTo(897.5383, 0.0001));
      expect(restored.binanceUsdt, closeTo(1045.00, 0.0001));
      expect(restored.euroBcv, closeTo(1001.186, 0.0001));
    });

    test('listFromJson y fromJson hacen fallback seguro ante JSON corrupto', () {
      expect(RateSnapshot.listFromJson(null), isEmpty);
      expect(RateSnapshot.listFromJson(''), isEmpty);
      expect(RateSnapshot.listFromJson('{no_es_lista: true}'), isEmpty);
      expect(RateSnapshot.listFromJson('json_invalido{{{'), isEmpty);

      final corruptItem = RateSnapshot.fromJson({
        'v': 1,
        'timestamp': 'fecha-rota',
        'bcvUsd': 'texto_invalido',
      });
      expect(corruptItem.isValid, isFalse);
    });
  });

  group('Lógica de append en RatesService (variación > 0.5% o >= 1h, máx 10)', () {
    test('no hace append si no cambia (< 0.5%) en < 1h; sí hace append si cambia > 0.5% o pasa >= 1h', () async {
      final service = RatesService();
      final t0 = DateTime.utc(2026, 11, 9, 12, 0);

      // 1. Primer snapshot siempre se guarda
      final s1 = RateSnapshot(
        timestamp: t0,
        bcvUsd: 900.0,
        binanceUsdt: 1000.0,
        euroBcv: 980.0,
      );
      expect(await service.recordSnapshotIfNeeded(s1), isTrue);
      expect((await service.getSnapshots()).length, 1);

      // 2. Variación menor a 0.5% (+0.2%) y solo pasaron 15 minutos -> NO append
      final s2 = RateSnapshot(
        timestamp: t0.add(const Duration(minutes: 15)),
        bcvUsd: 901.8, // +0.2%
        binanceUsdt: 1001.0, // +0.1%
        euroBcv: 980.0,
      );
      expect(await service.recordSnapshotIfNeeded(s2), isFalse);
      expect((await service.getSnapshots()).length, 1);

      // 3. Sin variación (0%), pero pasó exactamente 1 hora -> SÍ append
      final s3 = RateSnapshot(
        timestamp: t0.add(const Duration(hours: 1)),
        bcvUsd: 900.0,
        binanceUsdt: 1000.0,
        euroBcv: 980.0,
      );
      expect(await service.recordSnapshotIfNeeded(s3), isTrue);
      expect((await service.getSnapshots()).length, 2);

      // 4. Pasaron solo 10 minutos, pero Binance subió > 0.5% (+1.0%) -> SÍ append
      final s4 = RateSnapshot(
        timestamp: t0.add(const Duration(hours: 1, minutes: 10)),
        bcvUsd: 900.0,
        binanceUsdt: 1010.0, // +1.0% respecto a 1000.0
        euroBcv: 980.0,
      );
      expect(await service.recordSnapshotIfNeeded(s4), isTrue);
      expect((await service.getSnapshots()).length, 3);
    });

    test('poda FIFO a máximo 10 snapshots', () async {
      final service = RatesService();
      final base = DateTime.utc(2026, 11, 9, 0, 0);

      for (var i = 0; i < 12; i++) {
        await service.recordSnapshotIfNeeded(
          RateSnapshot(
            timestamp: base.add(Duration(hours: i)),
            bcvUsd: 900.0 + i,
            binanceUsdt: 1000.0 + i,
            euroBcv: 950.0 + i,
          ),
        );
      }

      final stored = await service.getSnapshots();
      expect(stored.length, 10);
      // Debe conservar desde i=2 hasta i=11
      expect(stored.first.bcvUsd, 902.0);
      expect(stored.last.bcvUsd, 911.0);
    });
  });

  group('RatesBarChart accesibilidad y ventana', () {
    testWidgets('expone Semantics(label: BCV X · Binance Y · Brecha Z%) y ventana de actualizaciones', (tester) async {
      final handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RatesBarChart(
                bcvRate: 897.54,
                binanceRate: 1045.00,
                euroRate: 1001.19,
                snapshots: [
                  RateSnapshot(
                    timestamp: DateTime.utc(2026, 11, 9, 10, 0),
                    bcvUsd: 895.0,
                    binanceUsdt: 1040.0,
                    euroBcv: 998.0,
                  ),
                  RateSnapshot(
                    timestamp: DateTime.utc(2026, 11, 9, 12, 0),
                    bcvUsd: 897.54,
                    binanceUsdt: 1045.0,
                    euroBcv: 1001.19,
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verificar label de Semantics con BCV, Binance y Brecha
        expect(
          find.bySemanticsLabel(RegExp(r'BCV 897,54 · Binance 1\.045,00 · Brecha 16\.43%')),
          findsOneWidget,
        );

        // Verificar documentación de ventana en la UI ("últimas N actualizaciones")
        expect(
          find.text('Ventana registrada: últimas 2 actualizaciones'),
          findsOneWidget,
        );
      } finally {
        handle.dispose();
      }
    });
  });
}

