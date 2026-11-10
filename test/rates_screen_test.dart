import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:calculadora_margenes_ve/screens/rates_screen.dart';

class _FailingHttpClient extends Fake implements HttpClient {
  @override
  bool autoUncompress = true;
  @override
  Duration idleTimeout = const Duration(seconds: 15);

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    throw const SocketException('Test offline fallback');
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);
  @override
  Future<HttpClientRequest> postUrl(Uri url) => openUrl('POST', url);
}

class _TestHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _FailingHttpClient();
}

void main() {
  setUpAll(() async {
    HttpOverrides.global = _TestHttpOverrides();
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('es_VE');
  });

  testWidgets('RatesScreen renderiza y muestra la tarjeta de Brecha Cambiaria', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: RatesScreen(),
      ),
    );
    // Con _TestHttpOverrides la red falla de inmediato y cae en el fallback verificado
    await tester.pump();
    await tester.pumpAndSettle();

    // Verificar presencia del título de la pantalla
    expect(find.text('Tasas del día'), findsOneWidget);

    // Verificar presencia de la tarjeta de Brecha Cambiaria
    expect(find.text('Brecha Cambiaria (Binance vs BCV)'), findsOneWidget);

    // Verificar que se muestre el diferencial y cálculo
    expect(find.textContaining('Diferencia: +'), findsOneWidget);
    expect(find.textContaining('diferencial'), findsOneWidget);
  });
}
