import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/rate.dart';
import 'calculator.dart';

/// Servicio de tasas: BCV dólar, Binance USDT P2P, Euro BCV y personalizada.
///
/// EN APP NATIVA NO HAY BLOQUEO CORS: ese bloqueo solo afecta a la web.
/// Por eso Binance se consulta directo desde la app con POST a
/// p2p.binance.com; en la versión web ese mismo endpoint es bloqueado
/// por el navegador (sin Access-Control-Allow-Origin).
///
/// Cadena de respaldo (fallback) por tasa:
/// - BCV dólar: DolarApi oficial → DolarApi paralelo NO se usa como
///   respaldo del BCV (es otra tasa); si falla, se usa la caché.
/// - Binance USDT: P2P adv/search (mediana) → quote-price de Binance
///   (1043,50 verificado el 2026-11-09) → DolarApi paralelo → caché.
/// - Euro BCV: DolarApi euros oficial → caché.
/// - Personalizada: nunca toca la red; la escribe el usuario.
///
/// Caché offline: última tasa + fecha en SharedPreferences, por fuente.
/// Sin conexión se muestra la última tasa guardada con su fecha y la
/// etiqueta "sin conexión — valor guardado".
class RatesService {
  RatesService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _timeout = Duration(seconds: 10);

  // Endpoints verificados 2026-11-09.
  static const _dolarApiUsd = 'https://ve.dolarapi.com/v1/dolares/oficial';
  static const _dolarApiEur = 'https://ve.dolarapi.com/v1/euros/oficial';
  static const _dolarApiParallel = 'https://ve.dolarapi.com/v1/dolares/paralelo';
  static const _binanceP2p =
      'https://p2p.binance.com/bapi/c2c/v2/friendly/c2c/adv/search';
  static const _binanceQuote =
      'https://www.binance.com/bapi/c2c/v1/public/c2c/agent/quote-price'
      '?fiat=VES&asset=USDT&tradeType=BUY';

  static const _cachePrefix = 'rate_cache_';
  static const _customRateKey = 'custom_rate_value';
  static const _dolarVzlaKeyKey = 'dolarvzla_api_key';

  // Valores reales observados el 2026-11-09 (último recurso si no hay
  // red ni caché: la app nunca arranca sin una tasa que mostrar).
  static const double fallbackBcvUsd = 897.5383;
  static const double fallbackEuroBcv = 1001.186;
  static const double fallbackBinanceUsdt = 1045.00;

