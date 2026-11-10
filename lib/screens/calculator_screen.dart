import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/calculation_item.dart';
import '../models/margin_mode.dart';
import '../models/product_item.dart';
import '../models/rate.dart';
import '../services/calculator.dart';
import '../services/history_service.dart';
import '../services/products_service.dart';
import '../services/rates_service.dart';
import '../services/seller_profile_service.dart';
import '../utils/format.dart';
import '../widgets/history_presets_sheet.dart';

/// Pantalla principal: costo, tasa (4 tarjetas), margen, comisiones,
/// gasto fijo → precio de venta con desglose paso a paso, calculadora
/// inversa y tabla comparativa 10 %-40 %.
class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  final _rates = RatesService();
  final _historyService = HistoryService();
  final _productsService = ProductsService();
  final _profileService = SellerProfileService();

  final _costCtrl = TextEditingController(text: '10');
  final _marginCtrl = TextEditingController(text: '20');
  // Mapeo de comisiones:
  // _provCtrl    -> Comisión de plataforma / proveedor (ej. Binance P2P 1.5 %, Operativa 2.0 %)
  // _gatewayCtrl -> Comisión por método de pago / pasarela (ej. Pago Móvil 0.3 %, Pasarela 3.0 %)
  // _otherCtrl   -> Otra comisión o imprevistos
  final _provCtrl = TextEditingController(text: '2');
  final _gatewayCtrl = TextEditingController(text: '0');
  final _otherCtrl = TextEditingController(text: '0');
  final _fixedCtrl = TextEditingController(text: '0');
  final _customRateCtrl = TextEditingController();
  final _inversePriceCtrl = TextEditingController();

  RateSource _selectedSource = RateSource.bcvUsd;
  MarginMode _marginMode = MarginMode.onCost;
  Map<RateSource, Rate> _ratesMap = {};
  bool _loadingRates = true;
  String? _ratesError;
  int _roundStep = 10;

  double get _costUsd => double.tryParse(_costCtrl.text.replaceAll(',', '.')) ?? 0;
  double get _margin => (double.tryParse(_marginCtrl.text.replaceAll(',', '.')) ?? 0) / 100;
  double get _prov => (double.tryParse(_provCtrl.text.replaceAll(',', '.')) ?? 0) / 100;
  double get _gateway => (double.tryParse(_gatewayCtrl.text.replaceAll(',', '.')) ?? 0) / 100;
  double get _other => (double.tryParse(_otherCtrl.text.replaceAll(',', '.')) ?? 0) / 100;
  double get _fixed => double.tryParse(_fixedCtrl.text.replaceAll(',', '.')) ?? 0;
  double get _totalCommission => _prov + _gateway + _other;

  double get _rate {
    if (_selectedSource == RateSource.custom) {
      return double.tryParse(_customRateCtrl.text.replaceAll(',', '.')) ?? 0;
    }
    return _ratesMap[_selectedSource]?.value ?? 0;
  }

  @override
  void initState() {
    super.initState();
    _loadRates();
    _rates.getCustomRate().then((v) {
      if (v != null && mounted) _customRateCtrl.text = v.toStringAsFixed(2);
    });
    for (final c in [
      _costCtrl,
      _marginCtrl,
      _provCtrl,
      _gatewayCtrl,
      _otherCtrl,
      _fixedCtrl,
      _customRateCtrl,
      _inversePriceCtrl,
    ]) {
      c.addListener(() => setState(() {}));
    }
  }

  Future<void> _loadRates() async {
    setState(() => _loadingRates = true);
    try {
      _ratesMap = await _rates.fetchAll();
      _ratesError = null;
    } catch (e) {
      _ratesError = 'Sin conexión: se muestra la última tasa guardada.';
    }
    if (mounted) setState(() => _loadingRates = false);
  }

  @override
  void dispose() {
    for (final c in [
      _costCtrl,
      _marginCtrl,
      _provCtrl,
      _gatewayCtrl,
      _otherCtrl,
      _fixedCtrl,
      _customRateCtrl,
      _inversePriceCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  static String _formatCleanDouble(double val) {
    if (val == 0) return '0';
    final rounded = double.parse(val.toStringAsFixed(2));
    if (rounded % 1 == 0) return rounded.toInt().toString();
    return rounded.toString();
  }

  /// Sincroniza todos los controladores y la fuente de tasa desde un [HistoryEntry] o [Preset].
  void _applyCalculationParams(
    CalculationParamsMixin item, {
    double? customRateOverride,
  }) {
    setState(() {
      _costCtrl.text = _formatCleanDouble(item.costUsd);
      _marginCtrl.text = _formatCleanDouble(item.marginPercent);
      _provCtrl.text = _formatCleanDouble(item.commissionPlatform * 100);
      _gatewayCtrl.text = _formatCleanDouble(item.commissionPaymentMethod * 100);
      _otherCtrl.text = _formatCleanDouble(item.commissionOther * 100);
      _fixedCtrl.text = _formatCleanDouble(item.fixedExpenseBs);
      _roundStep = item.roundStep;
      _selectedSource = item.rateSource;
      _marginMode = item.marginMode;
      if (item.rateSource == RateSource.custom &&
          customRateOverride != null &&
          customRateOverride > 0) {
        _customRateCtrl.text = _formatCleanDouble(customRateOverride);
      }
    });
  }

  void _onSelectHistory(HistoryEntry entry) {
    _applyCalculationParams(
      entry,
      customRateOverride:
          entry.rateSource == RateSource.custom ? entry.rateValue : null,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Cálculo "${entry.title}" cargado')),
    );
  }

  void _onSelectPreset(Preset preset) {
    _applyCalculationParams(
      preset,
      customRateOverride: preset.customRateValue,
    );

    String notice = 'Plantilla "${preset.title}" aplicada';
    if (preset.rateSource != RateSource.custom) {
      final rateObj = _ratesMap[preset.rateSource];
      if (rateObj != null) {
        final age = DateTime.now().difference(rateObj.fetchedAt);
        if (rateObj.isCached || age >= const Duration(hours: 1)) {
          final elapsedLabel = age.inHours >= 1
              ? '${age.inHours} h'
              : '${age.inMinutes < 1 ? 1 : age.inMinutes} min';
          notice = '$notice · Usando tasa de hace $elapsedLabel';
        }
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(notice)),
    );
  }

  /// Registra el cálculo actual en el historial (solo se invoca en acciones explícitas).
  Future<void> _recordCurrentToHistory(double finalPriceBs) async {
    final now = DateTime.now();
    final entry = HistoryEntry(
      id: now.microsecondsSinceEpoch.toString(),
      title: 'Cálculo \$${fmtUsd(_costUsd)} @ ${_selectedSource.label}',
      costUsd: _costUsd,
      marginPercent: _margin * 100,
      fixedExpenseBs: _fixed,
      commissionPlatform: _prov,
      commissionPaymentMethod: _gateway,
      commissionOther: _other,
      roundStep: _roundStep,
      rateSource: _selectedSource,
      marginMode: _marginMode,
      rateValue: _rate,
      finalPriceBs: finalPriceBs,
      timestamp: now,
    );
    await _historyService.addHistoryEntry(entry);
  }

  Future<String> _buildClientMessage(double finalPriceBs) async {
    final profile = await _profileService.getProfile();
    return profile.buildClientMessage(
      finalPriceBs: finalPriceBs,
      rateLabel: _selectedSource.label,
      rateValue: _rate,
    );
  }

  Future<void> _copyPrice(double roundedPriceBs) async {
    await _recordCurrentToHistory(roundedPriceBs);
    await Clipboard.setData(ClipboardData(text: '${fmtBs(roundedPriceBs)} Bs'));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Precio copiado')),
    );
  }

  Future<void> _copyClientMessage(double roundedPriceBs) async {
    await _recordCurrentToHistory(roundedPriceBs);
    final msg = await _buildClientMessage(roundedPriceBs);
    await Clipboard.setData(ClipboardData(text: msg));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Mensaje copiado')),
    );
  }

  Future<void> _shareWhatsApp(double roundedPriceBs) async {
    await _recordCurrentToHistory(roundedPriceBs);
    final msg = await _buildClientMessage(roundedPriceBs);
    final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(msg)}');
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      await Clipboard.setData(ClipboardData(text: msg));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir WhatsApp; mensaje copiado al portapapeles'),
        ),
      );
    }
  }

  Future<void> _promptSavePreset(double roundedPriceBs) async {
    final nameCtrl = TextEditingController(
      text: 'Producto \$${fmtUsd(_costUsd)}',
    );
    final confirmed = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Guardar como plantilla'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nombre de la plantilla',
            hintText: 'Ej. Recarga 100 Diamantes',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(nameCtrl.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (confirmed == null || confirmed.isEmpty) return;

    final now = DateTime.now();
    final idSuffix = now.microsecondsSinceEpoch.toString();
    final preset = Preset(
      id: 'preset_$idSuffix',
      title: confirmed,
      costUsd: _costUsd,
      marginPercent: _margin * 100,
      fixedExpenseBs: _fixed,
      commissionPlatform: _prov,
      commissionPaymentMethod: _gateway,
      commissionOther: _other,
      roundStep: _roundStep,
      rateSource: _selectedSource,
      marginMode: _marginMode,
      customRateValue: _selectedSource == RateSource.custom ? _rate : null,
      createdAt: now,
    );

    final product = ProductItem(
      id: 'prod_$idSuffix',
      name: confirmed,
      costUsd: _costUsd,
      marginPercent: _margin * 100,
      fixedExpenseBs: _fixed,
      commissionPlatform: _prov,
      commissionPaymentMethod: _gateway,
      commissionOther: _other,
      roundStep: _roundStep,
      rateSource: _selectedSource,
      marginMode: _marginMode,
      customRateValue: _selectedSource == RateSource.custom ? _rate : null,
      createdAt: now,
      updatedAt: now,
    );

    await _historyService.savePreset(preset);
    await _productsService.saveProduct(product);
    await _recordCurrentToHistory(roundedPriceBs);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Producto "$confirmed" guardado en Plantillas y Catálogo')),
    );
  }

  void _openHistoryPresetsSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => HistoryPresetsSheet(
        historyService: _historyService,
        ratesMap: _ratesMap,
        customRate: double.tryParse(_customRateCtrl.text.replaceAll(',', '.')) ?? 0,
        onSelectHistory: _onSelectHistory,
        onSelectPreset: _onSelectPreset,
      ),
    );
  }

  void _showMarginModeExplanation() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.help_outline, color: Color(0xFF22C55E)),
            SizedBox(width: 8),
            Expanded(child: Text('¿Cómo se calcula el precio y la tasa?')),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '1. Conversión de Tasa a Bolívares',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              SizedBox(height: 4),
              Text(
                'El costo en bolívares se calcula multiplicando el costo en dólares por la tasa seleccionada (BCV oficial, Binance USDT P2P o tu tasa personalizada):\n'
                '• Costo en Bs = Costo USD × Tasa (Bs/\$)',
                style: TextStyle(fontSize: 13),
              ),
              Divider(height: 24),
              Text(
                '2. Modo "Sobre Costo" (Markup)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              SizedBox(height: 4),
              Text(
                'La ganancia se calcula directamente como un porcentaje sobre lo que te costó el producto:\n'
                '• Fórmula: (Costo en Bs × (1 + Margen) + Gasto Fijo) ÷ (1 − Comisiones)\n\n'
                'Ejemplo: Si compras a \$10 y quieres ganarle el 20 %, tu ganancia base son \$2. '
                'El precio final cubre tus \$10 de costo, tus \$2 de ganancia y las comisiones de pago móvil/pasarela.',
                style: TextStyle(fontSize: 13),
              ),
              Divider(height: 24),
              Text(
                '3. Modo "Sobre Venta" (Margen comercial)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              SizedBox(height: 4),
              Text(
                'El margen representa qué porcentaje del precio final cobrado al cliente te queda como ganancia líquida:\n'
                '• Fórmula: (Costo en Bs + Gasto Fijo) ÷ (1 − Comisiones − Margen)\n\n'
                'Ejemplo: Si fijas 20 % de margen y cobras \$12,50, exactamente el 20 % (\$2,50) es ganancia limpia '
                'y el 80 % restante cubre la reposición del producto y las comisiones.',
                style: TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalComm = _prov + _gateway + _other;
    bool valid = _costUsd > 0 &&
        _rate > 0 &&
        _margin >= 0 &&
        _prov >= 0 &&
        _gateway >= 0 &&
        _other >= 0 &&
        _fixed >= 0 &&
        (_marginMode == MarginMode.onCost
            ? totalComm < 1.0
            : totalComm + _margin < 1.0);
    double? exact;
    double? rounded;
    Breakdown? bd;
    if (valid) {
      try {
        exact = MarginCalculator.salePrice(
          costUsd: _costUsd,
          rate: _rate,
          margin: _margin,
          commissionProvider: _prov,
          commissionGateway: _gateway,
          commissionOther: _other,
          fixedExpenseBs: _fixed,
          marginMode: _marginMode,
        );
        rounded = MarginCalculator.roundUp(exact, _roundStep);
        bd = MarginCalculator.breakdown(
          costUsd: _costUsd,
          rate: _rate,
          margin: _margin,
          commissionProvider: _prov,
          commissionGateway: _gateway,
          commissionOther: _other,
          fixedExpenseBs: _fixed,
          finalPriceBs: rounded,
          marginMode: _marginMode,
        );
      } catch (_) {
        valid = false;
      }
    }

    final inversePrice =
        double.tryParse(_inversePriceCtrl.text.replaceAll(',', '.'));
    final inverseMargin = (valid && inversePrice != null && inversePrice > 0)
        ? MarginCalculator.realMargin(
            costUsd: _costUsd,
            rate: _rate,
            totalCommission: _totalCommission,
            fixedExpenseBs: _fixed,
            currentPriceBs: inversePrice,
            marginMode: _marginMode,
          )
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calculadora de Márgenes VE'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bookmarks_outlined),
            tooltip: 'Historial y plantillas',
            onPressed: _openHistoryPresetsSheet,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar tasas',
            onPressed: _loadRates,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // --- 4 tarjetas de tasa ---
          const Text('Tasa del día', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (_loadingRates)
            const LinearProgressIndicator()
          else
            ...RateSource.values.map((s) => _rateCard(s)),
          if (_ratesError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_ratesError!, style: const TextStyle(color: Colors.orange)),
            ),
          if (_selectedSource == RateSource.custom)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextField(
                controller: _customRateCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Tasa personalizada (Bs/\$)',
                  hintText: 'Ej. 950,00',
                ),
                onChanged: (_) async {
                  final v = double.tryParse(_customRateCtrl.text.replaceAll(',', '.'));
                  if (v != null && v > 0) await _rates.setCustomRate(v);
                },
              ),
            ),
          const SizedBox(height: 16),

          // --- Modo de Cálculo: Sobre costo vs Sobre venta ---
          Row(
            children: [
              const Text('Modo de margen', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.help_outline, size: 20),
                tooltip: '¿Cómo se calcula el precio y la tasa?',
                onPressed: _showMarginModeExplanation,
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
          const SizedBox(height: 4),
          Text(
            _marginMode == MarginMode.onCost
                ? 'Markup directo: Precio = Costo × (1 + Margen) ÷ (1 − Comisiones)'
                : 'Margen comercial: Precio = Costo ÷ (1 − Comisiones − Margen)',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 14),

          // --- Inputs ---
          _numField(_costCtrl, 'Costo del producto (\$)'),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: _numField(
                _marginCtrl,
                _marginMode == MarginMode.onCost
                    ? 'Margen s/costo (%)'
                    : 'Margen s/venta (%)',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: _numField(_fixedCtrl, 'Gasto fijo (Bs)')),
          ]),
          const SizedBox(height: 8),
          const Text('Comisiones (%)', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _commissionChip(
                  label: '0.3% Pago Móvil',
                  ctrl: _gatewayCtrl,
                  targetValue: 0.3,
                ),
                const SizedBox(width: 8),
                _commissionChip(
                  label: '3.0% Pasarela',
                  ctrl: _gatewayCtrl,
                  targetValue: 3.0,
                ),
                const SizedBox(width: 8),
                _commissionChip(
                  label: '1.5% Binance P2P',
                  ctrl: _provCtrl,
                  targetValue: 1.5,
                ),
                const SizedBox(width: 8),
                _commissionChip(
                  label: '2.0% Operativa',
                  ctrl: _provCtrl,
                  targetValue: 2.0,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _numField(_provCtrl, 'Plataforma / Prov.')),
            const SizedBox(width: 8),
            Expanded(child: _numField(_gatewayCtrl, 'Pago Móvil / Pasarela')),
            const SizedBox(width: 8),
            Expanded(child: _numField(_otherCtrl, 'Otra')),
          ]),
          const SizedBox(height: 8),
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
          const SizedBox(height: 16),

          // --- Resultado + desglose paso a paso ---
          if (!valid)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Revisa los datos: el costo y la tasa deben ser mayores que 0, '
                  'y las comisiones deben ser menores al 100 %.',
                ),
              ),
            )
          else if (bd != null && rounded != null && exact != null) ...[
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Precio de venta', style: TextStyle(fontSize: 14)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary.withAlpha(40),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _marginMode.shortLabel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '${fmtBs(rounded)} Bs',
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      _roundStep == 0
                          ? 'Precio exacto · sin redondeo (≈ \$${fmtUsd(rounded / _rate)} USD)'
                          : 'Precio exacto: ${fmtBs(exact)} Bs · redondeado a Bs $_roundStep (≈ \$${fmtUsd(rounded / _rate)} USD)',
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      _marginMode == MarginMode.onCost
                          ? 'Ganancia neta: ${fmtBs(bd.netProfitBs)} Bs (≈ \$${fmtUsd(bd.netProfitBs / _rate)}) · '
                              'margen s/costo: ${(bd.realMarginOnCost * 100).toStringAsFixed(1)} % (s/venta: ${(bd.realMargin * 100).toStringAsFixed(1)} %)'
                          : 'Ganancia neta: ${fmtBs(bd.netProfitBs)} Bs (≈ \$${fmtUsd(bd.netProfitBs / _rate)}) · '
                              'margen real: ${(bd.realMargin * 100).toStringAsFixed(1)} %',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: () => _copyPrice(rounded!),
                          icon: const Icon(Icons.copy, size: 18),
                          label: const Text('Copiar precio'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _copyClientMessage(rounded!),
                          icon: const Icon(Icons.message_outlined, size: 18),
                          label: const Text('Mensaje cliente'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _shareWhatsApp(rounded!),
                          icon: const Icon(Icons.send_outlined, size: 18),
                          label: const Text('WhatsApp'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _promptSavePreset(rounded!),
                          icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                          label: const Text('Guardar como preset'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Desglose paso a paso', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _step('1. Costo en Bs', 'Costo × tasa = \$${fmtUsd(_costUsd)} × ${fmtRate(_rate)} = ${fmtBs(bd.costBs)} Bs'),
            _step('2. Gasto fijo', '${fmtBs(bd.fixedExpenseBs)} Bs'),
            _step(
              '3. Precio exacto (${_marginMode.shortLabel})',
              _marginMode == MarginMode.onCost
                  ? '(${fmtBs(bd.costBs)} × (1 + ${(_margin * 100).toStringAsFixed(1)} %) + ${fmtBs(bd.fixedExpenseBs)}) ÷ (1 − ${(_totalCommission * 100).toStringAsFixed(1)} %) = ${fmtBs(exact)} Bs'
                  : '(${fmtBs(bd.costBs)} + ${fmtBs(bd.fixedExpenseBs)}) ÷ (1 − ${(_totalCommission * 100).toStringAsFixed(1)} % − ${(_margin * 100).toStringAsFixed(1)} %) = ${fmtBs(exact)} Bs',
            ),
            _step(
              '4. Redondeo',
              _roundStep == 0
                  ? '${fmtBs(exact)} Bs (Exacto sin redondeo)'
                  : '${fmtBs(exact)} → ${fmtBs(rounded)} Bs (a Bs $_roundStep)',
            ),
            _step('5. Comisiones (${(_totalCommission * 100).toStringAsFixed(1)} %)',
                '${fmtBs(bd.commissionBs)} Bs (plataforma ${fmtBs(bd.commissionProviderBs)} · pago móvil/pasarela ${fmtBs(bd.commissionGatewayBs)} · otra ${fmtBs(bd.commissionOtherBs)})'),
            _step(
              '6. Ganancia',
              _marginMode == MarginMode.onCost
                  ? '${fmtBs(bd.profitBs)} Bs (${(_margin * 100).toStringAsFixed(1)} % del costo) + ${fmtBs(bd.roundingExtraBs)} Bs por redondeo = ${fmtBs(bd.netProfitBs)} Bs netos'
                  : '${fmtBs(bd.profitBs)} Bs (${(_margin * 100).toStringAsFixed(1)} % de venta) + ${fmtBs(bd.roundingExtraBs)} Bs por redondeo = ${fmtBs(bd.netProfitBs)} Bs netos',
            ),
            _step('Comprobación',
                '${fmtBs(bd.costBs)} + ${fmtBs(bd.fixedExpenseBs)} + ${fmtBs(bd.commissionBs)} + ${fmtBs(bd.netProfitBs)} = ${fmtBs(rounded)} Bs ✓'),
            const SizedBox(height: 16),

            // --- Tabla comparativa 10 %-40 % ---
            Text(
              'Tabla comparativa por margen (${_marginMode.shortLabel})',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: MarginCalculator.comparisonTable(
                  costUsd: _costUsd,
                  rate: _rate,
                  totalCommission: _totalCommission,
                  fixedExpenseBs: _fixed,
                  roundStep: _roundStep,
                  marginMode: _marginMode,
                ).map((row) => ListTile(
                      dense: true,
                      title: Text('${(row.margin * 100).toStringAsFixed(0)} %'),
                      trailing: Text(
                        '${fmtBs(row.roundedPriceBs)} Bs',
                        style: TextStyle(
                          fontWeight: row.margin == _margin ? FontWeight.bold : FontWeight.normal,
                          color: row.margin == _margin
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                      ),
                      subtitle: Text('Ganancia neta ${fmtBs(row.netProfitBs)} Bs'),
                    )).toList(),
              ),
            ),
            const SizedBox(height: 16),

            // --- Calculadora inversa ---
            const Text('Calculadora inversa', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _inversePriceCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Precio actual que cobras (Bs)',
                hintText: 'Ej. 12000',
              ),
            ),
            if (inverseMargin != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  inverseMargin < 0
                      ? 'Margen real: ${(inverseMargin * 100).toStringAsFixed(1)} % — ¡PIERDES DINERO con ese precio!'
                      : 'Margen real con ese precio: ${(inverseMargin * 100).toStringAsFixed(1)} %',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: inverseMargin < 0 ? Colors.red : Colors.green,
                  ),
                ),
              ),
          ],
          const SizedBox(height: 24),
          const Text(
            'Fórmula: Precio = (Costo en Bs + Gasto fijo) ÷ (1 − comisiones − margen). '
            'El margen es sobre el precio de venta, no sobre el costo.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _rateCard(RateSource source) {
    final rate = _ratesMap[source];
    final selected = _selectedSource == source;
    final String subtitle;
    if (source == RateSource.custom) {
      subtitle = 'La escribes tú, sin internet';
    } else if (rate == null) {
      subtitle = 'Sin datos';
    } else {
      final cachedSuffix = rate.isCached ? ' · guardada' : '';
      final effDateStr = (source == RateSource.bcvUsd || source == RateSource.euroBcv) &&
              rate.effectiveDate != null &&
              rate.effectiveDate!.isNotEmpty
          ? ' · ${formatEffectiveDate(rate.effectiveDate)}'
          : '';
      subtitle = '${fmtRate(rate.value)} ${source.unit}$cachedSuffix$effDateStr';
    }
    return Card(
      color: selected ? Theme.of(context).colorScheme.primaryContainer : null,
      child: ListTile(
        title: Text(source.label),
        subtitle: Text(subtitle),
        trailing: selected ? const Icon(Icons.check_circle) : null,
        onTap: () => setState(() => _selectedSource = source),
      ),
    );
  }

  Widget _numField(TextEditingController ctrl, String label) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
    );
  }

  Widget _commissionChip({
    required String label,
    required TextEditingController ctrl,
    required double targetValue,
  }) {
    final current = double.tryParse(ctrl.text.replaceAll(',', '.')) ?? 0.0;
    final isSelected = (current - targetValue).abs() < 0.0001;

    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: isSelected,
      onSelected: (_) {
        setState(() {
          if (isSelected) {
            ctrl.text = '';
          } else {
            ctrl.text = targetValue % 1 == 0
                ? targetValue.toInt().toString()
                : targetValue.toString();
          }
        });
      },
    );
  }

  Widget _step(String title, String detail) {
    return Card(
      child: ListTile(title: Text(title), subtitle: Text(detail)),
    );
  }
}
