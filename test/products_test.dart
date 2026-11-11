import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:calculadora_margenes_ve/models/margin_mode.dart';
import 'package:calculadora_margenes_ve/models/product_item.dart';
import 'package:calculadora_margenes_ve/models/rate.dart';
import 'package:calculadora_margenes_ve/screens/products_screen.dart';
import 'package:calculadora_margenes_ve/services/price_list_formatter.dart';
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

    testWidgets('selector de categoría en formulario permite usar existente o crear nueva', (tester) async {
      tester.view.physicalSize = const Size(450, 950);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final service = ProductsService();
      final now = DateTime.utc(2026, 11, 10, 12, 0);
      await service.saveProduct(
        ProductItem(
          id: 'p_ff1',
          name: '100 + 10 Diamantes',
          category: 'Free Fire',
          costUsd: 0.66,
          marginPercent: 30,
          fixedExpenseBs: 0,
          commissionPlatform: 0.0,
          commissionPaymentMethod: 0.0,
          commissionOther: 0.0,
          roundStep: 10,
          rateSource: RateSource.bcvUsd,
          marginMode: MarginMode.onCost,
          createdAt: now,
          updatedAt: now,
        ),
      );

      await tester.pumpWidget(
        const MaterialApp(home: ProductsScreen()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Agregar producto'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sin categoría'));
      await tester.pumpAndSettle();
      expect(find.text('Free Fire').last, findsOneWidget);
      expect(find.text('+ Crear nueva categoría...').last, findsOneWidget);

      await tester.tap(find.text('+ Crear nueva categoría...').last);
      await tester.pumpAndSettle();

      expect(find.text('Nombre de la nueva categoría'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Nombre de la nueva categoría'),
        'Roblox',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Nombre del producto'),
        '800 Robux',
      );
      await tester.drag(
        find.byType(SingleChildScrollView).last,
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar producto'));
      await tester.pumpAndSettle();

      final all = await service.getProducts(syncRemote: false);
      expect(all.any((p) => p.name == '800 Robux' && p.category == 'Roblox'), isTrue);
    });

    testWidgets('hoja de compartir lista WhatsApp filtra categorías seleccionadas', (tester) async {
      final service = ProductsService();
      final now = DateTime.utc(2026, 11, 10, 12, 0);
      await service.saveProduct(
        ProductItem(
          id: 'p_1',
          name: '1060 + 106 Diamantes',
          category: 'Free Fire',
          costUsd: 6.0,
          marginPercent: 20,
          fixedExpenseBs: 0,
          commissionPlatform: 0,
          commissionPaymentMethod: 0,
          commissionOther: 0,
          roundStep: 0,
          rateSource: RateSource.bcvUsd,
          marginMode: MarginMode.onCost,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await service.saveProduct(
        ProductItem(
          id: 'p_2',
          name: '100 + 10 Diamantes',
          category: 'Free Fire',
          costUsd: 0.66,
          marginPercent: 30,
          fixedExpenseBs: 0,
          commissionPlatform: 0,
          commissionPaymentMethod: 0,
          commissionOther: 0,
          roundStep: 0,
          rateSource: RateSource.bcvUsd,
          marginMode: MarginMode.onCost,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await service.saveProduct(
        ProductItem(
          id: 'p_3',
          name: '400 Robux',
          category: 'Roblox',
          costUsd: 4.5,
          marginPercent: 20,
          fixedExpenseBs: 0,
          commissionPlatform: 0,
          commissionPaymentMethod: 0,
          commissionOther: 0,
          roundStep: 0,
          rateSource: RateSource.bcvUsd,
          marginMode: MarginMode.onCost,
          createdAt: now,
          updatedAt: now,
        ),
      );

      await tester.pumpWidget(const MaterialApp(home: ProductsScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Compartir lista de precios por WhatsApp'));
      await tester.pumpAndSettle();

      expect(find.text('Compartir lista de precios'), findsOneWidget);
      expect(find.text('Free Fire (2)'), findsOneWidget);
      expect(find.text('Roblox (1)'), findsOneWidget);

      // Desmarcar Roblox para compartir solo Free Fire
      await tester.tap(find.text('Roblox (1)'));
      await tester.pumpAndSettle();

      final previewField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Vista previa del mensaje (puedes editarlo)'),
      );
      final text = previewField.controller!.text;
      expect(text, contains('Free Fire'));
      expect(text, isNot(contains('400 Robux')));
      expect(
        text.indexOf('100 + 10 Diamantes') < text.indexOf('1060 + 106 Diamantes'),
        isTrue,
      );
    });
  });

  group('Categorías, orden natural y lista WhatsApp', () {
    ProductItem makeProd(String id, String name, String category, double costUsd) =>
        ProductItem(
          id: id,
          name: name,
          category: category,
          costUsd: costUsd,
          marginPercent: 30,
          fixedExpenseBs: 0,
          commissionPlatform: 0,
          commissionPaymentMethod: 0,
          commissionOther: 0,
          roundStep: 0,
          rateSource: RateSource.bcvUsd,
          marginMode: MarginMode.onCost,
          createdAt: DateTime.utc(2026, 11, 10),
          updatedAt: DateTime.utc(2026, 11, 10),
        );

    test('extrae categorías únicas ordenadas y omite vacías', () {
      final cats = extractUniqueCategories([
        makeProd('1', 'A', 'Roblox', 1),
        makeProd('2', 'B', 'free fire', 1),
        makeProd('3', 'C', 'Free Fire', 1),
        makeProd('4', 'D', '   ', 1),
      ]);
      expect(cats, ['free fire', 'Roblox']);
    });

    test('ordena cantidades numéricas antes de productos de texto', () {
      final names = [
        'Tarjeta Semanal',
        '1060 + 106 Diamantes',
        'Pase Booyah',
        '200 + 20 Diamantes',
        '100 + 10 Diamantes',
        '310 + 31 Diamantes',
      ]..sort(compareNaturalProductNames);

      expect(names, [
        '100 + 10 Diamantes',
        '200 + 20 Diamantes',
        '310 + 31 Diamantes',
        '1060 + 106 Diamantes',
        'Pase Booyah',
        'Tarjeta Semanal',
      ]);
    });

    test('buildWhatsAppPriceList respeta formato de una o varias categorías', () {
      final now = DateTime.utc(2026, 11, 10);
      final rates = {
        RateSource.bcvUsd: Rate(
          source: RateSource.bcvUsd,
          value: 900.0,
          fetchedAt: now,
        ),
      };
      final prods = [
        makeProd('1', '1060 + 106 Diamantes', 'Free Fire', 7.0),
        makeProd('2', '100 + 10 Diamantes', 'Free Fire', 0.78),
        makeProd('3', 'Pase Booyah', 'Free Fire', 2.57),
        makeProd('4', '800 Robux', 'Roblox', 5.0),
      ];

      final single = buildWhatsAppPriceList(
        products: prods,
        selectedCategories: {'Free Fire'},
        includeUncategorized: false,
        ratesMap: rates,
        globalCustomRate: 0,
      );
      expect(single, contains('Aquí tienes los precios de *Free Fire*:'));
      expect(single, isNot(contains('800 Robux')));
      expect(
        single.indexOf('100 + 10 Diamantes') <
            single.indexOf('1060 + 106 Diamantes'),
        isTrue,
      );
      expect(
        single.indexOf('1060 + 106 Diamantes') < single.indexOf('Pase Booyah'),
        isTrue,
      );

      final multi = buildWhatsAppPriceList(
        products: prods,
        selectedCategories: {'Free Fire', 'Roblox'},
        includeUncategorized: false,
        ratesMap: rates,
        globalCustomRate: 0,
      );
      expect(multi, contains('*Free Fire:*'));
      expect(multi, contains('*Roblox:*'));
      expect(multi, contains('800 Robux'));
    });

    test('saveProduct rechaza margen >= 100 % en lugar de ignorarlo', () async {
      final service = ProductsService();
      final invalidMargin = ProductItem(
        id: 'bad_1',
        name: 'Test 120%',
        costUsd: 5,
        marginPercent: 120,
        fixedExpenseBs: 0,
        commissionPlatform: 0,
        commissionPaymentMethod: 0,
        commissionOther: 0,
        roundStep: 10,
        rateSource: RateSource.bcvUsd,
        createdAt: DateTime.utc(2026, 11, 10),
        updatedAt: DateTime.utc(2026, 11, 10),
      );
      expect(
        () => service.saveProduct(invalidMargin),
        throwsArgumentError,
      );
    });
  });
}

