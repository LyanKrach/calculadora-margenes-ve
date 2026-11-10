import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/rate.dart';
import '../models/rate_snapshot.dart';
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

  // Endpoints verificados:
  // 1. BCV Today: JSON público sin clave, actualiza con la fecha de vigencia oficial del BCV.
  static const _bcvTodayRate = 'https://bcv.today/api/v1/rate.json';
  // 2. Directo BCV: HTML oficial del BCV (nativo sin CORS).
  static const _bcvDirectUrl = 'https://www.bcv.org.ve/';
  // 3. DolarApi (respaldo):
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
  static const _snapshotsKey = 'rate_snapshots_history';
  static const int maxSnapshots = 10;

  // Valores reales observados el 2026-11-09 (último recurso si no hay
  // red ni caché: la app nunca arranca sin una tasa que mostrar).
  static const double fallbackBcvUsd = 899.27;
  static const double fallbackEuroBcv = 1006.61;
  static const double fallbackBinanceUsdt = 1082.50;

  Map<String, dynamic>? _lastBcvTodayData;
  DateTime? _lastBcvTodayFetchTime;

  Future<Map<String, dynamic>?> _fetchBcvToday() async {
    if (_lastBcvTodayData != null &&
        _lastBcvTodayFetchTime != null &&
        DateTime.now().difference(_lastBcvTodayFetchTime!) <
            const Duration(seconds: 15)) {
      return _lastBcvTodayData;
    }
    try {
      final res =
          await _client.get(Uri.parse(_bcvTodayRate)).timeout(_timeout);
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        _lastBcvTodayData = json;
        _lastBcvTodayFetchTime = DateTime.now();
        return json;
      }
    } catch (_) {}
    return null;
  }

  Future<_BcvDirectData?> _fetchDirectBcv() async {
    try {
      final res = await _client
          .get(
            Uri.parse(_bcvDirectUrl),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
              'Accept':
                  'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            },
          )
          .timeout(_timeout);
      if (res.statusCode == 200) {
        final html = res.body;

        final usdMatch = RegExp(
          r'id=["\x27]dolar["\x27][\s\S]*?<strong[^>]*>\s*([\d.,]+)\s*<\/strong>',
          caseSensitive: false,
        ).firstMatch(html);
        double? usd;
        if (usdMatch != null) {
          final clean = usdMatch.group(1)!.replaceAll('.', '').replaceAll(',', '.');
          usd = double.tryParse(clean);
        }

        final eurMatch = RegExp(
          r'id=["\x27]euro["\x27][\s\S]*?<strong[^>]*>\s*([\d.,]+)\s*<\/strong>',
          caseSensitive: false,
        ).firstMatch(html);
        double? eur;
        if (eurMatch != null) {
          final clean = eurMatch.group(1)!.replaceAll('.', '').replaceAll(',', '.');
          eur = double.tryParse(clean);
        }

        final dateMatch = RegExp(
          r'content=["\x27](\d{4}-\d{2}-\d{2})T',
          caseSensitive: false,
        ).firstMatch(html);
        final effDate = dateMatch?.group(1);

        if (usd != null || eur != null) {
          return _BcvDirectData(usd: usd, eur: eur, effectiveDate: effDate);
        }
      }
    } catch (_) {}
    return null;
  }

  // ------------------------------------------------------------------
  // BCV dólar:
  // 1. BCV Today (rápido, vigencia oficial, sin clave)
  // 2. Directo BCV (página web oficial en nativo sin CORS)
  // 3. DolarApi oficial (respaldo)
  // 4. Caché offline / Fallback
  // ------------------------------------------------------------------
  Future<Rate> fetchBcvUsd() async {
    // 1. BCV Today
    try {
      final bcvToday = await _fetchBcvToday();
      if (bcvToday != null && bcvToday['USD'] is num) {
        final raw = (bcvToday['USD'] as num).toDouble();
        final value = double.parse(raw.toStringAsFixed(2));
        final effDate = bcvToday['effective_date']?.toString();
        final rate = Rate(
          source: RateSource.bcvUsd,
          value: value,
          fetchedAt: DateTime.now(),
          effectiveDate: effDate,
        );
        await _saveToCache(rate);
        return rate;
      }
    } catch (_) {}

    // 2. Directo BCV
    try {
      final direct = await _fetchDirectBcv();
      if (direct != null && direct.usd != null && direct.usd! > 0) {
        final value = double.parse(direct.usd!.toStringAsFixed(2));
        final rate = Rate(
          source: RateSource.bcvUsd,
          value: value,
          fetchedAt: DateTime.now(),
          effectiveDate: direct.effectiveDate,
        );
        await _saveToCache(rate);
        return rate;
      }
    } catch (_) {}

    // 3. DolarApi (respaldo)
    try {
      final res =
          await _client.get(Uri.parse(_dolarApiUsd)).timeout(_timeout);
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final raw = (json['promedio'] as num).toDouble();
        final value = double.parse(raw.toStringAsFixed(2));
        final fechaStr = json['fechaActualizacion']?.toString();
        String? effDate;
        if (fechaStr != null && fechaStr.length >= 10) {
          effDate = fechaStr.substring(0, 10);
        }
        final rate = Rate(
          source: RateSource.bcvUsd,
          value: value,
          fetchedAt: DateTime.now(),
          effectiveDate: effDate,
        );
        await _saveToCache(rate);
        return rate;
      }
    } catch (_) {}

    return _cachedOrFallback(RateSource.bcvUsd, fallbackBcvUsd, '2026-11-10');
  }

  // ------------------------------------------------------------------
  // Euro BCV:
  // 1. BCV Today (rápido, vigencia oficial, sin clave)
  // 2. Directo BCV (página web oficial en nativo sin CORS)
  // 3. DolarApi euros oficial (respaldo)
  // 4. Caché offline / Fallback
  // ------------------------------------------------------------------
  Future<Rate> fetchEuroBcv() async {
    // 1. BCV Today
    try {
      final bcvToday = await _fetchBcvToday();
      if (bcvToday != null && bcvToday['EUR'] is num) {
        final raw = (bcvToday['EUR'] as num).toDouble();
        final value = double.parse(raw.toStringAsFixed(2));
        final effDate = bcvToday['effective_date']?.toString();
        final rate = Rate(
          source: RateSource.euroBcv,
          value: value,
          fetchedAt: DateTime.now(),
          effectiveDate: effDate,
        );
        await _saveToCache(rate);
        return rate;
      }
    } catch (_) {}

    // 2. Directo BCV
    try {
      final direct = await _fetchDirectBcv();
      if (direct != null && direct.eur != null && direct.eur! > 0) {
        final value = double.parse(direct.eur!.toStringAsFixed(2));
        final rate = Rate(
          source: RateSource.euroBcv,
          value: value,
          fetchedAt: DateTime.now(),
          effectiveDate: direct.effectiveDate,
        );
        await _saveToCache(rate);
        return rate;
      }
    } catch (_) {}

    // 3. DolarApi euros oficial (respaldo)
    try {
      final res =
          await _client.get(Uri.parse(_dolarApiEur)).timeout(_timeout);
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final raw = (json['promedio'] as num).toDouble();
        final value = double.parse(raw.toStringAsFixed(2));
        final fechaStr = json['fechaActualizacion']?.toString();
        String? effDate;
        if (fechaStr != null && fechaStr.length >= 10) {
          effDate = fechaStr.substring(0, 10);
        }
        final rate = Rate(
          source: RateSource.euroBcv,
          value: value,
          fetchedAt: DateTime.now(),
          effectiveDate: effDate,
        );
        await _saveToCache(rate);
        return rate;
      }
    } catch (_) {}

    return _cachedOrFallback(RateSource.euroBcv, fallbackEuroBcv, '2026-11-10');
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
          final raw = median(prices);
          final rate = Rate(
            source: RateSource.binanceUsdt,
            value: double.parse(raw.toStringAsFixed(2)),
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
        final raw = (json['promedio'] as num).toDouble();
        final value = double.parse(raw.toStringAsFixed(2));
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
  ///
  /// Registra un snapshot histórico solo si hay datos frescos de red y se
  /// cumple la condición de variación (> 0.5 %) o tiempo (≥ 1 hora).
  Future<Map<RateSource, Rate>> fetchAll() async {
    final results = await Future.wait([
      fetchBcvUsd(),
      fetchBinanceUsdt(),
      fetchEuroBcv(),
    ]);
    final map = {
      RateSource.bcvUsd: results[0],
      RateSource.binanceUsdt: results[1],
      RateSource.euroBcv: results[2],
    };

    final hasFreshNetworkData = results.any((r) => !r.isCached);
    if (hasFreshNetworkData) {
      await recordSnapshotIfNeeded(
        RateSnapshot(
          timestamp: DateTime.now(),
          bcvUsd: results[0].value,
          binanceUsdt: results[1].value,
          euroBcv: results[2].value,
        ),
      );
    }

    return map;
  }

  // ------------------------------------------------------------------
  // Historial de snapshots de tasas (máximo 10 entradas).
  // Append solo si: (a) variación > 0.5 % vs último snapshot, o (b) ≥ 1 hora.
  // ------------------------------------------------------------------
  Future<List<RateSnapshot>> getSnapshots() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_snapshotsKey);
    return RateSnapshot.listFromJson(raw);
  }

  Future<bool> recordSnapshotIfNeeded(RateSnapshot candidate) async {
    if (!candidate.isValid) return false;
    final prefs = await SharedPreferences.getInstance();
    final current = List<RateSnapshot>.from(
      RateSnapshot.listFromJson(prefs.getString(_snapshotsKey)),
    );
    final last = current.isEmpty ? null : current.last;

    if (!RateSnapshot.shouldAppend(last: last, candidate: candidate)) {
      return false;
    }

    current.add(candidate);
    while (current.length > maxSnapshots) {
      current.removeAt(0);
    }

    final encoded = jsonEncode(current.map((s) => s.toJson()).toList());
    await prefs.setString(_snapshotsKey, encoded);
    return true;
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
  // Caché.
  // ------------------------------------------------------------------
  Future<void> _saveToCache(Rate rate) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_cachePrefix${rate.source.name}',
      jsonEncode(rate.toJson()),
    );
  }

  Future<Rate> _cachedOrFallback(RateSource source, double fallback,
      [String? fallbackDate]) async {
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
      effectiveDate: fallbackDate,
    );
  }
}

class _BcvDirectData {
  const _BcvDirectData({this.usd, this.eur, this.effectiveDate});
  final double? usd;
  final double? eur;
  final String? effectiveDate;
}
