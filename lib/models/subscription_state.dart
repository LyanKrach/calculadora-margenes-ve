/// Correos propietarios con acceso al Panel Administrador Pro.
const List<String> proAdminEmails = [
  'layankrach@gmail.com',
  'soporterefillstore@gmail.com',
];

bool isAdminOwnerEmail(String? email) {
  final clean = (email ?? '').trim().toLowerCase();
  return clean.isNotEmpty && proAdminEmails.contains(clean);
}

/// Planes y modelos compartidos para suscripciones Pro y verificación Pabilo.
enum ProPlanId {
  monthly,
  quarterly,
  semiannual,
  annual;

  String get id => name;

  String get displayName => switch (this) {
        ProPlanId.monthly => 'Pro Mensual',
        ProPlanId.quarterly => 'Pro Trimestral',
        ProPlanId.semiannual => 'Pro 6 Meses',
        ProPlanId.annual => 'Pro Anual',
      };

  String get shortName => switch (this) {
        ProPlanId.monthly => 'Mensual',
        ProPlanId.quarterly => 'Trimestral',
        ProPlanId.semiannual => '6 Meses',
        ProPlanId.annual => 'Anual',
      };

  double get priceUsd => switch (this) {
        ProPlanId.monthly => 1.99,
        ProPlanId.quarterly => 4.99,
        ProPlanId.semiannual => 7.99,
        ProPlanId.annual => 14.99,
      };

  String get formattedUsd => switch (this) {
        ProPlanId.monthly => '\$1,99',
        ProPlanId.quarterly => '\$4,99',
        ProPlanId.semiannual => '\$7,99',
        ProPlanId.annual => '\$14,99',
      };

  String get periodSuffix => switch (this) {
        ProPlanId.monthly => '/ mes USDT',
        ProPlanId.quarterly => '/ 3 meses USDT',
        ProPlanId.semiannual => '/ 6 meses USDT',
        ProPlanId.annual => '/ año USDT',
      };

  int get durationDays => switch (this) {
        ProPlanId.monthly => 30,
        ProPlanId.quarterly => 90,
        ProPlanId.semiannual => 180,
        ProPlanId.annual => 365,
      };

  int get savePercent => switch (this) {
        ProPlanId.monthly => 0,
        ProPlanId.quarterly => 16,
        ProPlanId.semiannual => 33,
        ProPlanId.annual => 37,
      };

  int get tierRank => switch (this) {
        ProPlanId.monthly => 1,
        ProPlanId.quarterly => 2,
        ProPlanId.semiannual => 3,
        ProPlanId.annual => 4,
      };

  static ProPlanId? tryParse(String? raw) {
    return switch (raw?.trim()) {
      'monthly' => ProPlanId.monthly,
      'quarterly' => ProPlanId.quarterly,
      'semiannual' => ProPlanId.semiannual,
      'annual' => ProPlanId.annual,
      _ => null,
    };
  }
}

enum ProPaymentMethod {
  pagoMovil,
  usdt;

  String get id => this == ProPaymentMethod.usdt ? 'usdt' : 'pago_movil';

  String get label =>
      this == ProPaymentMethod.usdt ? 'Binance Pay (USDT)' : 'Pago Móvil (BDV)';

  String get currency => this == ProPaymentMethod.usdt ? 'USD' : 'BS';

  bool get allowLetters => this == ProPaymentMethod.usdt;

  int get minRefLength => this == ProPaymentMethod.usdt ? 6 : 4;

  static ProPaymentMethod fromId(String? raw) {
    return raw == 'usdt'
        ? ProPaymentMethod.usdt
        : ProPaymentMethod.pagoMovil;
  }
}

enum SubscriptionStatus {
  free,
  active,
  expired,
  canceled,
}

class PlanUpgradeInfo {
  final bool isActive;
  final ProPlanId? activePlan;
  final bool isCurrentPlan;
  final bool isLowerPlan;
  final bool isUpgrade;
  final bool canPurchase;
  final int remainingDays;
  final int addedDays;
  final int totalDaysAfter;
  final DateTime projectedEndDate;

