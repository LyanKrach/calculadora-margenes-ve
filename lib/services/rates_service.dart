import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/rate.dart';
import '../models/rate_snapshot.dart';
import 'bcv_http_client_stub.dart'
    if (dart.library.io) 'bcv_http_client_io.dart';
import 'calculator.dart';

/// Servicio de tasas: BCV dólar, Binance USDT P2P, Euro BCV y personalizada.
///
/// EN APP NATIVA NO HAY BLOQUEO CORS: ese bloqueo solo afecta a la web.
/// Por eso la app puede consultar `www.bcv.org.ve` directamente (usando el
/// certificado intermedio de Sectigo DV R36 sin desactivar SSL) además de la
/// fuente rápida compartida `rates.dolarvzla.com/bcv/current.json`.
///
/// Cadena de respaldo (fallback) por tasa BCV (Dólar y Euro):
/// 1. Directo BCV (`www.bcv.org.ve`, solo nativo) y DolarVZLA CDN JSON
///    (`rates.dolarvzla.com/bcv/current.json`, multiplataforma, sin clave, CORS *).
///    Si ambos responden, se toma el de fecha de vigencia más reciente.
/// 2. BCV Today (`bcv.today/api/v1/rate.json`, respaldo rápido sin clave).
/// 3. DolarApi oficial (`ve.dolarapi.com/v1/dolares/oficial` y `euros/oficial`).
/// 4. Caché offline / Valores fallback.
///
/// Cadena Binance USDT y Personalizada: intacta (sin cambios).
class RatesService {
  RatesService({http.Client? client})
      : _hasCustomClient = client != null,
        _client = client ?? http.Client();

  final bool _hasCustomClient;
  final http.Client _client;

  static const _timeout = Duration(seconds: 10);
  static const _bcvDirectTimeout = Duration(seconds: 4);

  // Fuentes BCV (USD y EUR):
  static const _dolarVzlaCurrent =
      'https://rates.dolarvzla.com/bcv/current.json';
  static const _bcvDirectUrl = 'https://www.bcv.org.ve/';
  static const _bcvTodayRate = 'https://bcv.today/api/v1/rate.json';

  // Respaldo DolarApi y paralelo/Binance:
  static const _dolarApiUsd = 'https://ve.dolarapi.com/v1/dolares/oficial';
  static const _dolarApiEur = 'https://ve.dolarapi.com/v1/euros/oficial';
  static const _dolarApiParallel =
      'https://ve.dolarapi.com/v1/dolares/paralelo';
  static const _binanceP2p =
      'https://p2p.binance.com/bapi/c2c/v2/friendly/c2c/adv/search';
  static const _binanceQuote =
      'https://www.binance.com/bapi/c2c/v1/public/c2c/agent/quote-price'
      '?fiat=VES&asset=USDT&tradeType=BUY';

  static const _cachePrefix = 'rate_cache_';
  static const _customRateKey = 'custom_rate_value';
  static const _snapshotsKey = 'rate_snapshots_history';
  static const int maxSnapshots = 10;

  // Valores de último recurso cuando no hay red ni caché previa.
  static const double fallbackBcvUsd = 899.27;
  static const double fallbackEuroBcv = 1006.61;
  static const double fallbackBinanceUsdt = 1082.50;

  _BcvPairData? _lastBcvPairData;
  DateTime? _lastBcvPairFetchTime;
  Future<_BcvPairData?>? _inFlightBcvFuture;

  Future<_BcvPairData?> _resolvePrimaryBcvPair() async {
    if (_lastBcvPairData != null &&
        _lastBcvPairFetchTime != null &&
        DateTime.now().difference(_lastBcvPairFetchTime!) <
            const Duration(seconds: 15)) {
      return _lastBcvPairData;
    }
    if (_inFlightBcvFuture != null) {
      return _inFlightBcvFuture;
    }

    final future = _fetchPrimaryBcvInternal();
    _inFlightBcvFuture = future;
    try {
      final result = await future;
      if (result != null) {
        _lastBcvPairData = result;
        _lastBcvPairFetchTime = DateTime.now();
      }
      return result;
    } finally {
      _inFlightBcvFuture = null;
    }
  }

  Future<_BcvPairData?> _fetchPrimaryBcvInternal() async {
    final vzlaFuture = _fetchDolarVzla();
    final directFuture = !kIsWeb ? _fetchDirectBcv() : Future<_BcvPairData?>.value(null);

    _BcvPairData? vzla;
    _BcvPairData? direct;

    if (kIsWeb) {
      vzla = await vzlaFuture;
    } else {
      // Consultar en paralelo sin bloquear más de 1.2s si DolarVZLA ya respondió
      // (p. ej. si www.bcv.org.ve está bloqueado fuera de Venezuela).
      vzla = await vzlaFuture;
      if (vzla != null) {
        try {
          direct = await directFuture.timeout(
            const Duration(milliseconds: 1200),
            onTimeout: () => null,
          );
        } catch (_) {
          direct = null;
        }
      } else {
        direct = await directFuture;
      }
    }

    final chosen = _pickFresherBcv(direct: direct, cdn: vzla);
    if (chosen != null) return chosen;

    // Respaldo rápido secundario antes de DolarApi: BCV Today
    return await _fetchBcvToday();
  }

