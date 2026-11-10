import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:calculadora_margenes_ve/models/rate.dart';
import 'package:calculadora_margenes_ve/services/rates_service.dart';
import 'package:calculadora_margenes_ve/utils/format.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('formatEffectiveDate', () {
    test('formatea correctamente fecha de hoy y de mañana', () {
      final now = DateTime.now();
      final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final tomorrow = now.add(const Duration(days: 1));
      final tomorrowStr = '${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}';

      final resToday = formatEffectiveDate(todayStr);
      expect(resToday, contains('Hoy'));
      expect(resToday, startsWith('Vigente:'));

      final resTomorrow = formatEffectiveDate(tomorrowStr);
      expect(resTomorrow, contains('Mañana'));
      expect(resTomorrow, startsWith('Vigente:'));
    });
  });

  group('RatesService BCV Today y fallback DolarApi', () {
    test('BCV Today es la fuente principal y parsea USD y effectiveDate', () async {
      final mockClient = MockClient((request) async {
        if (request.url.host == 'bcv.today') {
          return http.Response(
            jsonEncode({
              'USD': 899.2705,
              'EUR': 1006.6074,
              'effective_date': '2026-11-10',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final service = RatesService(client: mockClient);
      final rate = await service.fetchBcvUsd();

      expect(rate.source, RateSource.bcvUsd);
      expect(rate.value, 899.27);
      expect(rate.effectiveDate, '2026-11-10');
      expect(rate.isCached, isFalse);
    });

    test('DolarApi funciona como respaldo si BCV Today falla', () async {
      final mockClient = MockClient((request) async {
        if (request.url.host == 'bcv.today') {
          return http.Response('Internal Server Error', 500);
        }
        if (request.url.host == 'www.bcv.org.ve') {
          throw Exception('Connection blocked');
        }
        if (request.url.host == 've.dolarapi.com' && request.url.path.contains('dolares/oficial')) {
          return http.Response(
            jsonEncode({
              'moneda': 'USD',
              'promedio': 899.2705,
              'fechaActualizacion': '2026-11-10T00:00:00-04:00',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final service = RatesService(client: mockClient);
      final rate = await service.fetchBcvUsd();

      expect(rate.source, RateSource.bcvUsd);
      expect(rate.value, 899.27);
      expect(rate.effectiveDate, '2026-11-10');
      expect(rate.isCached, isFalse);
    });
  });
}