  const PlanUpgradeInfo({
    required this.isActive,
    required this.activePlan,
    required this.isCurrentPlan,
    required this.isLowerPlan,
    required this.isUpgrade,
    required this.canPurchase,
    required this.remainingDays,
    required this.addedDays,
    required this.totalDaysAfter,
    required this.projectedEndDate,
  });
}

double _round2(double v) => (v * 100).roundToDouble() / 100;

DateTime? _parseIso(dynamic raw) {
  if (raw == null) return null;
  final s = raw.toString().trim();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}

double? _toDouble(dynamic raw) {
  if (raw == null) return null;
  if (raw is num) return raw.isFinite ? raw.toDouble() : null;
  final parsed = double.tryParse(raw.toString().trim().replaceAll(',', '.'));
  return (parsed != null && parsed.isFinite) ? parsed : null;
}

class SubscriptionState {
  static const int freeMaxProducts = 10;

  final SubscriptionStatus status;
  final String? plan;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? provider;
  final String? paymentRef;
  final String? orderId;
  final int daysLeft;

  const SubscriptionState({
    required this.status,
    this.plan,
    this.startDate,
    this.endDate,
    this.provider,
    this.paymentRef,
    this.orderId,
    required this.daysLeft,
  });

  const SubscriptionState.free()
      : status = SubscriptionStatus.free,
        plan = null,
        startDate = null,
        endDate = null,
        provider = null,
        paymentRef = null,
        orderId = null,
        daysLeft = 0;

  bool get isPro => status == SubscriptionStatus.active;

  ProPlanId? get parsedPlan => ProPlanId.tryParse(plan);

  PlanUpgradeInfo upgradeInfoFor(ProPlanId targetPlan, {DateTime? now}) {
    final ref = (now ?? DateTime.now()).toUtc();
    final active = parsedPlan;
    final addedDays = targetPlan.durationDays;
    final currentEnd = endDate?.toUtc();
    final isCurrentlyActive =
        isPro && active != null && currentEnd != null && currentEnd.isAfter(ref);

    if (!isCurrentlyActive) {
      return PlanUpgradeInfo(
        isActive: false,
        activePlan: active,
        isCurrentPlan: false,
        isLowerPlan: false,
        isUpgrade: false,
        canPurchase: true,
        remainingDays: 0,
        addedDays: addedDays,
        totalDaysAfter: addedDays,
        projectedEndDate: ref.add(Duration(days: addedDays)),
      );
    }

    final remainingMs = currentEnd.difference(ref).inMilliseconds;
    final remainingDays = remainingMs > 0 ? (remainingMs / 86400000).ceil() : 0;
    final curRank = active.tierRank;
    final tgtRank = targetPlan.tierRank;
    final isCurrent = tgtRank == curRank;
    final isLower = tgtRank < curRank;
    final isUpgrade = tgtRank > curRank;
    final projectedEnd = currentEnd.add(Duration(days: addedDays));

    return PlanUpgradeInfo(
      isActive: true,
      activePlan: active,
      isCurrentPlan: isCurrent,
      isLowerPlan: isLower,
      isUpgrade: isUpgrade,
      canPurchase: isUpgrade,
      remainingDays: remainingDays,
      addedDays: addedDays,
      totalDaysAfter: remainingDays + addedDays,
      projectedEndDate: projectedEnd,
    );
  }

  ProPlanId? firstAvailableUpgradePlan({DateTime? now}) {
    if (!isPro) return ProPlanId.annual;
    for (final pid in ProPlanId.values) {
      if (upgradeInfoFor(pid, now: now).canPurchase) {
        return pid;
      }
    }
    return null;
  }

  static bool canAddProduct({
    required int currentCount,
    required bool isPro,
  }) =>
      isPro || currentCount < freeMaxProducts;

