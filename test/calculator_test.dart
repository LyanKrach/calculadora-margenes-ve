import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:calculadora_margenes_ve/models/margin_mode.dart';
import 'package:calculadora_margenes_ve/services/calculator.dart';
import 'package:calculadora_margenes_ve/utils/format.dart';

void main() {
  // Igual que main() de la app: sin esto DateFormat('es_VE') lanza
  // LocaleDataException. Este test existió para cazar ese bug (2026-11-09).
  setUpAll(() async {
    await initializeDateFormatting('es_VE');
  });
  group('MarginCalculator', () {
    test('ejemplo verificado sobre venta (onSale): \$10, BCV 897,54, margen 20 %, comisión 2 %', () {
      final price = MarginCalculator.salePrice(
        costUsd: 10,
        rate: 897.54,
        margin: 0.20,
        commissionProvider: 0.02,
        commissionGateway: 0,
        commissionOther: 0,
        marginMode: MarginMode.onSale,
      );
      // Costo en Bs = 10 × 897,54 = 8.975,40; Precio = 8.975,40 ÷ 0,78 = 11.506,92
      expect(price, closeTo(11506.92, 0.01));
    });

    test('ejemplo verificado sobre costo (onCost / Markup): \$0,66, tasa 964,20, margen 30 %', () {
      final exactPrice = MarginCalculator.salePrice(
        costUsd: 0.66,
        rate: 964.20,
        margin: 0.30,
        commissionProvider: 0,
        commissionGateway: 0,
        commissionOther: 0,
        marginMode: MarginMode.onCost,
      );
      // 0.66 * 964.20 * 1.30 = 636.372 * 1.30 = 827.2836 Bs
      expect(exactPrice, closeTo(827.28, 0.01));

      // Redondeo exacto (step = 0)
      expect(MarginCalculator.roundUp(exactPrice, 0), 827.28);

      // Si el vendedor vende a $0.86 en USD directo:
      final priceAt86Cents = 0.86 * 964.20;
      expect(priceAt86Cents, closeTo(829.21, 0.01));
    });

    test('redondeo: a múltiplos de 10, 50, 100 y modo Exacto (step = 0)', () {
      expect(MarginCalculator.roundUp(11506.92, 0), 11506.92);
      expect(MarginCalculator.roundUp(11506.92, 10), 11510);
      expect(MarginCalculator.roundUp(11506.92, 50), 11550);
      expect(MarginCalculator.roundUp(11506.92, 100), 11600);
    });

    test('inversa: precio 11.506,92 en onSale da margen real 20 %', () {
      final m = MarginCalculator.realMargin(
        costUsd: 10,
        rate: 897.54,
        totalCommission: 0.02,
        currentPriceBs: 11506.92,
        marginMode: MarginMode.onSale,
      );
      expect(m, closeTo(0.20, 0.001));
    });

    test('inversa: en onCost da margen sobre costo', () {
      final m = MarginCalculator.realMargin(
        costUsd: 0.66,
        rate: 964.20,
        totalCommission: 0,
        currentPriceBs: 827.2836,
        marginMode: MarginMode.onCost,
      );
      expect(m, closeTo(0.30, 0.001));
    });

    test('comisiones + margen >= 100 % en onSale lanza ArgumentError', () {
      expect(
        () => MarginCalculator.salePrice(
          costUsd: 10,
          rate: 897.54,
          margin: 0.60,
          commissionProvider: 0.40,
          commissionGateway: 0,
          commissionOther: 0,
          marginMode: MarginMode.onSale,
        ),
        throwsArgumentError,
      );
    });

    test('mediana Binance (par e impar)', () {
      expect(median([1, 3, 2]), 2);
      expect(median([1, 2, 3, 4]), 2.5);
    });

    test('brecha cambiaria exchangeGapPercent: cálculo estándar y casos borde', () {
      // Caso estándar: BCV 897.54, Binance 1045.00 -> gap ~16.429%
      final gap = MarginCalculator.exchangeGapPercent(
        bcvRate: 897.54,
        binanceRate: 1045.00,
      );
      expect(gap, closeTo(16.429, 0.001));

      // Caso negativo: Binance < BCV -> gap negativo
      final gapNegative = MarginCalculator.exchangeGapPercent(
        bcvRate: 1000.0,
        binanceRate: 900.0,
      );
      expect(gapNegative, -10.0);

      // Caso idéntico: 0%
      final gapZero = MarginCalculator.exchangeGapPercent(
        bcvRate: 1000.0,
        binanceRate: 1000.0,
      );
      expect(gapZero, 0.0);

      // Casos borde: BCV <= 0 -> 0.0
      expect(
        MarginCalculator.exchangeGapPercent(bcvRate: 0, binanceRate: 1000),
        0.0,
      );
      expect(
        MarginCalculator.exchangeGapPercent(bcvRate: -10, binanceRate: 1000),
        0.0,
      );
    });

    test('desglose (breakdown) cuadra al céntimo: costo + gasto fijo + comisiones + ganancia neta = precio final', () {
      const costUsd = 10.0;
      const rate = 897.54;
      const margin = 0.20;
      const prov = 0.015; // 1.5%
      const gateway = 0.003; // 0.3%
      const other = 0.002; // 0.2% -> total 2.0%
      const fixedBs = 50.0;

      final exact = MarginCalculator.salePrice(
        costUsd: costUsd,
        rate: rate,
        margin: margin,
        commissionProvider: prov,
        commissionGateway: gateway,
        commissionOther: other,
        fixedExpenseBs: fixedBs,
        marginMode: MarginMode.onSale,
      );
      final rounded = MarginCalculator.roundUp(exact, 10);
      final bd = MarginCalculator.breakdown(
        costUsd: costUsd,
        rate: rate,
        margin: margin,
        commissionProvider: prov,
        commissionGateway: gateway,
        commissionOther: other,
        fixedExpenseBs: fixedBs,
        finalPriceBs: rounded,
        marginMode: MarginMode.onSale,
      );

      // (8975.40 + 50) / 0.78 = 9025.40 / 0.78 = 11571.0256 -> redondeado a 10 = 11580.0
      expect(exact, closeTo(11571.03, 0.01));
      expect(rounded, 11580.0);

      // Comprobación contable exacta:
      final sumParts =
          bd.costBs + bd.fixedExpenseBs + bd.commissionBs + bd.netProfitBs;
      expect(sumParts, closeTo(bd.finalPriceBs, 0.0001));

      // Suma de sub-comisiones == comisión total
      expect(
        bd.commissionProviderBs + bd.commissionGatewayBs + bd.commissionOtherBs,
        closeTo(bd.commissionBs, 0.0001),
      );

      // Margen real en breakdown coincide con MarginCalculator.realMargin
      final invMargin = MarginCalculator.realMargin(
        costUsd: costUsd,
        rate: rate,
        totalCommission: prov + gateway + other,
        fixedExpenseBs: fixedBs,
        currentPriceBs: rounded,
        marginMode: MarginMode.onSale,
      );
      expect(bd.realMargin, closeTo(invMargin, 0.0001));
    });

    test('comparisonTable calcula ganancias netas y filtra márgenes que superan 100 % con comisiones altas', () {
      // Con comisión del 68 %, solo los márgenes 10 %, 15 %, 20 %, 25 % y 30 % son < 100 %
      final rows = MarginCalculator.comparisonTable(
        costUsd: 10,
        rate: 1000,
        totalCommission: 0.68,
        roundStep: 10,
        marginMode: MarginMode.onSale,
      );
      expect(rows.map((r) => r.margin).toList(), [0.10, 0.15, 0.20, 0.25, 0.30]);
      for (final row in rows) {
        final expectedNet = row.roundedPriceBs - 10000 - (row.roundedPriceBs * 0.68);
        expect(row.netProfitBs, closeTo(expectedNet, 0.001));
      }
    });
  });

  group('Formato es_VE (con initializeDateFormatting, como en main())', () {
    test('fmtBs usa punto de miles y coma decimal', () {
      expect(fmtBs(11506.92), '11.506,92');
    });

    test('DateFormat es_VE no lanza excepción', () {
      final s = DateFormat('dd/MM/yyyy HH:mm', 'es_VE')
          .format(DateTime(2026, 11, 9, 14, 30));
      expect(s, '09/11/2026 14:30');
    });
  });
}