  _BcvPairData? _pickFresherBcv({_BcvPairData? direct, _BcvPairData? cdn}) {
    if (direct == null) return cdn;
    if (cdn == null) return direct;
    final dDate = direct.effectiveDate ?? '';
    final cDate = cdn.effectiveDate ?? '';
    if (cDate.compareTo(dDate) > 0) {
      return cdn;
    }
    return direct;
  }

  Future<_BcvPairData?> _fetchDolarVzla() async {
    try {
      final res =
          await _client.get(Uri.parse(_dolarVzlaCurrent)).timeout(_timeout);
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final current = json['current'] as Map<String, dynamic>?;
        if (current != null) {
          final usd = (current['usd'] as num?)?.toDouble();
          final eur = (current['eur'] as num?)?.toDouble();
          final dateStr = current['date']?.toString();
          if ((usd != null && usd > 0) || (eur != null && eur > 0)) {
            return _BcvPairData(usd: usd, eur: eur, effectiveDate: dateStr);
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<_BcvPairData?> _fetchBcvToday() async {
    try {
      final res =
          await _client.get(Uri.parse(_bcvTodayRate)).timeout(_timeout);
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final usd = (json['USD'] as num?)?.toDouble();
        final eur = (json['EUR'] as num?)?.toDouble();
        final effDate =
            (json['effective_date'] ?? json['date'])?.toString();
        if ((usd != null && usd > 0) || (eur != null && eur > 0)) {
          return _BcvPairData(usd: usd, eur: eur, effectiveDate: effDate);
        }
      }
    } catch (_) {}
    return null;
  }

  Future<_BcvPairData?> _fetchDirectBcv() async {
    if (kIsWeb) return null;
    final http.Client bcvClient =
        _hasCustomClient ? _client : createBcvDirectHttpClient();
    try {
      final res = await bcvClient
          .get(
            Uri.parse(_bcvDirectUrl),
            headers: const {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
              'Accept':
                  'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            },
          )
          .timeout(_bcvDirectTimeout);
      if (res.statusCode == 200) {
        final html = res.body;

        final usdMatch = RegExp(
          r'id=["\x27]dolar["\x27][\s\S]*?<strong[^>]*>\s*([\d.,]+)\s*<\/strong>',
          caseSensitive: false,
        ).firstMatch(html);
        double? usd;
        if (usdMatch != null) {
          final clean =
              usdMatch.group(1)!.replaceAll('.', '').replaceAll(',', '.');
          usd = double.tryParse(clean);
        }

        final eurMatch = RegExp(
          r'id=["\x27]euro["\x27][\s\S]*?<strong[^>]*>\s*([\d.,]+)\s*<\/strong>',
          caseSensitive: false,
        ).firstMatch(html);
        double? eur;
        if (eurMatch != null) {
          final clean =
              eurMatch.group(1)!.replaceAll('.', '').replaceAll(',', '.');
          eur = double.tryParse(clean);
        }

        final dateMatch = RegExp(
          r'content=["\x27](\d{4}-\d{2}-\d{2})T',
          caseSensitive: false,
        ).firstMatch(html);
        final effDate = dateMatch?.group(1);

        if ((usd != null && usd > 0) || (eur != null && eur > 0)) {
          return _BcvPairData(usd: usd, eur: eur, effectiveDate: effDate);
        }
      }
    } catch (_) {
    } finally {
      if (!_hasCustomClient) {
        bcvClient.close();
      }
    }
    return null;
  }

  // ------------------------------------------------------------------
  // BCV dólar:
  // 1. Directo BCV (nativo) + DolarVZLA CDN JSON (principal rápido sin clave)
  // 2. BCV Today (respaldo rápido)
  // 3. DolarApi oficial (respaldo)
  // 4. Caché offline / Fallback
  // ------------------------------------------------------------------
  Future<Rate> fetchBcvUsd() async {
    try {
      final pair = await _resolvePrimaryBcvPair();
      if (pair != null && pair.usd != null && pair.usd! > 0) {
        final value = double.parse(pair.usd!.toStringAsFixed(2));
        final rate = Rate(
          source: RateSource.bcvUsd,
          value: value,
          fetchedAt: DateTime.now(),
          effectiveDate: pair.effectiveDate,
        );
        await _saveToCache(rate);
        return rate;
      }
    } catch (_) {}

    // Respaldo DolarApi oficial
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
  // Euro BCV (misma fuente rápida + respaldo DolarApi):
  // ------------------------------------------------------------------
  Future<Rate> fetchEuroBcv() async {
    try {
      final pair = await _resolvePrimaryBcvPair();
      if (pair != null && pair.eur != null && pair.eur! > 0) {
        final value = double.parse(pair.eur!.toStringAsFixed(2));
        final rate = Rate(
          source: RateSource.euroBcv,
          value: value,
          fetchedAt: DateTime.now(),
          effectiveDate: pair.effectiveDate,
        );
        await _saveToCache(rate);
        return rate;
      }
    } catch (_) {}

    // Respaldo DolarApi euros oficial
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

class _BcvPairData {
  const _BcvPairData({this.usd, this.eur, this.effectiveDate});
  final double? usd;
  final double? eur;
  final String? effectiveDate;
}