  static double planBsEstimate(ProPlanId plan, double bcvRate) {
    if (!bcvRate.isFinite || bcvRate <= 0) return 0;
    return _round2(plan.priceUsd * bcvRate);
  }

  factory SubscriptionState.fromJson(
    Map<String, dynamic>? json, {
    DateTime? now,
  }) {
    if (json == null || json.isEmpty) return const SubscriptionState.free();
    final refNow = (now ?? DateTime.now()).toUtc();
    final rawStatus = json['status']?.toString().trim().toLowerCase() ?? '';
    final plan = json['plan']?.toString().trim();
    final startDate = _parseIso(json['startDate']);
    final endDate = _parseIso(json['endDate']);
    final provider = json['provider']?.toString();
    final paymentRef = json['paymentRef']?.toString();
    final orderId = json['orderId']?.toString();

    if (rawStatus == 'active' && endDate != null) {
      final diffMs = endDate.toUtc().millisecondsSinceEpoch -
          refNow.millisecondsSinceEpoch;
      if (diffMs > 0) {
        final daysLeft = (diffMs / 86400000).ceil().clamp(1, 36500);
        return SubscriptionState(
          status: SubscriptionStatus.active,
          plan: plan,
          startDate: startDate,
          endDate: endDate,
          provider: provider,
          paymentRef: paymentRef,
          orderId: orderId,
          daysLeft: daysLeft,
        );
      }
      return SubscriptionState(
        status: SubscriptionStatus.expired,
        plan: plan,
        startDate: startDate,
        endDate: endDate,
        provider: provider,
        paymentRef: paymentRef,
        orderId: orderId,
        daysLeft: 0,
      );
    }

    if (rawStatus == 'canceled') {
      return SubscriptionState(
        status: SubscriptionStatus.canceled,
        plan: plan,
        startDate: startDate,
        endDate: endDate,
        provider: provider,
        paymentRef: paymentRef,
        orderId: orderId,
        daysLeft: 0,
      );
    }

    if (rawStatus == 'expired' || endDate != null) {
      return SubscriptionState(
        status: SubscriptionStatus.expired,
        plan: plan,
        startDate: startDate,
        endDate: endDate,
        provider: provider,
        paymentRef: paymentRef,
        orderId: orderId,
        daysLeft: 0,
      );
    }

    return const SubscriptionState.free();
  }

  /// Recalcula si la suscripción venció en el instante actual.
  SubscriptionState evaluateAt(DateTime now) {
    if (status != SubscriptionStatus.active || endDate == null) return this;
    final diffMs = endDate!.toUtc().millisecondsSinceEpoch -
        now.toUtc().millisecondsSinceEpoch;
    if (diffMs <= 0) {
      return SubscriptionState(
        status: SubscriptionStatus.expired,
        plan: plan,
        startDate: startDate,
        endDate: endDate,
        provider: provider,
        paymentRef: paymentRef,
        orderId: orderId,
        daysLeft: 0,
      );
    }
    return SubscriptionState(
      status: SubscriptionStatus.active,
      plan: plan,
      startDate: startDate,
      endDate: endDate,
      provider: provider,
      paymentRef: paymentRef,
      orderId: orderId,
      daysLeft: (diffMs / 86400000).ceil().clamp(1, 36500),
    );
  }

  Map<String, dynamic> toJson() => {
        'v': 1,
        'status': status.name,
        if (plan != null) 'plan': plan,
        if (startDate != null) 'startDate': startDate!.toUtc().toIso8601String(),
        if (endDate != null) 'endDate': endDate!.toUtc().toIso8601String(),
        if (provider != null) 'provider': provider,
        if (paymentRef != null) 'paymentRef': paymentRef,
        if (orderId != null) 'orderId': orderId,
      };
}

class PagoMovilPublicInfo {
  final String bank;
  final String cedulaRif;
  final String phone;
  final String holder;
  final bool autoVerify;

