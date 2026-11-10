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

  group('RatesService fuentes rápidas BCV y fallback DolarApi', () {
    test('DolarVZLA CDN parsea USD, EUR y effectiveDate para mañana', () async {
      final mockClient = MockClient((request) async {
        if (request.url.host == 'rates.dolarvzla.com') {
          return http.Response(
            jsonEncode({
              'current': {
                'date': '2026-11-11',
                'usd': 901.6175,
                'eur': 1007.96328412,
              },
              'previous': {
                'date': '2026-11-10',
                'usd': 899.2705,
                'eur': 1006.60742688,
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.host == 'www.bcv.org.ve') {
          throw Exception('Connection blocked outside VE');
        }
        return http.Response('Not Found', 404);
      });

      final service = RatesService(client: mockClient);
      final usd = await service.fetchBcvUsd();
      final eur = await service.fetchEuroBcv();

      expect(usd.source, RateSource.bcvUsd);
      expect(usd.value, 901.62);
      expect(usd.effectiveDate, '2026-11-11');
      expect(usd.isCached, isFalse);

      expect(eur.source, RateSource.euroBcv);
      expect(eur.value, 1007.96);
      expect(eur.effectiveDate, '2026-11-11');
      expect(eur.isCached, isFalse);
    });

    test('HTML directo www.bcv.org.ve parsea USD/EUR y gana si tiene fecha más reciente', () async {
      const bcvHtml = '''
        <html><body>
          <div id="euro"><strong> 1.007,96328412 </strong></div>
          <div id="dolar"><strong> 901,61750000 </strong></div>
          <span class="date-display-single" content="2026-11-11T00:00:00-04:00">Miércoles, 11 Noviembre 2026</span>
        </body></html>
      ''';

      final mockClient = MockClient((request) async {
        if (request.url.host == 'www.bcv.org.ve') {
          return http.Response(bcvHtml, 200);
        }
        if (request.url.host == 'rates.dolarvzla.com') {
          return http.Response(
            jsonEncode({
              'current': {
                'date': '2026-11-10',
                'usd': 899.2705,
                'eur': 1006.60742688,
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final service = RatesService(client: mockClient);
      final usd = await service.fetchBcvUsd();
      final eur = await service.fetchEuroBcv();

      expect(usd.value, 901.62);
      expect(usd.effectiveDate, '2026-11-11');
      expect(eur.value, 1007.96);
      expect(eur.effectiveDate, '2026-11-11');
    });

    test('Elige DolarVZLA si tiene fecha más reciente que www.bcv.org.ve', () async {
      const staleBcvHtml = '''
        <html><body>
          <div id="euro"><strong> 1.006,60742688 </strong></div>
          <div id="dolar"><strong> 899,27050000 </strong></div>
          <span content="2026-11-10T00:00:00-04:00">Martes, 10 Noviembre 2026</span>
        </body></html>
      ''';

      final mockClient = MockClient((request) async {
        if (request.url.host == 'www.bcv.org.ve') {
          return http.Response(staleBcvHtml, 200);
        }
        if (request.url.host == 'rates.dolarvzla.com') {
          return http.Response(
            jsonEncode({
              'current': {
                'date': '2026-11-11',
                'usd': 901.6175,
                'eur': 1007.96328412,
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final service = RatesService(client: mockClient);
      final usd = await service.fetchBcvUsd();
      final eur = await service.fetchEuroBcv();

      expect(usd.value, 901.62);
      expect(usd.effectiveDate, '2026-11-11');
      expect(eur.value, 1007.96);
      expect(eur.effectiveDate, '2026-11-11');
    });

    test('BCV Today actúa como respaldo secundario si BCV directo y DolarVZLA fallan', () async {
      final mockClient = MockClient((request) async {
        if (request.url.host == 'rates.dolarvzla.com') {
          return http.Response('Service Unavailable', 503);
        }
        if (request.url.host == 'www.bcv.org.ve') {
          throw Exception('Connection blocked');
        }
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
      final usd = await service.fetchBcvUsd();
      final eur = await service.fetchEuroBcv();

      expect(usd.value, 899.27);
      expect(usd.effectiveDate, '2026-11-10');
      expect(eur.value, 1006.61);
      expect(eur.effectiveDate, '2026-11-10');
    });

    test('DolarApi USD y EUR funcionan como respaldo si todas las fuentes rápidas fallan', () async {
      final mockClient = MockClient((request) async {
        if (request.url.host == 'rates.dolarvzla.com') {
          return http.Response('Internal Server Error', 500);
        }
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
        if (request.url.host == 've.dolarapi.com' && request.url.path.contains('euros/oficial')) {
          return http.Response(
            jsonEncode({
              'moneda': 'EUR',
              'promedio': 1006.6074,
              'fechaActualizacion': '2026-11-10T00:00:00-04:00',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final service = RatesService(client: mockClient);
      final usd = await service.fetchBcvUsd();
      final eur = await service.fetchEuroBcv();

      expect(usd.source, RateSource.bcvUsd);
      expect(usd.value, 899.27);
      expect(usd.effectiveDate, '2026-11-10');
      expect(usd.isCached, isFalse);

      expect(eur.source, RateSource.euroBcv);
      expect(eur.value, 1006.61);
      expect(eur.effectiveDate, '2026-11-10');
      expect(eur.isCached, isFalse);
    });
  });
}

