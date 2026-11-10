import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:calculadora_margenes_ve/models/margin_mode.dart';
import 'package:calculadora_margenes_ve/models/product_item.dart';
import 'package:calculadora_margenes_ve/models/rate.dart';
import 'package:calculadora_margenes_ve/screens/products_screen.dart';
import 'package:calculadora_margenes_ve/services/products_service.dart';

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

  group('ProductItem modelo y cálculo instantáneo de precios', () {
    test('round-trip toJson / fromJson incluye "v": 1 y calcula precio al instante', () {
      final now = DateTime.utc(2026, 11, 9, 20, 0);
      final prod = ProductItem(
        id: 'prod_1',
        name: 'Recarga 500 Diamantes',
        category: 'Gaming',
        costUsd: 10.0,
        marginPercent: 20.0,
        fixedExpenseBs: 0.0,
        commissionPlatform: 0.02,
        commissionPaymentMethod: 0.0,
        commissionOther: 0.0,
        roundStep: 10,
        rateSource: RateSource.bcvUsd,
        marginMode: MarginMode.onSale,
        createdAt: now,
        updatedAt: now,
      );

      final json = prod.toJson();
      expect(json['v'], 1);

      final restored = ProductItem.fromJson(json);
      expect(restored.isValid, isTrue);
      expect(restored.name, 'Recarga 500 Diamantes');
      expect(restored.category, 'Gaming');

      // Cálculo al instante con tasa BCV 897.54 -> 11510.0 Bs
      final price = restored.livePriceBs(897.54);
      expect(price, 11510.0);

      final bd = restored.liveBreakdown(897.54);
      expect(bd, isNotNull);
      expect(bd!.finalPriceBs, 11510.0);
    });

    test('ProductsService guarda, lista y elimina productos localmente', () async {
      final service = ProductsService();
      final now = DateTime.utc(2026, 11, 9, 20, 0);
      final prod = ProductItem(
        id: 'prod_test',
        name: 'Suscripción Streaming',
        category: 'Servicios',
        costUsd: 5.0,
        marginPercent: 25.0,
        fixedExpenseBs: 0.0,
        commissionPlatform: 0.015,
        commissionPaymentMethod: 0.003,
        commissionOther: 0.0,
        roundStep: 10,
        rateSource: RateSource.binanceUsdt,
        createdAt: now,
        updatedAt: now,
      );

      await service.saveProduct(prod);
      final list = await service.getProducts(syncRemote: false);
      expect(list.length, 1);
      expect(list.first.name, 'Suscripción Streaming');

      await service.deleteProduct('prod_test');
      expect(await service.getProducts(syncRemote: false), isEmpty);
    });
  });

  group('ProductsScreen UI: catálogo con precios al instante e historial', () {
    testWidgets('muestra productos con precio en Bs al instante y permite agregar uno nuevo', (tester) async {
      final service = ProductsService();
      final now = DateTime.utc(2026, 11, 9, 20, 0);
      await service.saveProduct(
        ProductItem(
          id: 'p_1',
          name: 'Pase Élite',
          category: 'Gaming',
          costUsd: 10.0,
          marginPercent: 20.0,
          fixedExpenseBs: 0.0,
          commissionPlatform: 0.02,
          commissionPaymentMethod: 0.0,
          commissionOther: 0.0,
          roundStep: 10,
          rateSource: RateSource.bcvUsd,
          marginMode: MarginMode.onSale,
          createdAt: now,
          updatedAt: now,
        ),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: ProductsScreen(),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      // Debe mostrar el producto guardado y su precio calculado al instante (11.530,00 Bs)
      expect(find.text('Pase Élite'), findsOneWidget);
      expect(find.text('11.530,00 Bs'), findsOneWidget);

      // Cambiar a la pestaña de Historial Calculado
      await tester.tap(find.text('Historial Calculado'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Aún no hay productos calculados en el historial'),
        findsOneWidget,
      );
    });
  });
}