  const PagoMovilPublicInfo({
    this.bank = 'Banco de Venezuela (BDV · 0102)',
    this.cedulaRif = '31955598',
    this.phone = '04220336568',
    this.holder = '',
    this.autoVerify = true,
  });

  factory PagoMovilPublicInfo.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const PagoMovilPublicInfo();
    final bank = (json['bank'] ?? json['banco'] ?? '').toString().trim();
    final ced = (json['cedulaRif'] ?? '').toString().trim();
    final phone = (json['phone'] ?? json['telefono'] ?? '').toString().trim();
    return PagoMovilPublicInfo(
      bank: bank.isNotEmpty ? bank : 'Banco de Venezuela (BDV · 0102)',
      cedulaRif: ced.isNotEmpty ? ced : '31955598',
      phone: phone.isNotEmpty ? phone : '04220336568',
      holder: (json['holder'] ?? json['titular'] ?? '').toString().trim(),
      autoVerify: json['autoVerify'] is bool ? json['autoVerify'] as bool : true,
    );
  }
}

class UsdtPublicInfo {
  final String network;
  final String binanceId;
  final String address;
  final bool autoVerify;

  const UsdtPublicInfo({
    this.network = 'Binance Pay (USDT)',
    this.binanceId = '916942742',
    this.address = '',
    this.autoVerify = true,
  });

  factory UsdtPublicInfo.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const UsdtPublicInfo();
    final net = (json['network'] ?? json['red'] ?? '').toString().trim();
    final binId = (json['binanceId'] ?? '').toString().trim();
    return UsdtPublicInfo(
      network: net.isNotEmpty ? net : 'Binance Pay (USDT)',
      binanceId: binId.isNotEmpty ? binId : '916942742',
      address: (json['address'] ?? json['direccion'] ?? '').toString().trim(),
      autoVerify:
          json['autoVerify'] is bool ? json['autoVerify'] as bool : true,
    );
  }
}

class ProPaymentConfig {
  static const String defaultSupportEmail = 'soporterefillstore@gmail.com';
  static const String defaultSupportWhatsapp = '+584161740312';

  final double? bcvUsd;
  final String? rateEffectiveDate;
  final String? rateSource;
  final PagoMovilPublicInfo pagoMovil;
  final UsdtPublicInfo usdt;
  final String supportEmail;
  final String supportWhatsapp;

  const ProPaymentConfig({
    this.bcvUsd,
    this.rateEffectiveDate,
    this.rateSource,
    this.pagoMovil = const PagoMovilPublicInfo(),
    this.usdt = const UsdtPublicInfo(),
    this.supportEmail = defaultSupportEmail,
    this.supportWhatsapp = defaultSupportWhatsapp,
  });

  factory ProPaymentConfig.fromJson(Map<String, dynamic> json) {
    final bcvMap = json['bcvRate'] as Map<String, dynamic>?;
    final methods = json['methods'] as Map<String, dynamic>?;
    final sup = json['support'] as Map<String, dynamic>?;
    final email = (sup?['email'] ?? '').toString().trim();
    final whatsapp = (sup?['whatsapp'] ?? '').toString().trim();
    return ProPaymentConfig(
      bcvUsd: bcvMap != null ? _toDouble(bcvMap['usd']) : null,
      rateEffectiveDate: bcvMap?['effectiveDate']?.toString(),
      rateSource: bcvMap?['source']?.toString(),
      pagoMovil: PagoMovilPublicInfo.fromJson(
        methods?['pago_movil'] as Map<String, dynamic>?,
      ),
      usdt: UsdtPublicInfo.fromJson(
        methods?['usdt'] as Map<String, dynamic>?,
      ),
      supportEmail: email.isNotEmpty ? email : defaultSupportEmail,
      supportWhatsapp: whatsapp.isNotEmpty ? whatsapp : defaultSupportWhatsapp,
    );
  }
}

