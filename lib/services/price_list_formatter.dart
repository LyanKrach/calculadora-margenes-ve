import '../models/product_item.dart';
import '../models/rate.dart';
import '../models/seller_profile.dart';
import '../utils/format.dart';

/// Clave centinela para identificar productos sin categoría al compartir listas.
const String uncategorizedKey = '';

/// Extrae las categorías únicas no vacías de [products], ordenadas A–Z.
List<String> extractUniqueCategories(Iterable<ProductItem> products) {
  final byLower = <String, String>{};
  for (final p in products) {
    final trimmed = p.category.trim();
    if (trimmed.isEmpty) continue;
    final lower = trimmed.toLowerCase();
    byLower.putIfAbsent(lower, () => trimmed);
  }
  final result = byLower.values.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return result;
}

/// Indica si existe al menos un producto sin categoría asignada.
bool hasUncategorizedProducts(Iterable<ProductItem> products) =>
    products.any((p) => p.category.trim().isEmpty);

final RegExp _tokenRegex = RegExp(r'\d+|\D+');
final RegExp _startsWithWordOrDigit = RegExp(r'^[A-Za-z0-9ÁÉÍÓÚÜÑáéíóúüñ]');

/// Comparador natural: ordena tokens numéricos por valor (`100` antes que `1060`),
/// antepone cantidades numéricas a textos y compara texto sin distinguir mayúsculas.
int compareNaturalProductNames(String a, String b) {
  final tokensA = _tokenRegex.allMatches(a.trim()).map((m) => m.group(0)!).toList();
  final tokensB = _tokenRegex.allMatches(b.trim()).map((m) => m.group(0)!).toList();
  final minLen = tokensA.length < tokensB.length ? tokensA.length : tokensB.length;

  for (var i = 0; i < minLen; i++) {
    final ta = tokensA[i];
    final tb = tokensB[i];
    final na = int.tryParse(ta);
    final nb = int.tryParse(tb);

    if (na != null && nb != null) {
      final cmp = na.compareTo(nb);
      if (cmp != 0) return cmp;
      if (ta.length != tb.length) return ta.length.compareTo(tb.length);
      continue;
    }
    if (na != null && nb == null) return -1;
    if (na == null && nb != null) return 1;

    final textCmp = ta.trim().toLowerCase().compareTo(tb.trim().toLowerCase());
    if (textCmp != 0) return textCmp;
  }

  return tokensA.length.compareTo(tokensB.length);
}

String _prefixIconForProduct(String name, String category) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '• ';
  // Evita duplicar si el usuario ya incluyó un emoji o símbolo al inicio.
  if (!_startsWithWordOrDigit.hasMatch(trimmed)) return '';

  final lower = '$name $category'.toLowerCase();
  if (RegExp(r'diamant|diamond|robux|gema|\buc\b|\bcp\b|moneda|coin').hasMatch(lower)) {
    return '💎 ';
  }
  if (RegExp(r'\bpase\b|booyah|\bvip\b|elite|promo|oferta').hasMatch(lower)) {
    return '🔥 ';
  }
  if (RegExp(r'tarjeta|card|gift|\bpin\b|c[oó]digo|vale').hasMatch(lower)) {
    return '💳 ';
  }
  if (RegExp(r'paquete|combo|\bpack\b|\bkit\b|nivel').hasMatch(lower)) {
    return '📦 ';
  }
  return '• ';
}

