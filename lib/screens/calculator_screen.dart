import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/calculation_item.dart';
import '../models/margin_mode.dart';
import '../models/product_item.dart';
import '../models/rate.dart';
import '../services/auth_service.dart';
import '../services/calculator.dart';
import '../services/history_service.dart';
import '../services/price_list_formatter.dart';
import '../services/products_service.dart';
import '../services/rates_service.dart';
import '../services/seller_profile_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/category_picker_field.dart';
import '../widgets/history_presets_sheet.dart';
import 'auth_screen.dart';
import 'result_screen.dart';

/// Pantalla principal estilo ArbiCalc (sin scroll vertical):
/// - Fila de 4 tarjetas de tasa (BCV $, Binance USDT, Euro BCV, Personalizada)
/// - Modo de margen (Sobre costo / Sobre venta) + fila compacta Costo, Margen y Gasto fijo
/// - Comisiones como chips + 3 campos (Plataforma, Pago Móvil, Otra) + Redondeo como chips
/// - Botón verde fijo "Calcular precio" abajo que abre [ResultScreen].
class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  final _rates = RatesService();
  final _authService = AuthService();
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
  Map<RateSource, Rate> _ratesMap = {
    RateSource.bcvUsd: Rate(
      source: RateSource.bcvUsd,
      value: RatesService.fallbackBcvUsd,
      fetchedAt: DateTime.now(),
      isCached: true,
      effectiveDate: '2026-11-10',
    ),
    RateSource.binanceUsdt: Rate(
      source: RateSource.binanceUsdt,
      value: RatesService.fallbackBinanceUsdt,
      fetchedAt: DateTime.now(),
      isCached: true,
    ),
    RateSource.euroBcv: Rate(
      source: RateSource.euroBcv,
      value: RatesService.fallbackEuroBcv,
      fetchedAt: DateTime.now(),
      isCached: true,
      effectiveDate: '2026-11-10',
    ),
  };
  bool _loadingRates = true;
  String? _ratesError;
  int _roundStep = 10;

  double get _costUsd =>
      double.tryParse(_costCtrl.text.replaceAll(',', '.')) ?? 0;
  double get _margin =>
      (double.tryParse(_marginCtrl.text.replaceAll(',', '.')) ?? 0) / 100;
  double get _prov =>
      (double.tryParse(_provCtrl.text.replaceAll(',', '.')) ?? 0) / 100;
  double get _gateway =>
      (double.tryParse(_gatewayCtrl.text.replaceAll(',', '.')) ?? 0) / 100;
  double get _other =>
      (double.tryParse(_otherCtrl.text.replaceAll(',', '.')) ?? 0) / 100;
  double get _fixed =>
      double.tryParse(_fixedCtrl.text.replaceAll(',', '.')) ?? 0;
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
      _gatewayCtrl.text = _formatCleanDouble(
        item.commissionPaymentMethod * 100,
      );
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
      customRateOverride: entry.rateSource == RateSource.custom
          ? entry.rateValue
          : null,
    );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Cálculo "${entry.title}" cargado')));
  }

  void _onSelectPreset(Preset preset) {
    _applyCalculationParams(preset, customRateOverride: preset.customRateValue);

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

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(notice)));
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

  Future<void> _copyPrice(BuildContext activeCtx, double roundedPriceBs) async {
    await _recordCurrentToHistory(roundedPriceBs);
    await Clipboard.setData(ClipboardData(text: '${fmtBs(roundedPriceBs)} Bs'));
    if (!activeCtx.mounted) return;
    ScaffoldMessenger.of(
      activeCtx,
    ).showSnackBar(const SnackBar(content: Text('Precio copiado')));
  }

  Future<void> _copyClientMessage(
    BuildContext activeCtx,
    double roundedPriceBs,
  ) async {
    await _recordCurrentToHistory(roundedPriceBs);
    final msg = await _buildClientMessage(roundedPriceBs);
    await Clipboard.setData(ClipboardData(text: msg));
    if (!activeCtx.mounted) return;
    ScaffoldMessenger.of(
      activeCtx,
    ).showSnackBar(const SnackBar(content: Text('Mensaje copiado')));
  }

  Future<void> _shareWhatsApp(
    BuildContext activeCtx,
    double roundedPriceBs,
  ) async {
    await _recordCurrentToHistory(roundedPriceBs);
    final msg = await _buildClientMessage(roundedPriceBs);
    final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(msg)}');
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && activeCtx.mounted) {
      await Clipboard.setData(ClipboardData(text: msg));
      if (!activeCtx.mounted) return;
      ScaffoldMessenger.of(activeCtx).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo abrir WhatsApp; mensaje copiado al portapapeles',
          ),
        ),
      );
    }
  }

  Future<void> _promptSavePreset(
    BuildContext activeCtx,
    double roundedPriceBs,
  ) async {
    if (AuthService.isFirebaseInitialized && !_authService.isSignedIn) {
      final shouldLogin = await showDialog<bool>(
        context: activeCtx,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.cloud_upload_outlined, color: Colors.teal),
              SizedBox(width: 8),
              Expanded(child: Text('Cuenta requerida')),
            ],
          ),
          content: const Text(
            'Para que tus productos y plantillas se guarden en tu cuenta y aparezcan en la versión web (y viceversa), debes iniciar sesión con tu correo o Google.\n\n¿Deseas iniciar sesión ahora?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.login),
              onPressed: () => Navigator.of(ctx).pop(true),
              label: const Text('Iniciar sesión'),
            ),
          ],
        ),
      );
      if (shouldLogin == true && activeCtx.mounted) {
        await Navigator.of(
          activeCtx,
        ).push(MaterialPageRoute(builder: (_) => const AuthScreen()));
        if (!activeCtx.mounted || !_authService.isSignedIn) return;
      } else {
        return;
      }
    }

    if (!activeCtx.mounted) return;

    final existingProducts = await _productsService.getProducts(
      syncRemote: false,
    );
    if (!activeCtx.mounted) return;
    final existingCategories = extractUniqueCategories(existingProducts);

    final nameCtrl = TextEditingController(
      text: 'Producto \$${fmtUsd(_costUsd)}',
    );
    final categoryCtrl = TextEditingController();
    var selectedCategory = '';

    final result = await showDialog<({String name, String category})>(
      context: activeCtx,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Guardar como plantilla'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del producto / plantilla',
                    hintText: 'Ej. 100 + 10 Diamantes',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                CategoryPickerField(
                  existingCategories: existingCategories,
                  selectedValue: selectedCategory,
                  newCategoryController: categoryCtrl,
                  onChanged: (v) => setDialogState(() => selectedCategory = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final trimmedName = nameCtrl.text.trim();
                if (trimmedName.isEmpty) return;
                Navigator.of(ctx).pop((
                  name: trimmedName,
                  category: resolveSelectedCategory(
                    selectedCategory,
                    categoryCtrl.text,
                  ),
                ));
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    nameCtrl.dispose();
    categoryCtrl.dispose();

    if (result == null || result.name.isEmpty) return;
    final confirmed = result.name;

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
      category: result.category,
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

    try {
      await _historyService.savePreset(preset);
      await _productsService.saveProduct(product);
      await _recordCurrentToHistory(roundedPriceBs);
      if (!activeCtx.mounted) return;
      ScaffoldMessenger.of(activeCtx).showSnackBar(
        SnackBar(
          content: Text(
            'Producto "$confirmed" guardado en tu cuenta y catálogo',
          ),
        ),
      );
    } catch (e) {
      if (!activeCtx.mounted) return;
      ScaffoldMessenger.of(activeCtx).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade800,
          content: Text('Error al guardar en la nube: $e'),
        ),
      );
    }
  }

  void _openHistoryPresetsSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => HistoryPresetsSheet(
        historyService: _historyService,
        ratesMap: _ratesMap,
        customRate:
            double.tryParse(_customRateCtrl.text.replaceAll(',', '.')) ?? 0,
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

  void _onCalculatePressed({
    required bool valid,
    required double? exact,
    required double? rounded,
    required Breakdown? bd,
  }) {
    FocusScope.of(context).unfocus();
    if (!valid || exact == null || rounded == null || bd == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Revisa los datos: el costo y la tasa deben ser mayores que 0, '
            'y las comisiones deben ser menores al 100 %.',
          ),
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ResultScreen(
          costUsd: _costUsd,
          rate: _rate,
          rateSource: _selectedSource,
          margin: _margin,
          marginMode: _marginMode,
          commissionProvider: _prov,
          commissionGateway: _gateway,
          commissionOther: _other,
          fixedExpenseBs: _fixed,
          roundStep: _roundStep,
          exactPriceBs: exact,
          roundedPriceBs: rounded,
          breakdown: bd,
          inversePriceController: _inversePriceCtrl,
          onCopyPrice: _copyPrice,
          onCopyClientMessage: _copyClientMessage,
          onShareWhatsApp: _shareWhatsApp,
          onSavePreset: _promptSavePreset,
        ),
      ),
    );
  }

  InputDecoration _compactDecoration({
    required String labelText,
    String? prefixText,
    String? suffixText,
    String? hintText,
    required bool ultraTight,
    required bool tight,
  }) {
    final colors = context.appColors;
    final vPad = ultraTight ? 4.0 : (tight ? 7.0 : 9.0);
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      prefixText: prefixText,
      suffixText: suffixText,
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 9, vertical: vPad),
      labelStyle: TextStyle(
        color: colors.textMuted,
        fontSize: ultraTight ? 10.5 : 11.5,
      ),
      floatingLabelStyle: TextStyle(
        color: colors.primary,
        fontSize: ultraTight ? 10.0 : 11.0,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final totalComm = _prov + _gateway + _other;
    bool valid =
        _costUsd > 0 &&
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

    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: colors.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: colors.primary.withValues(alpha: 0.6),
                      blurRadius: 9,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Text('Calculadora de Márgenes VE'),
            ],
          ),
        ),
        actions: [
          IconButton(
            style: IconButton.styleFrom(
              backgroundColor: colors.surface,
              foregroundColor: colors.textPrimary,
              side: BorderSide(color: colors.borderSubtle),
              shape: const CircleBorder(),
              minimumSize: const Size(38, 38),
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.bookmarks_outlined, size: 19),
            tooltip: 'Historial y plantillas',
            onPressed: _openHistoryPresetsSheet,
          ),
          const SizedBox(width: 4),
          IconButton(
            style: IconButton.styleFrom(
              backgroundColor: colors.surface,
              foregroundColor: colors.textPrimary,
              side: BorderSide(color: colors.borderSubtle),
              shape: const CircleBorder(),
              minimumSize: const Size(38, 38),
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.refresh, size: 19),
            tooltip: 'Actualizar tasas',
            onPressed: _loadRates,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final h = constraints.maxHeight;
          final extraRows =
              (_selectedSource == RateSource.custom ? 1 : 0) +
              (_ratesError != null ? 1 : 0);

          final tight = h < (560 + extraRows * 34);
          final ultraTight = h < (470 + extraRows * 30);
          // En teléfonos altos (>= 650 lógicos) las secciones crecen de verdad:
          // tarjetas de tasa 76 px, inputs 54 px, padding 16 px y chips/segmentos
          // de 34/36 px. Las secciones se reparten el sobrante con Expanded.
          final generous = h >= (650 + extraRows * 70);

          final outerVPad = ultraTight
              ? 4.0
              : (tight ? 6.0 : (generous ? 14.0 : 10.0));
          final gap = ultraTight ? 4.0 : (tight ? 6.0 : 10.0);
          final cardPad = ultraTight
              ? 6.0
              : (tight ? 8.5 : (generous ? 16.0 : 11.0));
          final fieldGap = ultraTight
              ? 4.0
              : (tight ? 6.0 : (generous ? 10.0 : 8.5));
          final rateCarouselHeight = ultraTight
              ? 62.0
              : (tight ? 64.0 : (generous ? 76.0 : 68.0));
          final ctaHeight = ultraTight
              ? 38.0
              : (tight ? 43.0 : (generous ? 52.0 : 48.0));
          final inputHeight = ultraTight
              ? 32.0
              : (tight ? 36.0 : (generous ? 54.0 : 41.0));
          final segmentHeight = ultraTight
              ? 26.0
              : (tight ? 30.0 : (generous ? 36.0 : 30.0));
          final chipHeight = ultraTight
              ? 25.0
              : (tight ? 29.0 : (generous ? 34.0 : 29.0));
          // El selector de tasa necesita más alto cuando aparece el campo de
          // tasa personalizada; así el reparto flex no lo comprime.
          final rateFlex = extraRows > 0 ? 6 : 5;

          return Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: outerVPad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_ratesError != null) ...[
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: ultraTight ? 2 : 4,
                    ),
                    decoration: BoxDecoration(
                      color: colors.amber.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: colors.amber.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          color: colors.amber,
                          size: 13,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _ratesError!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.amber,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: gap),
                ],

                // 1. Selector de tasa: las 4 tarjetas en una sola fila (sin scroll horizontal)
                Expanded(
                  flex: rateFlex,
                  child: Container(
                    key: const Key('rate_section'),
                    padding: EdgeInsets.all(cardPad),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: colors.borderSubtle),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 3.5,
                              height: 13,
                              decoration: BoxDecoration(
                                color: colors.primary,
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Tasa del día',
                              style: TextStyle(
                                fontSize: ultraTight ? 11.5 : 12.5,
                                fontWeight: FontWeight.w800,
                                color: colors.primary,
                              ),
                            ),
                            if (_loadingRates) ...[
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 11,
                                height: 11,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.8,
                                  color: colors.primary,
                                ),
                              ),
                            ],
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _rate > 0
                                    ? '${_selectedSource.label} · ${fmtRate(_rate)} ${_selectedSource.unit}'
                                    : _selectedSource.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.end,
                                style: TextStyle(
                                  fontSize: ultraTight ? 10.5 : 11.5,
                                  fontWeight: FontWeight.w800,
                                  color: colors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: ultraTight ? 4 : 6),
                        SizedBox(
                          height: rateCarouselHeight,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (
                                var i = 0;
                                i < RateSource.values.length;
                                i++
                              ) ...[
                                if (i > 0) const SizedBox(width: 6),
                                Expanded(
                                  child: _rateCarouselCard(
                                    RateSource.values[i],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (_selectedSource == RateSource.custom) ...[
                          SizedBox(height: fieldGap),
                          SizedBox(
                            height: inputHeight,
                            child: TextField(
                              controller: _customRateCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              style: TextStyle(
                                fontSize: ultraTight ? 12.5 : 13.5,
                                fontWeight: FontWeight.w700,
                              ),
                              decoration: _compactDecoration(
                                labelText: 'Tasa personalizada (Bs/\$)',
                                hintText: 'Ej. 950,00',
                                suffixText: 'Bs/\$',
                                ultraTight: ultraTight,
                                tight: tight,
                              ),
                              onChanged: (_) async {
                                final v = double.tryParse(
                                  _customRateCtrl.text.replaceAll(',', '.'),
                                );
                                if (v != null && v > 0) {
                                  await _rates.setCustomRate(v);
                                }
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                SizedBox(height: gap),

                // 2. Modo de margen (segmento) + Costo, Margen y Gasto fijo en una fila
                Expanded(
                  flex: 5,
                  child: Container(
                    key: const Key('margin_section'),
                    padding: EdgeInsets.all(cardPad),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: colors.borderSubtle),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Modo de margen',
                              style: TextStyle(
                                fontSize: ultraTight ? 11.5 : 12.5,
                                fontWeight: FontWeight.w800,
                                color: colors.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 4),
                            SizedBox(
                              width: 22,
                              height: 22,
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                icon: Icon(
                                  Icons.help_outline,
                                  size: 15,
                                  color: colors.textSecondary,
                                ),
                                tooltip:
                                    '¿Cómo se calcula el precio y la tasa?',
                                onPressed: _showMarginModeExplanation,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: SizedBox(
                                height: segmentHeight,
                                child: SegmentedButton<MarginMode>(
                                  showSelectedIcon: false,
                                  style: ButtonStyle(
                                    visualDensity: VisualDensity.compact,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    padding: const WidgetStatePropertyAll(
                                      EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 0,
                                      ),
                                    ),
                                    textStyle: WidgetStatePropertyAll(
                                      TextStyle(
                                        fontSize: ultraTight ? 10.5 : 11.5,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  segments: const [
                                    ButtonSegment(
                                      value: MarginMode.onCost,
                                      label: Text('Sobre costo'),
                                    ),
                                    ButtonSegment(
                                      value: MarginMode.onSale,
                                      label: Text('Sobre venta'),
                                    ),
                                  ],
                                  selected: {_marginMode},
                                  onSelectionChanged: (s) =>
                                      setState(() => _marginMode = s.first),
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: fieldGap),
                        Row(
                          children: [
                            Expanded(
                              flex: 11,
                              child: SizedBox(
                                height: inputHeight,
                                child: _numField(
                                  _costCtrl,
                                  'Costo del producto (\$)',
                                  prefixText: '\$ ',
                                  ultraTight: ultraTight,
                                  tight: tight,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              flex: 11,
                              child: SizedBox(
                                height: inputHeight,
                                child: _numField(
                                  _marginCtrl,
                                  _marginMode == MarginMode.onCost
                                      ? 'Margen s/costo (%)'
                                      : 'Margen s/venta (%)',
                                  suffixText: '%',
                                  ultraTight: ultraTight,
                                  tight: tight,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              flex: 9,
                              child: SizedBox(
                                height: inputHeight,
                                child: _numField(
                                  _fixedCtrl,
                                  'Gasto fijo (Bs)',
                                  suffixText: 'Bs',
                                  ultraTight: ultraTight,
                                  tight: tight,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                SizedBox(height: gap),

                // 3. Comisiones (chips + 3 campos) y Redondeo (chips)
                Expanded(
                  flex: 7,
                  child: Container(
                    key: const Key('commissions_section'),
                    padding: EdgeInsets.all(cardPad),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: colors.borderSubtle),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Comisiones (%)',
                              style: TextStyle(
                                fontSize: ultraTight ? 11.5 : 12.5,
                                fontWeight: FontWeight.w800,
                                color: colors.textPrimary,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: colors.primary.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: colors.primary.withValues(alpha: 0.4),
                                ),
                              ),
                              child: Text(
                                'Total ${(_totalCommission * 100).toStringAsFixed(1)}%',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: colors.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: ultraTight ? 3 : 5),
                        Row(
                          children: [
                            Expanded(
                              child: _commissionChip(
                                label: '0.3% Pago Móvil',
                                ctrl: _gatewayCtrl,
                                targetValue: 0.3,
                                height: chipHeight,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: _commissionChip(
                                label: '3.0% Pasarela',
                                ctrl: _gatewayCtrl,
                                targetValue: 3.0,
                                height: chipHeight,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: _commissionChip(
                                label: '1.5% Binance P2P',
                                ctrl: _provCtrl,
                                targetValue: 1.5,
                                height: chipHeight,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: _commissionChip(
                                label: '2.0% Operativa',
                                ctrl: _provCtrl,
                                targetValue: 2.0,
                                height: chipHeight,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: fieldGap),
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: inputHeight,
                                child: _numField(
                                  _provCtrl,
                                  'Plataforma / Prov.',
                                  suffixText: '%',
                                  ultraTight: ultraTight,
                                  tight: tight,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: SizedBox(
                                height: inputHeight,
                                child: _numField(
                                  _gatewayCtrl,
                                  'Pago Móvil / Pasarela',
                                  suffixText: '%',
                                  ultraTight: ultraTight,
                                  tight: tight,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: SizedBox(
                                height: inputHeight,
                                child: _numField(
                                  _otherCtrl,
                                  'Otra',
                                  suffixText: '%',
                                  ultraTight: ultraTight,
                                  tight: tight,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: fieldGap),
                        Row(
                          children: [
                            Text(
                              'Redondeo',
                              style: TextStyle(
                                fontSize: ultraTight ? 10.5 : 11.5,
                                fontWeight: FontWeight.w800,
                                color: colors.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SizedBox(
                                height: segmentHeight,
                                child: SegmentedButton<int>(
                                  showSelectedIcon: false,
                                  style: ButtonStyle(
                                    visualDensity: VisualDensity.compact,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    padding: const WidgetStatePropertyAll(
                                      EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 0,
                                      ),
                                    ),
                                    textStyle: WidgetStatePropertyAll(
                                      TextStyle(
                                        fontSize: ultraTight ? 10.5 : 11.5,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  segments: const [
                                    ButtonSegment(
                                      value: 0,
                                      label: Text('Exacto'),
                                    ),
                                    ButtonSegment(
                                      value: 10,
                                      label: Text('Bs 10'),
                                    ),
                                    ButtonSegment(
                                      value: 50,
                                      label: Text('Bs 50'),
                                    ),
                                    ButtonSegment(
                                      value: 100,
                                      label: Text('Bs 100'),
                                    ),
                                  ],
                                  selected: {_roundStep},
                                  onSelectionChanged: (s) =>
                                      setState(() => _roundStep = s.first),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                SizedBox(height: gap),

                // 4. Botón verde fijo "Calcular precio" abajo
                SizedBox(
                  height: ctaHeight,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [colors.primary, colors.primaryDark],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: colors.primary.withValues(alpha: 0.28),
                          blurRadius: 12,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: ElevatedButton.icon(
                      key: const Key('calc_submit_button'),
                      onPressed: () => _onCalculatePressed(
                        valid: valid,
                        exact: exact,
                        rounded: rounded,
                        bd: bd,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: const Color(0xFF04140A),
                        shadowColor: Colors.transparent,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: Icon(
                        Icons.calculate_rounded,
                        size: ultraTight ? 17 : 20,
                        color: const Color(0xFF04140A),
                      ),
                      label: Text(
                        'Calcular precio',
                        style: TextStyle(
                          color: const Color(0xFF04140A),
                          fontSize: ultraTight ? 13.5 : 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _rateCarouselCard(RateSource source) {
    final rate = _ratesMap[source];
    final selected = _selectedSource == source;
    final colors = context.appColors;

    final bool hasTodayBadge =
        rate != null &&
        (source == RateSource.bcvUsd || source == RateSource.euroBcv);

    final String subtitleText;
    var isNumericRate = true;
    if (source == RateSource.custom) {
      final customVal =
          double.tryParse(_customRateCtrl.text.replaceAll(',', '.')) ?? 0;
      subtitleText = customVal > 0
          ? '${fmtRate(customVal)} Bs/\$'
          : 'La escribes tú, sin internet';
      isNumericRate = customVal > 0;
    } else if (rate == null) {
      subtitleText = 'Sin datos';
    } else {
      subtitleText = '${fmtRate(rate.value)} ${source.unit}';
    }

    final valueStyle = TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w700,
      color: selected ? colors.primary : colors.textMuted,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return GestureDetector(
      key: Key('rate_card_${source.name}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _selectedSource = source),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        decoration: BoxDecoration(
          color: selected
              ? colors.primary.withValues(alpha: 0.16)
              : colors.surfaceElevated,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: selected ? colors.primary : colors.borderSubtle,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  source == RateSource.bcvUsd
                      ? Icons.account_balance_rounded
                      : source == RateSource.binanceUsdt
                      ? Icons.currency_bitcoin
                      : source == RateSource.euroBcv
                      ? Icons.euro_rounded
                      : Icons.tune_rounded,
                  size: 14,
                  color: selected ? colors.primary : colors.textSecondary,
                ),
                const Spacer(),
                if (hasTodayBadge)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 0.5,
                    ),
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'Hoy',
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: TextStyle(
                        fontSize: 8,
                        letterSpacing: 0,
                        fontWeight: FontWeight.w800,
                        color: colors.primary,
                      ),
                    ),
                  ),
                if (selected) ...[
                  if (hasTodayBadge) const SizedBox(width: 1),
                  Icon(Icons.check_circle, color: colors.primary, size: 11),
                ],
              ],
            ),
            const SizedBox(height: 2),
            // Etiqueta a todo el ancho debajo del icono. FittedBox la escala
            // solo si hace falta, para que nunca se lea "Binance US..." ni
            // "Personaliza...". El icono ya no compite por el ancho del texto.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                source.label,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: selected ? colors.textPrimary : colors.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 1),
            if (isNumericRate)
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(subtitleText, maxLines: 1, style: valueStyle),
              )
            else
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  subtitleText,
                  maxLines: 1,
                  softWrap: false,
                  style: valueStyle.copyWith(fontSize: 9.5),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _numField(
    TextEditingController ctrl,
    String label, {
    String? prefixText,
    String? suffixText,
    required bool ultraTight,
    required bool tight,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: TextStyle(
        fontSize: ultraTight ? 12.5 : 13.5,
        fontWeight: FontWeight.w700,
      ),
      decoration: _compactDecoration(
        labelText: label,
        prefixText: prefixText,
        suffixText: suffixText,
        ultraTight: ultraTight,
        tight: tight,
      ),
    );
  }

  Widget _commissionChip({
    required String label,
    required TextEditingController ctrl,
    required double targetValue,
    required double height,
  }) {
    final current = double.tryParse(ctrl.text.replaceAll(',', '.')) ?? 0.0;
    final isSelected = (current - targetValue).abs() < 0.0001;

    return SizedBox(
      height: height,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: FilterChip(
          showCheckmark: false,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
          labelPadding: const EdgeInsets.symmetric(horizontal: 2),
          label: Text(label, style: const TextStyle(fontSize: 11.5)),
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
        ),
      ),
    );
  }
}