  // ------------------------------------------------------------------
  // BCV dólar — DolarApi, campo `promedio`.
  // ------------------------------------------------------------------
  Future<Rate> fetchBcvUsd() async {
    try {
      final res = await _client
          .get(Uri.parse(_dolarApiUsd))
          .timeout(_timeout);
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final value = (json['promedio'] as num).toDouble();
        final rate = Rate(
          source: RateSource.bcvUsd,
          value: value,
          fetchedAt: DateTime.now(),
        );
        await _saveToCache(rate);
        return rate;
      }
    } catch (_) {
      // Cae al caché / valor de respaldo.
    }
    return _cachedOrFallback(RateSource.bcvUsd, fallbackBcvUsd);
  }

  // ------------------------------------------------------------------
  // Euro BCV — DolarApi, campo `promedio`.
  // ------------------------------------------------------------------
  Future<Rate> fetchEuroBcv() async {
    try {
      final res = await _client
          .get(Uri.parse(_dolarApiEur))
          .timeout(_timeout);
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final value = (json['promedio'] as num).toDouble();
        final rate = Rate(
          source: RateSource.euroBcv,
          value: value,
          fetchedAt: DateTime.now(),
        );
        await _saveToCache(rate);
        return rate;
      }
    } catch (_) {}
    return _cachedOrFallback(RateSource.euroBcv, fallbackEuroBcv);
  }

  // ------------------------------------------------------------------
  // Binance USDT P2P — mediana de los 10 primeros anuncios de COMPRA
  // (tradeType BUY = usuarios que compran USDT con VES; es el precio
  // que paga quien vende USDT, el relevante para un vendedor en VE).
  // Respaldo 1: quote-price de Binance. Respaldo 2: DolarApi paralelo.
  // ------------------------------------------------------------------
  Future<Rate> fetchBinanceUsdt() async {
    // Intento 1: P2P adv/search (mediana de adv.price).
    try {
      final res = await _client
          .post(
            Uri.parse(_binanceP2p),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'fiat': 'VES',
              'asset': 'USDT',
              'tradeType': 'BUY',
              'page': 1,
              'rows': 10,
            }),
          )
          .timeout(_timeout);
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final data = (json['data'] as List?) ?? [];
        final prices = data
            .map((e) => double.tryParse(
                (e as Map<String, dynamic>)['adv']['price'].toString()))
            .whereType<double>()
            .toList();
        if (prices.isNotEmpty) {
          final rate = Rate(
            source: RateSource.binanceUsdt,
            value: median(prices),
            fetchedAt: DateTime.now(),
          );
          await _saveToCache(rate);
          return rate;
        }
      }
    } catch (_) {}

    // Intento 2: quote-price público de Binance.
    try {
      final res = await _client
          .get(Uri.parse(_binanceQuote))
          .timeout(_timeout);
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final priceStr = json['data']?['price']?.toString();
        final value = double.tryParse(priceStr ?? '');
        if (value != null && value > 0) {
          final rate = Rate(
            source: RateSource.binanceUsdt,
            value: value,
            fetchedAt: DateTime.now(),
          );
          await _saveToCache(rate);
          return rate;
        }
      }
    } catch (_) {}

    // Intento 3: DolarApi paralelo (aproximación al USDT P2P).
    try {
      final res = await _client
          .get(Uri.parse(_dolarApiParallel))
          .timeout(_timeout);
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final value = (json['promedio'] as num).toDouble();
        final rate = Rate(
          source: RateSource.binanceUsdt,
          value: value,
          fetchedAt: DateTime.now(),
        );
        await _saveToCache(rate);
        return rate;
      }
    } catch (_) {}

    return _cachedOrFallback(RateSource.binanceUsdt, fallbackBinanceUsdt);
  }

  /// Las 3 tasas de red en paralelo. Si una falla, trae su caché/respaldo.
  Future<Map<RateSource, Rate>> fetchAll() async {
    final results = await Future.wait([
      fetchBcvUsd(),
      fetchBinanceUsdt(),
      fetchEuroBcv(),
    ]);
    return {
      RateSource.bcvUsd: results[0],
      RateSource.binanceUsdt: results[1],
      RateSource.euroBcv: results[2],
    };
  }

  // ------------------------------------------------------------------
  // Tasa personalizada (manual, sin red).
  // ------------------------------------------------------------------
  Future<double?> getCustomRate() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_customRateKey);
  }

  Future<void> setCustomRate(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_customRateKey, value);
  }

  // ------------------------------------------------------------------
  // API key opcional de DolarVzla (solo en SharedPreferences, NUNCA
  // hardcodeada). Se pega en Ajustes; si está vacía, no se usa.
  // Nota: DolarVzla es un respaldo opcional futuro; las 3 tasas
  // principales funcionan sin key (DolarApi es gratis y sin key,
  // Binance P2P es público).
  // ------------------------------------------------------------------
  Future<String?> getDolarVzlaKey() async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString(_dolarVzlaKeyKey);
    return (key == null || key.isEmpty) ? null : key;
  }

  Future<void> setDolarVzlaKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    if (key.trim().isEmpty) {
      await prefs.remove(_dolarVzlaKeyKey);
    } else {
      await prefs.setString(_dolarVzlaKeyKey, key.trim());
    }
  }

  // ------------------------------------------------------------------
  // Caché.
  // ------------------------------------------------------------------
  Future<void> _saveToCache(Rate rate) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_cachePrefix${rate.source.name}',
      jsonEncode(rate.toJson()),
    );
  }

  Future<Rate> _cachedOrFallback(RateSource source, double fallback) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_cachePrefix${source.name}');
    if (raw != null) {
      try {
        return Rate.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {}
    }
    // Sin red ni caché: último recurso, marcado como guardado.
    return Rate(
      source: source,
      value: fallback,
      fetchedAt: DateTime.now(),
      isCached: true,
    );
  }
}