/// Construye una lista de precios ordenada lista para copiar o enviar por WhatsApp.
///
/// [selectedCategories] contiene los nombres exactos (trimmed) de las categorías
/// elegidas. Si [includeUncategorized] es `true`, se incluyen además los productos
/// sin categoría. Devuelve cadena vacía si no hay productos con precio válido (> 0).
String buildWhatsAppPriceList({
  required List<ProductItem> products,
  required Set<String> selectedCategories,
  required bool includeUncategorized,
  required Map<RateSource, Rate> ratesMap,
  required double globalCustomRate,
  RateSource? overrideSource,
  SellerProfile? profile,
  String? customGreeting,
  bool includePaymentData = false,
}) {
  final selectedLower = selectedCategories.map((c) => c.trim().toLowerCase()).toSet();

  // Agrupamos por clave normalizada manteniendo la etiqueta legible de cada categoría.
  final grouped = <String, List<ProductItem>>{};
  final displayLabel = <String, String>{};

  for (final item in products) {
    final cat = item.category.trim();
    final catLower = cat.toLowerCase();
    final included = cat.isEmpty
        ? includeUncategorized
        : selectedLower.contains(catLower);
    if (!included) continue;

    final groupKey = cat.isEmpty ? uncategorizedKey : catLower;
    grouped.putIfAbsent(groupKey, () => <ProductItem>[]).add(item);
    if (cat.isNotEmpty) {
      displayLabel.putIfAbsent(groupKey, () => cat);
    }
  }

  // Filtramos solo productos con precio calculable válido.
  final nonEmptyKeys = <String>[];
  for (final entry in grouped.entries) {
    entry.value.sort((a, b) => compareNaturalProductNames(a.name, b.name));
    final withPrice = <ProductItem>[];
    for (final p in entry.value) {
      final r = _resolveRate(p, ratesMap, globalCustomRate, overrideSource);
      if (p.livePriceBs(r) != null) withPrice.add(p);
    }
    grouped[entry.key] = withPrice;
    if (withPrice.isNotEmpty) nonEmptyKeys.add(entry.key);
  }

  if (nonEmptyKeys.isEmpty) return '';

  // Ordenamos grupos alfabéticamente y dejamos sin categoría al final.
  nonEmptyKeys.sort((a, b) {
    if (a == uncategorizedKey) return 1;
    if (b == uncategorizedKey) return -1;
    return (displayLabel[a] ?? a)
        .toLowerCase()
        .compareTo((displayLabel[b] ?? b).toLowerCase());
  });

  final namedCount = nonEmptyKeys.where((k) => k != uncategorizedKey).length;
  final singleNamedOnly = nonEmptyKeys.length == 1 && namedCount == 1;
  final greetingTrimmed = (customGreeting ?? '').trim();

  final buffer = StringBuffer();
  if (greetingTrimmed.isNotEmpty) {
    buffer.writeln(greetingTrimmed);
  } else if (singleNamedOnly) {
    final label = displayLabel[nonEmptyKeys.first]!;
    buffer.writeln('¡Hola! 🔥 Aquí tienes los precios de *$label*:');
  } else {
    final business = profile?.businessName.trim() ?? '';
    if (business.isNotEmpty) {
      buffer.writeln('¡Hola! 🔥 Aquí tienes los precios de *$business*:');
    } else {
      buffer.writeln('¡Hola! 🔥 Aquí tienes nuestra lista de precios:');
    }
  }

  for (final key in nonEmptyKeys) {
    final items = grouped[key]!;
    buffer.writeln();
    if (!singleNamedOnly && nonEmptyKeys.length > 1) {
      final header = key == uncategorizedKey
          ? 'Otros productos'
          : displayLabel[key]!;
      buffer.writeln('*$header:*');
    }
    for (final p in items) {
      final r = _resolveRate(p, ratesMap, globalCustomRate, overrideSource);
      final price = p.livePriceBs(r);
      if (price == null) continue;
      final prefix = _prefixIconForProduct(p.name, p.category);
      buffer.writeln('$prefix${p.name.trim()} = ${fmtBs(price)} Bs');
    }
  }

  if (includePaymentData && profile != null && profile.hasPagoMovil) {
    buffer.writeln();
    buffer.writeln('📲 *Datos para Pago Móvil:*');
    if (profile.businessName.trim().isNotEmpty) {
      buffer.writeln('Comercio: ${profile.businessName.trim()}');
    }
    buffer.writeln('CI/RIF: ${profile.idDocument.trim()}');
    buffer.writeln('Tel: ${profile.phone.trim()}');
    buffer.writeln('Banco: ${profile.bank.trim()}');
    if (profile.paymentNotes.trim().isNotEmpty) {
      buffer.writeln(profile.paymentNotes.trim());
    }
  }

  return buffer.toString().trim();
}

double _resolveRate(
  ProductItem item,
  Map<RateSource, Rate> ratesMap,
  double globalCustomRate,
  RateSource? overrideSource,
) {
  if (overrideSource != null) {
    if (overrideSource == RateSource.custom) {
      return (item.customRateValue != null && item.customRateValue! > 0)
          ? item.customRateValue!
          : globalCustomRate;
    }
    return ratesMap[overrideSource]?.value ?? 0.0;
  }
  return item.effectiveRate(ratesMap, globalCustomRate);
}

