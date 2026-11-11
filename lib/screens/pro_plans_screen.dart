import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/rate.dart';
import '../models/subscription_state.dart';
import '../services/auth_service.dart';
import '../services/rates_service.dart';
import '../services/subscription_service.dart';
import '../utils/format.dart';
import 'auth_screen.dart';

/// Pantalla de Planes Pro ($1,99 Mensual · $4,99 Trimestral · $7,99 6 Meses · $14,99 Anual)
/// con verificación automática vía Pabilo, respaldo manual y Panel Admin propietario.
class ProPlansScreen extends StatefulWidget {
  final ProPlanId initialPlan;

  const ProPlansScreen({
    super.key,
    this.initialPlan = ProPlanId.annual,
  });

  @override
  State<ProPlansScreen> createState() => _ProPlansScreenState();
}

class _ProPlansScreenState extends State<ProPlansScreen> {
  final _subService = SubscriptionService.instance;
  final _authService = AuthService();
  final _ratesService = RatesService();
  final _refCtrl = TextEditingController();

  late ProPlanId _selectedPlan;
  ProPaymentMethod _selectedMethod = ProPaymentMethod.pagoMovil;

  SubscriptionState _subState = const SubscriptionState.free();
  Map<String, dynamic>? _pendingDoc;
  ProPaymentConfig _paymentConfig = const ProPaymentConfig();
  double _bcvRate = 0;

  ProCheckoutOrder? _activeOrder;
  _PayBanner? _statusBanner;
  bool _loadingConfig = true;
  bool _creatingOrder = false;
  bool _verifying = false;

  @override
  void initState() {
    super.initState();
    _selectedPlan = widget.initialPlan;
    _subService.ensureStarted();
    _subState = _subService.currentState;
    _pendingDoc = _subService.pendingNotifier.value;
    _subService.stateNotifier.addListener(_onSubChanged);
    _subService.pendingNotifier.addListener(_onPendingChanged);
    _loadInitialData();
  }

  @override
  void dispose() {
    _subService.stateNotifier.removeListener(_onSubChanged);
    _subService.pendingNotifier.removeListener(_onPendingChanged);
    _refCtrl.dispose();
    super.dispose();
  }

  void _onSubChanged() {
    if (!mounted) return;
    setState(() => _subState = _subService.currentState);
  }

  void _onPendingChanged() {
    if (!mounted) return;
    setState(() => _pendingDoc = _subService.pendingNotifier.value);
  }

  Future<void> _loadInitialData() async {
    setState(() => _loadingConfig = true);
    try {
      await _subService.refreshSubscription();
      final savedOrder = await _subService.loadSavedOrder();
      final results = await Future.wait<Object?>([
        _ratesService.fetchAll().catchError((_) => <RateSource, Rate>{}),
        _subService
            .fetchPaymentConfig()
            .then<ProPaymentConfig?>((value) => value)
            .catchError((_) => null),
      ]);
      final ratesMap = results[0] as Map<RateSource, Rate>?;
      final remoteCfg = results[1] as ProPaymentConfig?;
      final bcvFromRates = ratesMap?[RateSource.bcvUsd]?.value ?? 0;

      if (!mounted) return;
      setState(() {
        if (_activeOrder == null && savedOrder != null) {
          _activeOrder = savedOrder;
          _selectedPlan = savedOrder.plan;
          _selectedMethod = savedOrder.method;
        }
        if (remoteCfg != null) {
          _paymentConfig = remoteCfg;
        }
        _bcvRate = (remoteCfg?.bcvUsd != null && remoteCfg!.bcvUsd! > 0)
            ? remoteCfg.bcvUsd!
            : bcvFromRates;
      });
    } finally {
      if (mounted) setState(() => _loadingConfig = false);
    }
  }

  bool get _autoVerifyEnabled => _selectedMethod == ProPaymentMethod.pagoMovil
      ? _paymentConfig.pagoMovil.autoVerify
      : _paymentConfig.usdt.autoVerify;

  ProCheckoutOrder? get _matchingOrder {
    final ord = _activeOrder;
    if (ord == null) return null;
    if (ord.plan != _selectedPlan || ord.method != _selectedMethod) {
      return null;
    }
    if (ord.isExpired) return null;
    return ord;
  }