class ProCheckoutOrder {
  final String id;
  final ProPlanId plan;
  final ProPaymentMethod method;
  final String currency;
  final double expectedAmountUsd;
  final double expectedAmountBs;
  final double expectedTotal;
  final double paidAmount;
  final double remainingAmount;
  final double rateBs;
  final String rateSource;
  final String? rateEffectiveDate;
  final bool autoVerify;
  final DateTime? expiresAt;
  final String status;
  final String? paymentLinkId;
  final String? paymentLinkUrl;

  const ProCheckoutOrder({
    required this.id,
    required this.plan,
    required this.method,
    required this.currency,
    required this.expectedAmountUsd,
    required this.expectedAmountBs,
    required this.expectedTotal,
    required this.paidAmount,
    required this.remainingAmount,
    required this.rateBs,
    required this.rateSource,
    this.rateEffectiveDate,
    required this.autoVerify,
    this.expiresAt,
    required this.status,
    this.paymentLinkId,
    this.paymentLinkUrl,
  });

  bool get isExpired {
    if (paidAmount > 0 || expiresAt == null) return false;
    return expiresAt!.isBefore(DateTime.now());
  }

  ProCheckoutOrder withPartialUpdate({
    required double paidAmount,
    required double remainingAmount,
    DateTime? expiresAt,
  }) =>
      ProCheckoutOrder(
        id: id,
        plan: plan,
        method: method,
        currency: currency,
        expectedAmountUsd: expectedAmountUsd,
        expectedAmountBs: expectedAmountBs,
        expectedTotal: expectedTotal,
        paidAmount: paidAmount,
        remainingAmount: remainingAmount,
        rateBs: rateBs,
        rateSource: rateSource,
        rateEffectiveDate: rateEffectiveDate,
        autoVerify: autoVerify,
        expiresAt: expiresAt ?? this.expiresAt,
        status: status,
        paymentLinkId: paymentLinkId,
        paymentLinkUrl: paymentLinkUrl,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'plan': plan.id,
        'method': method.id,
        'currency': currency,
        'expectedAmountUsd': expectedAmountUsd,
        'expectedAmountBs': expectedAmountBs,
        'expectedTotal': expectedTotal,
        'paidAmount': paidAmount,
        'remainingAmount': remainingAmount,
        'rateBs': rateBs,
        'rateSource': rateSource,
        if (rateEffectiveDate != null) 'rateEffectiveDate': rateEffectiveDate,
        'autoVerify': autoVerify,
        if (expiresAt != null) 'expiresAt': expiresAt!.toUtc().toIso8601String(),
        'status': status,
        if (paymentLinkId != null) 'paymentLinkId': paymentLinkId,
        if (paymentLinkUrl != null) 'paymentLinkUrl': paymentLinkUrl,
      };

  factory ProCheckoutOrder.fromJson(Map<String, dynamic> json) {
    return ProCheckoutOrder(
      id: json['id']?.toString() ?? '',
      plan: ProPlanId.tryParse(json['plan']?.toString()) ?? ProPlanId.monthly,
      method: ProPaymentMethod.fromId(json['method']?.toString()),
      currency: json['currency']?.toString() ?? 'BS',
      expectedAmountUsd: _toDouble(json['expectedAmountUsd']) ?? 0,
      expectedAmountBs: _toDouble(json['expectedAmountBs']) ?? 0,
      expectedTotal: _toDouble(json['expectedTotal']) ?? 0,
      paidAmount: _toDouble(json['paidAmount']) ?? 0,
      remainingAmount: _toDouble(json['remainingAmount']) ?? 0,
      rateBs: _toDouble(json['rateBs']) ?? 0,
      rateSource: json['rateSource']?.toString() ?? '',
      rateEffectiveDate: json['rateEffectiveDate']?.toString(),
      autoVerify: json['autoVerify'] == true,
      expiresAt: _parseIso(json['expiresAt']),
      status: json['status']?.toString() ?? 'awaiting_payment',
      paymentLinkId: json['paymentLinkId']?.toString(),
      paymentLinkUrl: json['paymentLinkUrl']?.toString(),
    );
  }
}

