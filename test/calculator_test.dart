import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:calculadora_margenes_ve/services/calculator.dart';
import 'package:calculadora_margenes_ve/utils/format.dart';

void main() {
  // Igual que main() de la app: sin esto DateFormat('es_VE') lanza
  // LocaleDataException. Este test existió para cazar ese bug (2026-11-09).
  setUpAll(() async {
    await initializeDateFormatting('es_VE');
  });
  group('MarginCalculator', () {
    test('ejemplo verificado 2026-11-09: \$10, BCV 897,54, margen 20 %, comisión 2 %', () {
      final price = MarginCalculator.salePrice(
        costUsd: 10,
        rate: 897.54,
        margin: 0.20,
        commissionProvider: 0.02,
        commissionGateway: 0,
        commissionOther: 0,
      );
      // Costo en Bs = 10 × 897,54 = 8.975,40; Precio = 8.975,40 ÷ 0,78 = 11.506,92
      expect(price, closeTo(11506.92, 0.01));
    });

    test('redondeo siempre hacia arriba', () {
      expect(MarginCalculator.roundUp(11506.92, 10), 11510);
      expect(MarginCalculator.roundUp(11506.92, 50), 11550);
      expect(MarginCalculator.roundUp(11506.92, 100), 11600);
    });

    test('inversa: precio 11.506,92 da margen real 20 %', () {
      final m = MarginCalculator.realMargin(
        costUsd: 10,
        rate: 897.54,
        totalCommission: 0.02,
        currentPriceBs: 11506.92,
      );
      expect(m, closeTo(0.20, 0.001));
    });

    test('comisiones + margen >= 100 % lanza ArgumentError', () {
      expect(
        () => MarginCalculator.salePrice(
          costUsd: 10,
          rate: 897.54,
          margin: 0.60,
          commissionProvider: 0.40,
          commissionGateway: 0,
          commissionOther: 0,
        ),
        throwsArgumentError,
      );
    });

    test('mediana Binance (par e impar)', () {
      expect(median([1, 3, 2]), 2);
      expect(median([1, 2, 3, 4]), 2.5);
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