  bool _requireRealUser() {
    final user = _authService.currentUser;
    if (user == null || user.isAnonymous) {
      return false;
    }
    return true;
  }

  Future<void> _openAuth() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
    );
    await _loadInitialData();
  }

  Future<ProCheckoutOrder?> _createOrder({bool silent = false}) async {
    if (!_requireRealUser()) {
      await _promptSignInRequired();
      return null;
    }
    if (!silent) {
      setState(() {
        _creatingOrder = true;
        _statusBanner = null;
      });
    }
    try {
      final order = await _subService.createCheckout(
        plan: _selectedPlan,
        method: _selectedMethod,
      );
      await _subService.saveActiveOrder(order);
      if (!mounted) return order;
      setState(() {
        _activeOrder = order;
        if (order.rateBs > 0) _bcvRate = order.rateBs;
        if (!silent) {
          _statusBanner = const _PayBanner(
            tone: _BannerTone.info,
            message:
                'Orden creada con tasa BCV congelada por 30 minutos. Transfiere el monto exacto y pega tu referencia abajo.',
          );
        }
      });
      return order;
    } catch (e) {
      if (mounted && !silent) {
        setState(() {
          _statusBanner = _PayBanner(
            tone: _BannerTone.error,
            message: e.toString(),
          );
        });
      }
      if (silent) rethrow;
      return null;
    } finally {
      if (mounted && !silent) {
        setState(() => _creatingOrder = false);
      }
    }
  }

  Future<void> _submitVerifyOrManual({bool forceManual = false}) async {
    if (!_requireRealUser()) {
      await _promptSignInRequired();
      return;
    }

    final useManual = forceManual || !_autoVerifyEnabled;
    final cleanRef = SubscriptionService.normalizeReference(
      _refCtrl.text,
      allowLetters: useManual || _selectedMethod.allowLetters,
    );

    if (cleanRef.length < _selectedMethod.minRefLength) {
      _showSnack(
        _selectedMethod.allowLetters
            ? 'Ingresa el ID de orden o TxID completo (mínimo 6 caracteres).'
            : 'Ingresa los dígitos de la referencia bancaria (mínimo 4 dígitos).',
      );
      return;
    }

    if (useManual) {
      await _submitManualFallback(cleanRef);
      return;
    }

    if (_verifying) return;
    setState(() {
      _verifying = true;
      _statusBanner = _PayBanner(
        tone: _BannerTone.info,
        message: _selectedMethod == ProPaymentMethod.pagoMovil
            ? 'Verificando tu referencia automáticamente con Pabilo… Si pagaste vía BDV puede tardar 15 a 35 segundos, no cierres esta pantalla.'
            : 'Verificando tu orden de Binance Pay automáticamente con Pabilo… Un momento por favor, no cierres esta pantalla.',
      );
    });

    try {
      var ord = _matchingOrder;
      ord ??= await _createOrder(silent: true);
      if (ord == null) return;

      final res = await _subService.verifyPayment(
        orderId: ord.id,
        reference: cleanRef,
      );
      if (!mounted) return;

      if (res.isActivated) {
        _refCtrl.clear();
        await _subService.saveActiveOrder(null);
        if (!mounted) return;
        setState(() {
          _activeOrder = null;
          _subState = _subService.currentState;
          _statusBanner = const _PayBanner(
            tone: _BannerTone.success,
            message:
                '¡Suscripción Pro activada automáticamente! Ya tienes todas las funciones desbloqueadas.',
          );
        });
        _showSnack('¡Plan Pro activado al instante!');
      } else if (res.isPartial) {
        _refCtrl.clear();
        final nextOrder = ord.withPartialUpdate(
          paidAmount: res.paidAmount ?? ord.paidAmount,
          remainingAmount: res.remainingAmount ?? ord.remainingAmount,
          expiresAt: res.expiresAt,
        );
        await _subService.saveActiveOrder(nextOrder);
        if (!mounted) return;
        final remText = res.remainingAmount?.toStringAsFixed(2);
        setState(() {
          _activeOrder = nextOrder;
          _statusBanner = _PayBanner(
            tone: _BannerTone.warning,
            message: res.message.isNotEmpty
                ? res.message
                : 'Abono parcial recibido. Transfiere la diferencia e ingresa la nueva referencia.',
            copyAmountText: remText,
          );
        });
      } else if (res.fallbackManual) {
        setState(() {
          _statusBanner = _PayBanner(
            tone: _BannerTone.warning,
            message: res.message,
            showManualFallbackAction: true,
          );
        });
      } else if (res.code == 'ORDER_EXPIRED') {
        await _subService.saveActiveOrder(null);
        if (!mounted) return;
        setState(() {
          _activeOrder = null;
          _statusBanner = _PayBanner(
            tone: _BannerTone.warning,
            message: res.message,
          );
        });
      } else {
        setState(() {
          _statusBanner = _PayBanner(
            tone: res.retryable ? _BannerTone.warning : _BannerTone.error,
            message: res.message.isNotEmpty
                ? res.message
                : 'No pudimos confirmar el pago. Revisa la referencia e intenta otra vez.',
          );
        });
      }
    } catch (e) {
      if (!mounted) return;
      final isTimeout = e.toString().toLowerCase().contains('timeout');
      setState(() {
        _statusBanner = _PayBanner(
          tone: _BannerTone.warning,
          message: isTimeout
              ? 'El banco tardó más de lo normal en responder. Toca «Verificar» de nuevo con la misma referencia para reconciliar automáticamente.'
              : '${e.toString()} (Puedes reintentar o enviarlo para validación manual).',
          showManualFallbackAction: !isTimeout,
        );
      });
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _submitManualFallback(String cleanRef) async {
    setState(() => _verifying = true);
    try {
      final estBs =
          SubscriptionState.planBsEstimate(_selectedPlan, _bcvRate);
      await _subService.submitManualFallback(
        plan: _selectedPlan,
        method: _selectedMethod,
        reference: cleanRef,
        amountUsd: _selectedPlan.priceUsd,
        amountBs: estBs > 0 ? estBs : null,
        rateBs: _bcvRate > 0 ? _bcvRate : null,
      );
      if (!mounted) return;
      _refCtrl.clear();
      setState(() {
        _statusBanner = const _PayBanner(
          tone: _BannerTone.info,
          message:
              'Referencia enviada para revisión manual. Activaremos tu Pro al verificarla.',
        );
      });
      _showSnack('Referencia enviada para validación manual.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusBanner = _PayBanner(
          tone: _BannerTone.error,
          message: e.toString(),
        );
      });
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _promptSignInRequired() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cuenta requerida'),
        content: const Text(
          'Inicia sesión con tu correo o Google para vincular la suscripción Pro a tu cuenta en la app y en la web.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.login),
            label: const Text('Iniciar sesión'),
          ),
        ],
      ),
    );
    if (go == true && mounted) {
      await _openAuth();
    }
  }

  void _copy(String value, String label) {
    Clipboard.setData(ClipboardData(text: value));
    _showSnack('$label copiado');
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Planes Pro'),
        actions: [
          IconButton(
            tooltip: 'Actualizar tasas y estado',
            onPressed: _loadInitialData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadInitialData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildStatusCard(),
            if (_shouldShowPendingCard()) ...[
              const SizedBox(height: 12),
              _buildPendingCard(),
            ],
            const SizedBox(height: 16),
            _buildPlanCards(),
            const SizedBox(height: 16),
            _buildPaymentBox(),
            if (_subService.isCurrentUserAdmin) ...[
              const SizedBox(height: 16),
              _buildAdminEntryCard(),
            ],
            const SizedBox(height: 14),
            const Text(
              'La calculadora completa, tasas en vivo y brecha cambiaria siempre son gratis. '
              'El pago Pro no es reembolsable salvo error técnico comprobado; al vencer vuelve automáticamente a Gratis si no renuevas.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    final user = _authService.currentUser;
    final dateFmt = DateFormat('dd/MM/yyyy', 'es_VE');
    if (user == null || user.isAnonymous) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Modo invitado / sin cuenta vinculada',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 6),
              const Text(
                'Inicia sesión con tu correo o Google para sincronizar tu suscripción Pro entre Android y margencalcu.online.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _openAuth,
                icon: const Icon(Icons.login),
                label: const Text('Entrar / Crear cuenta'),
              ),
            ],
          ),
        ),
      );
    }

    if (_subState.isPro) {
      final parsedPlan = ProPlanId.tryParse(_subState.plan) ?? ProPlanId.monthly;
      final planLabel = '${parsedPlan.displayName} (${parsedPlan.formattedUsd})';
      final startStr = _subState.startDate != null
          ? dateFmt.format(_subState.startDate!.toLocal())
          : 'Hoy';
      final endStr = _subState.endDate != null
          ? dateFmt.format(_subState.endDate!.toLocal())
          : 'Activo';
      return Card(
        color: Theme.of(context)
            .colorScheme
            .primaryContainer
            .withValues(alpha: 0.35),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'PRO ACTIVO',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      planLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Inicio: $startStr · Vence: $endStr (${_subState.daysLeft} días restantes)\n'
                'Cuenta: ${user.email ?? user.uid}. Si renuevas antes del vencimiento, los días se suman.',
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    if (_subState.status == SubscriptionStatus.expired &&
        _subState.endDate != null) {
      return Card(
        color: Colors.amber.withValues(alpha: 0.14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Tu suscripción Pro venció el ${dateFmt.format(_subState.endDate!.toLocal())}. '
            'Volviste al Plan Gratis (hasta 10 productos). Todos tus productos anteriores se conservan; renueva abajo para recuperar Pro.',
            style: const TextStyle(fontSize: 13),
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Plan actual: Gratis (${user.email ?? 'Cuenta activa'})\n'
          'Incluye calculadora ilimitada, tasas/brecha y hasta 10 productos en la nube. Actualiza a Pro abajo en segundos.',
          style: const TextStyle(fontSize: 13),
        ),
      ),
    );
  }

  bool _shouldShowPendingCard() {
    final p = _pendingDoc;
    if (p == null || p['status'] != 'pending') return false;
    if (!_subState.isPro) return true;
    final reqAt = p['requestedAt']?.toString() ?? '';
    final curStart = _subState.startDate?.toUtc().toIso8601String() ?? '';
    return reqAt.compareTo(curStart) > 0;
  }

  Widget _buildPendingCard() {
    final p = _pendingDoc!;
    final parsed = ProPlanId.tryParse(p['plan']?.toString()) ?? ProPlanId.monthly;
    final planTxt = '${parsed.shortName} (${parsed.formattedUsd})';
    final methodTxt = p['method'] == 'usdt' ? 'USDT' : 'Pago Móvil';
    return Card(
      color: Colors.orange.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Text(
          '⏳ Pago pendiente de validación manual: $planTxt vía $methodTxt · Ref: ${p['reference'] ?? ''}',
          style: const TextStyle(fontSize: 13),
        ),
      ),
    );
  }

  Widget _buildPlanCards() {
    return Column(
      children: [
        _buildSinglePlanCard(
          plan: ProPlanId.annual,
          badge: 'RECOMENDADO · Ahorra 37%',
          subtitle: 'Frente a 12 × \$1,99 = \$23,88 al año (365 días)',
          features: const [
            'Productos ilimitados en la nube (app y web)',
            'Historial ilimitado, reportes y exportación Excel/PDF',
            'Revalorización masiva en 1 toque y alertas de brecha',
            'Lista de precios profesional e importación Excel/CSV',
          ],
        ),
        const SizedBox(height: 12),
        _buildSinglePlanCard(
          plan: ProPlanId.semiannual,
          badge: '6 Meses · Ahorra 33%',
          subtitle: 'Frente a 6 × \$1,99 = \$11,94 (180 días)',
          features: const [
            'Todas las funciones Pro durante 6 meses continuos',
            'Productos ilimitados, historial, lote y revalorización',
            'Reportes Excel/PDF, alertas BCV y soporte prioritario',
          ],
        ),
        const SizedBox(height: 12),
        _buildSinglePlanCard(
          plan: ProPlanId.quarterly,
          badge: 'Trimestral · Ahorra 16%',
          subtitle: 'Frente a 3 × \$1,99 = \$5,97 (90 días)',
          features: const [
            'Todas las funciones Pro durante 3 meses continuos',
            'Catálogo, reportes, lote y lista de precios sin límites',
          ],
        ),
        const SizedBox(height: 12),
        _buildSinglePlanCard(
          plan: ProPlanId.monthly,
          badge: 'Mensual',
          subtitle: 'Facturación de 30 días sin permanencia',
          features: const [
            'Todas las herramientas Pro durante 30 días',
            'Productos y categorías ilimitadas',
            'Activación automática inmediata al verificar pago',
          ],
        ),
      ],
    );
  }

  Widget _buildSinglePlanCard({
    required ProPlanId plan,
    required String badge,
    required String subtitle,
    required List<String> features,
  }) {
    final selected = _selectedPlan == plan;
    final estBs = SubscriptionState.planBsEstimate(plan, _bcvRate);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() {
          _selectedPlan = plan;
          if (_statusBanner?.tone != _BannerTone.success) {
            _statusBanner = null;
          }
        }),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    plan.displayName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: plan == ProPlanId.annual
                          ? scheme.primaryContainer
                          : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: plan == ProPlanId.annual
                            ? scheme.onPrimaryContainer
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    plan.formattedUsd,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    plan.periodSuffix,
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ],
              ),
              Text(
                estBs > 0
                    ? '≈ Bs ${fmtBs(estBs)} al BCV (${fmtRate(_bcvRate)})'
                    : 'Equivalente en Bs según tasa BCV del día',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 10),
              for (final f in features)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, size: 15, color: scheme.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(f, style: const TextStyle(fontSize: 13)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentBox() {
    final scheme = Theme.of(context).colorScheme;
    final ord = _matchingOrder;
    final pm = _paymentConfig.pagoMovil;
    final usdt = _paymentConfig.usdt;
    final estBs = SubscriptionState.planBsEstimate(_selectedPlan, _bcvRate);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Pagar y activar al instante',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(
                    _autoVerifyEnabled ? Icons.bolt : Icons.edit_note,
                    size: 16,
                  ),
                  label: Text(
                    _autoVerifyEnabled
                        ? 'Pabilo automático'
                        : 'Validación manual',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_loadingConfig) const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ProPaymentMethod.values.map((m) {
                return ChoiceChip(
                  label: Text(m.label),
                  selected: _selectedMethod == m,
                  onSelected: (_) => setState(() {
                    _selectedMethod = m;
                    if (_statusBanner?.tone != _BannerTone.success) {
                      _statusBanner = null;
                    }
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: scheme.primary.withValues(alpha: 0.4),
                ),
              ),
              child: ord != null
                  ? _buildActiveOrderBox(ord)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedPlan.displayName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _selectedMethod == ProPaymentMethod.pagoMovil
                              ? (estBs > 0
                                  ? 'Monto estimado hoy: Bs ${fmtBs(estBs)} (tasa BCV ${fmtRate(_bcvRate)})'
                                  : 'Genera la orden para congelar la tasa BCV exacta.')
                              : 'Monto exacto: \$${_selectedPlan.priceUsd.toStringAsFixed(2)} USDT',
                          style: const TextStyle(fontSize: 13),
                        ),
                        if (_autoVerifyEnabled) ...[
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed:
                                _creatingOrder ? null : () => _createOrder(),
                            icon: _creatingOrder
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.lock_clock_outlined, size: 18),
                            label: Text(
                              _creatingOrder
                                  ? 'Congelando tasa…'
                                  : 'Generar orden con monto exacto (30 min)',
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
            const SizedBox(height: 12),
            if (_selectedMethod == ProPaymentMethod.pagoMovil) ...[
              _buildInfoRow('Banco', pm.bank),
              _buildInfoRow('Cédula / RIF', pm.cedulaRif),
              _buildInfoRow('Teléfono', pm.phone),
              if (pm.holder.trim().isNotEmpty)
                _buildInfoRow('Titular', pm.holder),
            ] else ...[
              _buildInfoRow('Red / Canal', usdt.network),
              _buildInfoRow('Binance Pay ID', usdt.binanceId),
              if (usdt.address.trim().isNotEmpty)
                _buildInfoRow('Dirección USDT', usdt.address),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: _refCtrl,
              keyboardType: _selectedMethod.allowLetters
                  ? TextInputType.text
                  : TextInputType.number,
              decoration: InputDecoration(
                labelText: _selectedMethod == ProPaymentMethod.pagoMovil
                    ? 'Número de referencia bancaria'
                    : 'ID de orden de Binance Pay',
                hintText: _selectedMethod == ProPaymentMethod.pagoMovil
                    ? 'Ej. últimos 6-8 dígitos o referencia completa BDV'
                    : 'Ej. ID de orden de Binance Pay (verificado por Pabilo)',
                prefixIcon: const Icon(Icons.receipt_long_outlined),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _verifying ? null : () => _submitVerifyOrManual(),
                icon: _verifying
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        _autoVerifyEnabled ? Icons.verified_outlined : Icons.send,
                      ),
                label: Text(
                  _verifying
                      ? 'Verificando con Pabilo…'
                      : (_autoVerifyEnabled
                          ? 'Verificar pago y activar Pro'
                          : 'Enviar referencia para validación manual'),
                ),
              ),
            ),
            if (_statusBanner != null) ...[
              const SizedBox(height: 12),
              _buildBannerCard(_statusBanner!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActiveOrderBox(ProCheckoutOrder ord) {
    final isBs = ord.currency == 'BS';
    final remStr = ord.remainingAmount.toStringAsFixed(2);
    final expStr = ord.expiresAt != null
        ? DateFormat('HH:mm', 'es_VE').format(ord.expiresAt!.toLocal())
        : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Orden activa: ${ord.id}${expStr.isNotEmpty ? ' · Expira $expStr' : ''}',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                isBs
                    ? 'Transfiere exacto: Bs ${fmtBs(ord.remainingAmount)}'
                    : 'Envía exacto: \$$remStr USDT',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () => _copy(remStr, 'Monto exacto'),
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copiar'),
            ),
          ],
        ),
        if (ord.paidAmount > 0)
          Text(
            isBs
                ? 'Abonado: Bs ${fmtBs(ord.paidAmount)} · Falta por transferir: Bs ${fmtBs(ord.remainingAmount)}'
                : 'Abonado: \$${ord.paidAmount.toStringAsFixed(2)} · Falta: \$$remStr USDT',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        if (ord.paymentLinkUrl != null && ord.paymentLinkUrl!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              FilledButton.tonalIcon(
                onPressed: () async {
                  final uri = Uri.tryParse(ord.paymentLinkUrl!);
                  if (uri != null) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Pagar con enlace Pabilo'),
              ),
              OutlinedButton.icon(
                onPressed: _verifying ? null : () => _verifyOrderLink(ord),
                icon: const Icon(Icons.verified_outlined, size: 16),
                label: const Text('Ya pagué · Verificar enlace'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _verifyOrderLink(ProCheckoutOrder ord) async {
    if (_verifying) return;
    setState(() {
      _verifying = true;
      _statusBanner = const _PayBanner(
        tone: _BannerTone.info,
        message: 'Consultando el estado real de tu enlace de pago en Pabilo…',
      );
    });
    try {
      final res = await _subService.verifyPayment(
        orderId: ord.id,
        reference: '',
      );
      if (!mounted) return;
      if (res.isActivated) {
        _refCtrl.clear();
        await _subService.saveActiveOrder(null);
        if (!mounted) return;
        setState(() {
          _activeOrder = null;
          _subState = _subService.currentState;
          _statusBanner = const _PayBanner(
            tone: _BannerTone.success,
            message: '¡Pago confirmado mediante enlace Pabilo! Tu plan Pro ya está activo.',
          );
        });
        _showSnack('¡Plan Pro activado al instante!');
      } else {
        setState(() {
          _statusBanner = _PayBanner(
            tone: res.retryable ? _BannerTone.warning : _BannerTone.error,
            message: res.message.isNotEmpty
                ? res.message
                : 'El enlace aún aparece pendiente. Si ya transferiste, pega tu referencia abajo.',
          );
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusBanner = _PayBanner(
          tone: _BannerTone.warning,
          message: e.toString(),
        );
      });
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Widget _buildInfoRow(String label, String value) {
    final empty = value.trim().isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ),
          Expanded(
            child: Text(
              empty ? 'Por configurar (config/proPayments)' : value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: empty ? FontWeight.normal : FontWeight.w600,
                fontStyle: empty ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ),
          if (!empty)
            IconButton(
              icon: const Icon(Icons.copy, size: 16),
              tooltip: 'Copiar $label',
              onPressed: () => _copy(value, label),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }

  Widget _buildBannerCard(_PayBanner banner) {
    final Color bg;
    switch (banner.tone) {
      case _BannerTone.success:
        bg = Colors.green.withValues(alpha: 0.16);
      case _BannerTone.warning:
        bg = Colors.amber.withValues(alpha: 0.16);
      case _BannerTone.error:
        bg = Colors.red.withValues(alpha: 0.15);
      case _BannerTone.info:
        bg = Colors.blue.withValues(alpha: 0.14);
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(banner.message, style: const TextStyle(fontSize: 13)),
          if (banner.copyAmountText != null) ...[
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: () =>
                  _copy(banner.copyAmountText!, 'Diferencia exacta'),
              icon: const Icon(Icons.copy, size: 16),
              label: Text('Copiar diferencia (${banner.copyAmountText})'),
            ),
          ],
          if (banner.showManualFallbackAction) ...[
            const SizedBox(height: 6),
            OutlinedButton(
              onPressed: _verifying
                  ? null
                  : () => _submitVerifyOrManual(forceManual: true),
              child: const Text('Enviar para validación manual'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAdminEntryCard() {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.primary.withValues(alpha: 0.5)),
      ),
      child: ListTile(
        leading: Icon(Icons.admin_panel_settings, color: scheme.primary),
        title: const Text(
          'Panel Administrador Pro',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: const Text(
          'Activar, regalar o desactivar Pro en otras cuentas por correo.',
          style: TextStyle(fontSize: 12),
        ),
        trailing: FilledButton(
          onPressed: _openAdminSheet,
          child: const Text('Abrir'),
        ),
      ),
    );
  }

  Future<void> _openAdminSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ProAdminSheet(subService: _subService),
    );
    if (mounted) {
      await _subService.refreshSubscription();
    }
  }
}

class _ProAdminSheet extends StatefulWidget {
  final SubscriptionService subService;

  const _ProAdminSheet({required this.subService});

  @override
  State<_ProAdminSheet> createState() => _ProAdminSheetState();
}

class _ProAdminSheetState extends State<_ProAdminSheet> {
  final _emailCtrl = TextEditingController();
  final _daysCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  ProPlanId _plan = ProPlanId.monthly;
  bool _loading = true;
  bool _busy = false;
  String? _statusMsg;
  bool _statusIsError = false;
  AdminUserSummary? _lookupUser;
  AdminOverviewResult? _overview;

  @override
  void initState() {
    super.initState();
    _loadOverview();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _daysCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadOverview() async {
    setState(() => _loading = true);
    try {
      final res = await widget.subService.fetchAdminOverview();
      if (!mounted) return;
      setState(() {
        _overview = res;
        _statusIsError = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMsg = e.toString();
        _statusIsError = true;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _lookup() async {
    final email = _emailCtrl.text.trim();
    if (!email.contains('@')) {
      setState(() {
        _statusMsg = 'Ingresa un correo válido.';
        _statusIsError = true;
      });
      return;
    }
    setState(() => _busy = true);
    try {
      final found = await widget.subService.adminLookupByEmail(email);
      if (!mounted) return;
      setState(() {
        _lookupUser = found;
        _statusMsg = 'Cuenta encontrada: ${found.email}';
        _statusIsError = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _lookupUser = null;
        _statusMsg = e.toString();
        _statusIsError = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _activate({
    String? uid,
    String? email,
    ProPlanId? plan,
    int? days,
    String? note,
  }) async {
    final targetEmail = (email ?? _emailCtrl.text).trim();
    if ((uid == null || uid.isEmpty) && targetEmail.isEmpty) {
      setState(() {
        _statusMsg = 'Escribe el correo de la cuenta primero.';
        _statusIsError = true;
      });
      return;
    }
    setState(() => _busy = true);
    try {
      final parsedDays = int.tryParse(_daysCtrl.text.trim());
      final out = await widget.subService.adminActivatePro(
        uid: uid,
        email: targetEmail.isNotEmpty ? targetEmail : null,
        plan: plan ?? _plan,
        days: days ?? parsedDays,
        note: note ??
            (_noteCtrl.text.trim().isNotEmpty
                ? _noteCtrl.text.trim()
                : 'Activado desde app'),
      );
      if (!mounted) return;
      setState(() {
        _lookupUser = out.user;
        _statusMsg = out.message;
        _statusIsError = false;
      });
      await _loadOverview();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMsg = e.toString();
        _statusIsError = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deactivate({String? uid, String? email}) async {
    final targetEmail = (email ?? _emailCtrl.text).trim();
    if ((uid == null || uid.isEmpty) && targetEmail.isEmpty) {
      setState(() {
        _statusMsg = 'Escribe el correo de la cuenta a desactivar.';
        _statusIsError = true;
      });
      return;
    }
    setState(() => _busy = true);
    try {
      final out = await widget.subService.adminDeactivatePro(
        uid: uid,
        email: targetEmail.isNotEmpty ? targetEmail : null,
        note: _noteCtrl.text.trim().isNotEmpty
            ? _noteCtrl.text.trim()
            : 'Desactivado desde app',
      );
      if (!mounted) return;
      setState(() {
        _lookupUser = out.user;
        _statusMsg = out.message;
        _statusIsError = false;
      });
      await _loadOverview();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMsg = e.toString();
        _statusIsError = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ov = _overview;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      builder: (_, ctrl) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: ListView(
          controller: ctrl,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Panel Administrador Pro',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  tooltip: 'Actualizar',
                  onPressed: _busy ? null : _loadOverview,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (ov != null)
              Text(
                '${ov.totalUsers} cuentas · ${ov.activePro} Pro activas · ${ov.pendingManual} pendientes',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Correo de usuario',
                hintText: 'cliente@gmail.com',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: 'Buscar',
                  onPressed: _busy ? null : _lookup,
                  icon: const Icon(Icons.search),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<ProPlanId>(
                    initialValue: _plan,
                    decoration: const InputDecoration(
                      labelText: 'Plan / regalo',
                      border: OutlineInputBorder(),
                    ),
                    items: ProPlanId.values
                        .map(
                          (p) => DropdownMenuItem(
                            value: p,
                            child: Text('${p.shortName} (${p.formattedUsd})'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _plan = v);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 115,
                  child: TextField(
                    controller: _daysCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Días (opc)',
                      hintText: 'Ej. 30',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _noteCtrl,
              decoration: const InputDecoration(
                labelText: 'Nota (opcional)',
                hintText: 'Regalo 1 mes / Pago verificado',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : () => _activate(),
                    child: const Text('Activar / Regalar Pro'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _busy ? null : () => _deactivate(),
                  child: const Text('Desactivar'),
                ),
              ],
            ),
            if (_statusMsg != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (_statusIsError ? Colors.red : scheme.primary)
                      .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_statusMsg!, style: const TextStyle(fontSize: 13)),
              ),
            ],
            if (_lookupUser != null) ...[
              const SizedBox(height: 12),
              _buildAdminUserCard(_lookupUser!),
            ],
            const SizedBox(height: 16),
            const Text(
              'Cuentas recientes',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (ov == null || ov.users.isEmpty)
              const Text('No hay cuentas cargadas.',
                  style: TextStyle(color: Colors.grey))
            else
              for (final u in ov.users.take(40)) _buildAdminUserCard(u),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminUserCard(AdminUserSummary u) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    u.email.isNotEmpty ? u.email : u.uid,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: (u.isPro ? Colors.green : Colors.grey)
                        .withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    u.isPro
                        ? 'PRO ${(ProPlanId.tryParse(u.plan)?.shortName ?? '').toUpperCase()} · ${u.daysLeft}d'
                        : 'GRATIS',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            if (u.pending != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '⏳ Pago pendiente Ref: ${u.pending!['reference'] ?? u.pending!['method']}',
                  style: const TextStyle(fontSize: 12, color: Colors.orange),
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                ActionChip(
                  label: const Text('Regalar 1 mes'),
                  onPressed: _busy
                      ? null
                      : () => _activate(
                            uid: u.uid,
                            email: u.email,
                            plan: ProPlanId.monthly,
                            days: 30,
                            note: 'Regalo 1 mes',
                          ),
                ),
                ActionChip(
                  label: const Text('Activar 1 año'),
                  onPressed: _busy
                      ? null
                      : () => _activate(
                            uid: u.uid,
                            email: u.email,
                            plan: ProPlanId.annual,
                            days: 365,
                            note: 'Activado 1 año',
                          ),
                ),
                if (u.isPro)
                  ActionChip(
                    label: const Text('Desactivar'),
                    onPressed: _busy
                        ? null
                        : () => _deactivate(uid: u.uid, email: u.email),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _BannerTone { success, warning, error, info }

class _PayBanner {
  final _BannerTone tone;
  final String message;
  final String? copyAmountText;
  final bool showManualFallbackAction;

  const _PayBanner({
    required this.tone,
    required this.message,
    this.copyAmountText,
    this.showManualFallbackAction = false,
  });
}