class PabiloVerifyResult {
  final bool ok;
  final String code;
  final bool retryable;
  final bool fallbackManual;
  final String orderId;
  final String message;
  final double? paidAmount;
  final double? remainingAmount;
  final double? reportedAmount;
  final DateTime? expiresAt;
  final SubscriptionState? subscription;

  const PabiloVerifyResult({
    required this.ok,
    required this.code,
    required this.retryable,
    required this.fallbackManual,
    required this.orderId,
    required this.message,
    this.paidAmount,
    this.remainingAmount,
    this.reportedAmount,
    this.expiresAt,
    this.subscription,
  });

  bool get isActivated =>
      ok && (code == 'ACTIVATED' || code == 'ALREADY_ACTIVATED');

  bool get isPartial => code == 'PARTIAL_PAYMENT';

  factory PabiloVerifyResult.fromJson(
    Map<String, dynamic> json, {
    String fallbackOrderId = '',
  }) {
    final subMap = json['subscription'] as Map<String, dynamic>?;
    return PabiloVerifyResult(
      ok: json['ok'] == true,
      code: json['code']?.toString() ?? '',
      retryable: json['retryable'] == true,
      fallbackManual: json['fallbackManual'] == true,
      orderId: json['orderId']?.toString() ?? fallbackOrderId,
      message: json['message']?.toString() ?? '',
      paidAmount: _toDouble(json['paidAmount']),
      remainingAmount: _toDouble(json['remainingAmount']),
      reportedAmount: _toDouble(json['reportedAmount']),
      expiresAt: _parseIso(json['expiresAt']),
      subscription:
          subMap != null ? SubscriptionState.fromJson(subMap) : null,
    );
  }
}

class AdminUserSummary {
  final String uid;
  final String email;
  final String displayName;
  final bool isOwner;
  final bool isPro;
  final String status;
  final String? plan;
  final int daysLeft;
  final DateTime? endDate;
  final String? note;
  final Map<String, dynamic>? pending;

  const AdminUserSummary({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.isOwner,
    required this.isPro,
    required this.status,
    this.plan,
    required this.daysLeft,
    this.endDate,
    this.note,
    this.pending,
  });

  factory AdminUserSummary.fromJson(Map<String, dynamic> json) {
    final pend = json['pending'];
    return AdminUserSummary(
      uid: json['uid']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? '',
      isOwner: json['isOwner'] == true,
      isPro: json['isPro'] == true,
      status: json['status']?.toString() ?? 'free',
      plan: json['plan']?.toString(),
      daysLeft: (json['daysLeft'] as num?)?.toInt() ?? 0,
      endDate: _parseIso(json['endDate']),
      note: json['note']?.toString(),
      pending: pend is Map<String, dynamic> ? pend : null,
    );
  }
}

class AdminOverviewResult {
  final int totalUsers;
  final int activePro;
  final int pendingManual;
  final List<AdminUserSummary> users;

  const AdminOverviewResult({
    required this.totalUsers,
    required this.activePro,
    required this.pendingManual,
    required this.users,
  });

  factory AdminOverviewResult.fromJson(Map<String, dynamic> json) {
    final stats = json['stats'] as Map<String, dynamic>? ?? const {};
    final rawUsers = json['users'] as List<dynamic>? ?? const [];
    return AdminOverviewResult(
      totalUsers: (stats['totalUsers'] as num?)?.toInt() ?? rawUsers.length,
      activePro: (stats['activePro'] as num?)?.toInt() ?? 0,
      pendingManual: (stats['pendingManual'] as num?)?.toInt() ?? 0,
      users: rawUsers
          .whereType<Map<String, dynamic>>()
          .map(AdminUserSummary.fromJson)
          .toList(),
    );
  }
}

