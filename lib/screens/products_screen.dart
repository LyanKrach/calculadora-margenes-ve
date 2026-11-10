import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/calculation_item.dart';
import '../models/margin_mode.dart';
import '../models/product_item.dart';
import '../models/rate.dart';
import '../services/auth_service.dart';
import '../services/history_service.dart';
import '../services/products_service.dart';
import '../services/rates_service.dart';
import '../services/seller_profile_service.dart';
import '../utils/format.dart';
import 'auth_screen.dart';

/// Pantalla de Catálogo de Productos (con precios en Bs calculados al instante)
/// e Historial de Productos Calculados, respaldados localmente y en Firestore.
class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final _productsService = ProductsService();
  final _historyService = HistoryService();
  final _ratesService = RatesService();
  final _profileService = SellerProfileService();
  final _authService = AuthService();

  final _searchCtrl = TextEditingController();

  List<ProductItem> _products = const [];
  List<HistoryEntry> _history = const [];
  Map<RateSource, Rate> _ratesMap = {};
  double _globalCustomRate = 0;
  RateSource? _overrideSource;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refreshAll();
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshAll() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _ratesService.fetchAll(),
        _ratesService.getCustomRate(),
        _productsService.getProducts(syncRemote: true),
        _historyService.getHistory(syncRemote: true),
      ]);
      if (!mounted) return;
      setState(() {
        _ratesMap = results[0] as Map<RateSource, Rate>;
        _globalCustomRate = (results[1] as double?) ?? 0;
        _products = results[2] as List<ProductItem>;
        _history = results[3] as List<HistoryEntry>;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  double _rateForProduct(ProductItem item) {
    final source = _overrideSource ?? item.rateSource;
    if (source == RateSource.custom) {
      return (item.customRateValue != null && item.customRateValue! > 0)
          ? item.customRateValue!
          : _globalCustomRate;
    }
    return _ratesMap[source]?.value ?? 0.0;
  }

  RateSource _effectiveSourceForProduct(ProductItem item) =>
      _overrideSource ?? item.rateSource;

  Future<void> _recordProductHistory(
    ProductItem item,
    double rateValue,
    double finalPriceBs,
  ) async {
    final now = DateTime.now();
    final source = _effectiveSourceForProduct(item);
    final entry = HistoryEntry(
      id: 'prod_${now.microsecondsSinceEpoch}',
      title: '${item.name} (\$${fmtUsd(item.costUsd)} @ ${source.label})',
      costUsd: item.costUsd,
      marginPercent: item.marginPercent,
      fixedExpenseBs: item.fixedExpenseBs,
      commissionPlatform: item.commissionPlatform,
      commissionPaymentMethod: item.commissionPaymentMethod,
      commissionOther: item.commissionOther,
      roundStep: item.roundStep,
      rateSource: source,
      marginMode: item.marginMode,
      rateValue: rateValue,
      finalPriceBs: finalPriceBs,
      timestamp: now,
    );
    await _historyService.addHistoryEntry(entry);
    final updatedHistory = await _historyService.getHistory(syncRemote: false);
    if (mounted) {
      setState(() => _history = updatedHistory);
    }
  }

  Future<void> _copyProductPrice(
    ProductItem item,
    double rateValue,
    double finalPriceBs,
  ) async {
    await _recordProductHistory(item, rateValue, finalPriceBs);
    await Clipboard.setData(
      ClipboardData(text: '${item.name}: ${fmtBs(finalPriceBs)} Bs'),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Precio de "${item.name}" copiado')),
    );
  }

  Future<void> _shareProductWhatsApp(
    ProductItem item,
    double rateValue,
    double finalPriceBs,
  ) async {
    await _recordProductHistory(item, rateValue, finalPriceBs);
    final profile = await _profileService.getProfile();
    final source = _effectiveSourceForProduct(item);
    final baseMsg = profile.buildClientMessage(
      finalPriceBs: finalPriceBs,
      rateLabel: source.label,
      rateValue: rateValue,
    );
    final fullMsg = '*Producto:* ${item.name}\n$baseMsg';
    final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(fullMsg)}');
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      await Clipboard.setData(ClipboardData(text: fullMsg));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mensaje de cobro copiado al portapapeles'),
        ),
      );
    }
  }

  Future<void> _openProductForm({ProductItem? existing}) async {
    final saved = await showModalBottomSheet<ProductItem>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ProductFormSheet(
        existing: existing,
        defaultCustomRate: _globalCustomRate,
      ),
    );
    if (saved != null) {
      await _productsService.saveProduct(saved);
      final list = await _productsService.getProducts(syncRemote: false);
      if (!mounted) return;
      setState(() => _products = list);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            existing == null
                ? 'Producto "${saved.name}" guardado'
                : 'Producto "${saved.name}" actualizado',
          ),
        ),
      );
    }
  }

  Future<void> _deleteProduct(ProductItem item) async {
    await _productsService.deleteProduct(item.id);
    final list = await _productsService.getProducts(syncRemote: false);
    if (!mounted) return;
    setState(() => _products = list);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Producto "${item.name}" eliminado')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSignedIn = _authService.isSignedIn;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Productos e Historial'),
          actions: [
            IconButton(
              icon: Icon(
                isSignedIn ? Icons.cloud_done : Icons.cloud_upload_outlined,
                color: isSignedIn ? Theme.of(context).colorScheme.primary : null,
              ),
              tooltip: isSignedIn
                  ? 'Sincronizado con Firebase'
                  : 'Iniciar sesión en la nube',
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AuthScreen()),
                );
                await _refreshAll();
              },
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Actualizar precios y sincronizar',
              onPressed: _refreshAll,
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(
                icon: Icon(Icons.inventory_2_outlined),
                text: 'Catálogo de Productos',
              ),
              Tab(
                icon: Icon(Icons.history),
                text: 'Historial Calculado',
              ),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _buildProductsCatalogTab(),
                  _buildHistoryTab(),
                ],
              ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _openProductForm(),
          icon: const Icon(Icons.add),
          label: const Text('Agregar producto'),
        ),
      ),
    );
  }

  Widget _buildProductsCatalogTab() {
    final query = _searchCtrl.text.trim().toLowerCase();
    final filtered = _products.where((p) {
      if (query.isEmpty) return true;
      return p.name.toLowerCase().contains(query) ||
          p.category.toLowerCase().contains(query);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Buscar producto o categoría...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: _searchCtrl.clear,
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ChoiceChip(
                      label: const Text('Tasa de cada producto', style: TextStyle(fontSize: 12)),
                      selected: _overrideSource == null,
                      onSelected: (_) => setState(() => _overrideSource = null),
                    ),
                    const SizedBox(width: 6),
                    for (final s in [
                      RateSource.bcvUsd,
                      RateSource.binanceUsdt,
                      RateSource.euroBcv,
                    ]) ...[
                      ChoiceChip(
                        label: Text(
                          '${s.label} (${_ratesMap[s] != null ? fmtRate(_ratesMap[s]!.value) : "—"})',
                          style: const TextStyle(fontSize: 12),
                        ),
                        selected: _overrideSource == s,
                        onSelected: (sel) => setState(
                          () => _overrideSource = sel ? s : null,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _products.isEmpty
                          ? 'Aún no tienes productos guardados.\n'
                              'Toca "Agregar producto" abajo para guardar tus productos '
                              'y ver su precio en bolívares al instante todos los días.'
                          : 'No se encontraron productos que coincidan con "$query".',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _refreshAll,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      final rate = _rateForProduct(item);
                      final source = _effectiveSourceForProduct(item);
                      final priceBs = item.livePriceBs(rate);
                      final bd = item.liveBreakdown(rate);
                      final totalCommPct = (item.commissionPlatform +
                              item.commissionPaymentMethod +
                              item.commissionOther) *
                          100;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.name,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        if (item.category.isNotEmpty)
                                          Text(
                                            item.category,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Theme.of(context).colorScheme.primary,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        priceBs != null
                                            ? '${fmtBs(priceBs)} Bs'
                                            : 'Sin tasa',
                                        style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(context).colorScheme.primary,
                                        ),
                                      ),
                                      Text(
                                        '${source.label} (${rate > 0 ? fmtRate(rate) : "—"})',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Costo: \$${fmtUsd(item.costUsd)} · Margen: ${item.marginPercent.toStringAsFixed(1)}% (${item.marginMode.shortLabel}) · '
                                'Comisiones: ${totalCommPct.toStringAsFixed(1)}%'
                                '${bd != null && rate > 0 ? ' · Ganancia: ${fmtBs(bd.netProfitBs)} Bs (≈ \$${fmtUsd(bd.netProfitBs / rate)})' : ''}',
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  if (priceBs != null) ...[
                                    FilledButton.tonalIcon(
                                      onPressed: () => _copyProductPrice(
                                        item,
                                        rate,
                                        priceBs,
                                      ),
                                      icon: const Icon(Icons.copy, size: 16),
                                      label: const Text('Copiar Bs'),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: () => _shareProductWhatsApp(
                                        item,
                                        rate,
                                        priceBs,
                                      ),
                                      icon: const Icon(Icons.send_outlined, size: 16),
                                      label: const Text('WhatsApp'),
                                    ),
                                  ],
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined, size: 20),
                                    tooltip: 'Editar producto',
                                    onPressed: () => _openProductForm(existing: item),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 20),
                                    tooltip: 'Eliminar producto',
                                    onPressed: () => _deleteProduct(item),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildHistoryTab() {
    final fmt = DateFormat('dd/MM/yyyy HH:mm', 'es_VE');

    if (_history.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Aún no hay productos calculados en el historial.\n'
            'Cada vez que copies un precio o compartas por WhatsApp desde la Calculadora o desde tu Catálogo, quedará registrado aquí.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Últimos ${_history.length} productos calculados',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              TextButton.icon(
                onPressed: () async {
                  await _historyService.clearHistory();
                  final updated = await _historyService.getHistory(syncRemote: false);
                  if (mounted) setState(() => _history = updated);
                },
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                label: const Text('Limpiar historial'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
            itemCount: _history.length,
            itemBuilder: (context, index) {
              final entry = _history[index];
              final totalCommPct = (entry.commissionPlatform +
                      entry.commissionPaymentMethod +
                      entry.commissionOther) *
                  100;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(
                    entry.title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'Costo \$${fmtUsd(entry.costUsd)} · Margen ${entry.marginPercent.toStringAsFixed(1)}% · '
                    'Com. ${totalCommPct.toStringAsFixed(1)}%\n'
                    '${entry.rateSource.label}: ${fmtRate(entry.rateValue)} · ${fmt.format(entry.timestamp)}',
                  ),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${fmtBs(entry.finalPriceBs)} Bs',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 18),
                        tooltip: 'Copiar precio',
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: '${fmtBs(entry.finalPriceBs)} Bs'),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Precio histórico copiado')),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: 'Eliminar del historial',
                        onPressed: () async {
                          await _historyService.deleteHistoryEntry(entry.id);
                          final updated =
                              await _historyService.getHistory(syncRemote: false);
                          if (mounted) setState(() => _history = updated);
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ProductFormSheet extends StatefulWidget {
  const _ProductFormSheet({
    this.existing,
    required this.defaultCustomRate,
  });

  final ProductItem? existing;
  final double defaultCustomRate;

  @override
  State<_ProductFormSheet> createState() => _ProductFormSheetState();
}

class _ProductFormSheetState extends State<_ProductFormSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _categoryCtrl;
  late final TextEditingController _costCtrl;
  late final TextEditingController _marginCtrl;
  late final TextEditingController _fixedCtrl;
  late final TextEditingController _provCtrl;
  late final TextEditingController _gatewayCtrl;
  late final TextEditingController _otherCtrl;
  late final TextEditingController _customRateCtrl;

  late RateSource _rateSource;
  late MarginMode _marginMode;
  late int _roundStep;
  String? _error;

  static String _fmt(double v) {
    if (v == 0) return '0';
    final r = double.parse(v.toStringAsFixed(4));
    return r % 1 == 0 ? r.toInt().toString() : r.toString();
  }

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _categoryCtrl = TextEditingController(text: e?.category ?? '');
    _costCtrl = TextEditingController(text: e != null ? _fmt(e.costUsd) : '10');
    _marginCtrl =
        TextEditingController(text: e != null ? _fmt(e.marginPercent) : '20');
    _fixedCtrl =
        TextEditingController(text: e != null ? _fmt(e.fixedExpenseBs) : '0');
    _provCtrl = TextEditingController(
      text: e != null ? _fmt(e.commissionPlatform * 100) : '2',
    );
    _gatewayCtrl = TextEditingController(
      text: e != null ? _fmt(e.commissionPaymentMethod * 100) : '0',
    );
    _otherCtrl = TextEditingController(
      text: e != null ? _fmt(e.commissionOther * 100) : '0',
    );
    _customRateCtrl = TextEditingController(
      text: e?.customRateValue != null
          ? _fmt(e!.customRateValue!)
          : (widget.defaultCustomRate > 0 ? _fmt(widget.defaultCustomRate) : ''),
    );
    _rateSource = e?.rateSource ?? RateSource.bcvUsd;
    _marginMode = e?.marginMode ?? MarginMode.onCost;
    _roundStep = e?.roundStep ?? 10;
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl,
      _categoryCtrl,
      _costCtrl,
      _marginCtrl,
      _fixedCtrl,
      _provCtrl,
      _gatewayCtrl,
      _otherCtrl,
      _customRateCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    final cost = double.tryParse(_costCtrl.text.replaceAll(',', '.')) ?? 0;
    final marginPct =
        double.tryParse(_marginCtrl.text.replaceAll(',', '.')) ?? 0;
    final fixedBs = double.tryParse(_fixedCtrl.text.replaceAll(',', '.')) ?? 0;
    final prov =
        (double.tryParse(_provCtrl.text.replaceAll(',', '.')) ?? 0) / 100;
    final gateway =
        (double.tryParse(_gatewayCtrl.text.replaceAll(',', '.')) ?? 0) / 100;
    final other =
        (double.tryParse(_otherCtrl.text.replaceAll(',', '.')) ?? 0) / 100;
    final customRate =
        double.tryParse(_customRateCtrl.text.replaceAll(',', '.'));

    if (name.isEmpty) {
      setState(() => _error = 'Escribe el nombre del producto.');
      return;
    }
    if (cost <= 0) {
      setState(() => _error = 'El costo en USD debe ser mayor que 0.');
      return;
    }
    if (_marginMode == MarginMode.onCost) {
      if (prov + gateway + other >= 1.0) {
        setState(() => _error = 'Las comisiones deben sumar menos del 100 %.');
        return;
      }
    } else {
      if ((prov + gateway + other + (marginPct / 100)) >= 1.0) {
        setState(
          () => _error = 'La suma de comisiones y margen debe ser menor al 100 %.',
        );
        return;
      }
    }

    final now = DateTime.now();
    final product = ProductItem(
      id: widget.existing?.id ?? 'prod_${now.microsecondsSinceEpoch}',
      name: name,
      category: _categoryCtrl.text.trim(),
      costUsd: cost,
      marginPercent: marginPct,
      fixedExpenseBs: fixedBs,
      commissionPlatform: prov,
      commissionPaymentMethod: gateway,
      commissionOther: other,
      roundStep: _roundStep,
      rateSource: _rateSource,
      marginMode: _marginMode,
      customRateValue: _rateSource == RateSource.custom ? customRate : null,
      createdAt: widget.existing?.createdAt ?? now,
      updatedAt: now,
    );

    Navigator.of(context).pop(product);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomInset + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.existing == null ? 'Nuevo Producto' : 'Editar Producto',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameCtrl,
              autofocus: widget.existing == null,
              decoration: const InputDecoration(
                labelText: 'Nombre del producto',
                hintText: 'Ej. Recarga 100 Diamantes / Harina 1kg',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _categoryCtrl,
              decoration: const InputDecoration(
                labelText: 'Categoría (opcional)',
                hintText: 'Ej. Gaming, Víveres, Servicios',
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Text('Modo de cálculo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.help_outline, size: 18),
                  tooltip: '¿Cómo se calcula?',
                  onPressed: () {
                    showDialog<void>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Modo de cálculo'),
                        content: const Text(
                          '• Sobre costo: suma el % de margen directamente a tu costo (Markup).\n\n'
                          '• Sobre venta: el % de margen representa qué fracción del precio final cobrado al cliente te queda como ganancia neta.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: const Text('Entendido'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            SegmentedButton<MarginMode>(
              segments: const [
                ButtonSegment(
                  value: MarginMode.onCost,
                  icon: Icon(Icons.trending_up, size: 16),
                  label: Text('Sobre costo'),
                ),
                ButtonSegment(
                  value: MarginMode.onSale,
                  icon: Icon(Icons.pie_chart_outline, size: 16),
                  label: Text('Sobre venta'),
                ),
              ],
              selected: {_marginMode},
              onSelectionChanged: (s) => setState(() => _marginMode = s.first),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _costCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Costo (USD)'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _marginCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: _marginMode == MarginMode.onCost
                          ? 'Margen s/costo (%)'
                          : 'Margen s/venta (%)',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _fixedCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration:
                        const InputDecoration(labelText: 'Gasto fijo (Bs)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _provCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration:
                        const InputDecoration(labelText: 'Plataforma (%)'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _gatewayCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration:
                        const InputDecoration(labelText: 'Pago Móvil (%)'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _otherCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Otra (%)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<RateSource>(
              initialValue: _rateSource,
              decoration: const InputDecoration(
                labelText: 'Tasa de referencia del producto',
              ),
              items: RateSource.values
                  .map((s) => DropdownMenuItem(value: s, child: Text(s.label)))
                  .toList(),
              onChanged: (val) {
                if (val != null) setState(() => _rateSource = val);
              },
            ),
            if (_rateSource == RateSource.custom) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _customRateCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Tasa personalizada (Bs/\$)',
                ),
              ),
            ],
            const SizedBox(height: 10),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Exacto')),
                ButtonSegment(value: 10, label: Text('Bs 10')),
                ButtonSegment(value: 50, label: Text('Bs 50')),
                ButtonSegment(value: 100, label: Text('Bs 100')),
              ],
              selected: {_roundStep},
              onSelectionChanged: (s) => setState(() => _roundStep = s.first),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Guardar producto'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

