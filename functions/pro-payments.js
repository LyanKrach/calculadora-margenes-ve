'use strict';

const crypto = require('crypto');
const {
  verifyPayment,
  getExchangeRate,
  normalizeReference,
  getCaracasDateString,
  createPaymentLink,
  getPaymentLinkInfo,
  verifyWebhookSignature,
} = require('./pabilo');

const PRO_PLANS = Object.freeze({
  monthly: Object.freeze({
    id: 'monthly',
    name: 'Pro Mensual',
    priceUsd: 1.99,
    durationDays: 30,
    savePercent: 0,
    recommended: false,
  }),
  quarterly: Object.freeze({
    id: 'quarterly',
    name: 'Pro Trimestral',
    priceUsd: 4.99,
    durationDays: 90,
    savePercent: 16,
    recommended: false,
  }),
  semiannual: Object.freeze({
    id: 'semiannual',
    name: 'Pro 6 Meses',
    priceUsd: 7.99,
    durationDays: 180,
    savePercent: 33,
    recommended: false,
  }),
  annual: Object.freeze({
    id: 'annual',
    name: 'Pro Anual',
    priceUsd: 14.99,
    durationDays: 365,
    savePercent: 37,
    recommended: true,
  }),
});

const PAYMENT_METHODS = Object.freeze({
  pago_movil: Object.freeze({
    id: 'pago_movil',
    label: 'Pago Móvil (BDV)',
    currency: 'BS',
    allowLetters: false,
    minRefLength: 4,
    maxRefLength: 20,
    providerId: 'pabilo_bdv',
  }),
  usdt: Object.freeze({
    id: 'usdt',
    label: 'Binance Pay (USDT)',
    currency: 'USD',
    allowLetters: true,
    minRefLength: 6,
    maxRefLength: 64,
    providerId: 'pabilo_binance',
  }),
});

const ORDER_TTL_MS = 30 * 60 * 1000;
const MAX_VERIFY_ATTEMPTS = 5;
const OVERPAY_ALERT_PERCENT = 10;

class ProPaymentError extends Error {
  constructor(status, code, message, extra = {}) {
    super(message);
    this.name = 'ProPaymentError';
    this.status = status;
    this.code = code;
    this.extra = extra;
  }
}

function round(value, decimals = 2) {
  const num = Number(value);
  if (!Number.isFinite(num)) return 0;
  const factor = Math.pow(10, decimals);
  return Math.round((num + Number.EPSILON) * factor) / factor;
}

/**
 * Comparación entera a céntimos (cero tolerancia por debajo del monto esperado).
 */
function checkAmount(expected, received, alertOverPercent = OVERPAY_ALERT_PERCENT) {
  const expectedScaled = Math.round(Number(expected) * 100);
  const receivedScaled = Math.round(Number(received) * 100);
  const diffScaled = receivedScaled - expectedScaled;
  const shortfall = diffScaled < 0 ? round(-diffScaled / 100, 2) : 0;
  const overpaid = diffScaled > 0 ? round(diffScaled / 100, 2) : 0;
  const overpaidAlert =
    expectedScaled > 0 && diffScaled / expectedScaled > alertOverPercent / 100;

  return {
    ok: shortfall === 0,
    expected: round(expected, 2),
    received: round(received, 2),
    shortfall,
    overpaid,
    overpaidAlert,
  };
}

function computeSubscriptionDates({ existingSub, durationDays, nowMs = Date.now() }) {
  const nowDate = new Date(nowMs);
  const nowIso = nowDate.toISOString();
  let baseEndDate = nowDate;
  let startDate = nowIso;

  if (existingSub && existingSub.status === 'active' && existingSub.endDate) {
    const parsedEnd = new Date(existingSub.endDate);
    if (!Number.isNaN(parsedEnd.getTime()) && parsedEnd.getTime() > nowMs) {
      baseEndDate = parsedEnd;
      if (existingSub.startDate) {
        const parsedStart = new Date(existingSub.startDate);
        if (!Number.isNaN(parsedStart.getTime())) {
          startDate = parsedStart.toISOString();
        }
      }
    }
  }

  const endDate = new Date(baseEndDate.getTime() + durationDays * 86_400_000).toISOString();
  return { startDate, endDate, nowIso };
}

function makeReferenceLockKey(methodId, normalizedRef) {
  const prefix = methodId === 'usdt' ? 'bp_' : 'pm_';
  return `${prefix}${normalizedRef}`;
}

async function fetchJsonWithTimeout(url, fetchImpl, timeoutMs = 6000) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetchImpl(url, { signal: controller.signal });
    if (!res.ok) return null;
    return await res.json();
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Obtiene la tasa BCV oficial vigente desde las mismas fuentes confiables
 * de Calculadora de Márgenes VE, con respaldo de Pabilo si las CDN fallan.
 */
async function resolveAuthoritativeBcvRate({
  fetchImpl = globalThis.fetch,
  pabiloConfig = {},
} = {}) {
  const vzla = await fetchJsonWithTimeout('https://rates.dolarvzla.com/bcv/current.json', fetchImpl);
  if (vzla && vzla.current && Number(vzla.current.usd) > 0) {
    return {
      usd: round(Number(vzla.current.usd), 4),
      eur: Number(vzla.current.eur) > 0 ? round(Number(vzla.current.eur), 4) : null,
      effectiveDate: vzla.current.date ? String(vzla.current.date) : null,
      source: 'dolarvzla',
    };
  }

  const bcvToday = await fetchJsonWithTimeout('https://bcv.today/api/v1/rate.json', fetchImpl);
  if (bcvToday && Number(bcvToday.USD) > 0) {
    return {
      usd: round(Number(bcvToday.USD), 4),
      eur: Number(bcvToday.EUR) > 0 ? round(Number(bcvToday.EUR), 4) : null,
      effectiveDate: String(bcvToday.effective_date || bcvToday.date || '') || null,
      source: 'bcv.today',
    };
  }

  const dolarApi = await fetchJsonWithTimeout('https://ve.dolarapi.com/v1/dolares/oficial', fetchImpl);
  if (dolarApi && Number(dolarApi.promedio) > 0) {
    return {
      usd: round(Number(dolarApi.promedio), 4),
      eur: null,
      effectiveDate: dolarApi.fechaActualizacion ? String(dolarApi.fechaActualizacion) : null,
      source: 'dolarapi',
    };
  }

  if (pabiloConfig.apiKey) {
    const pabiloRate = await getExchangeRate({
      baseUrl: pabiloConfig.baseUrl,
      apiKey: pabiloConfig.apiKey,
      fetchImpl,
    });
    if (pabiloRate && pabiloRate.usd > 0) {
      return {
        usd: round(pabiloRate.usd, 4),
        eur: pabiloRate.eur ? round(pabiloRate.eur, 4) : null,
        effectiveDate: null,
        source: 'pabilo',
      };
    }
  }

  throw new ProPaymentError(
    503,
    'RATE_UNAVAILABLE',
    'No pudimos consultar la tasa BCV oficial en este momento. Intenta de nuevo en unos segundos.',
  );
}

/**
 * Construye la configuración pública de pago (sin exponer claves ni bankIds)
 * combinando `config/proPayments` de Firestore y variables de entorno.
 */
async function loadPublicPaymentConfig({ db, env = process.env, runtimeSecrets = {} }) {
  let fsPublic = {};
  let fsPrivate = {};
  if (db) {
    try {
      const [pubSnap, privSnap] = await Promise.all([
        db.collection('config').doc('proPayments').get(),
        db.collection('config').doc('pabiloPrivate').get(),
      ]);
      if (pubSnap.exists) fsPublic = pubSnap.data() || {};
      if (privSnap.exists) fsPrivate = privSnap.data() || {};
    } catch {
      // Si config aún no existe o falla lectura, usamos env como respaldo seguro.
    }
  }

  const apiKey = String(runtimeSecrets.apiKey || env.PABILO_API_KEY || '').trim();
  const pmBankId = String(
    runtimeSecrets.userBankId || env.PABILO_USER_BANK_ID || fsPrivate.userBankId || '',
  ).trim();
  const binanceBankId = String(
    runtimeSecrets.binanceUserBankId ||
      env.PABILO_BINANCE_USER_BANK_ID ||
      fsPrivate.binanceUserBankId ||
      '',
  ).trim();
  const baseUrl = String(runtimeSecrets.baseUrl || env.PABILO_BASE_URL || '').trim();
  const webhookSecret = String(
    runtimeSecrets.webhookSecret || env.PABILO_WEBHOOK_SECRET || fsPrivate.webhookSecret || '',
  ).trim();

  const pmDoc = (fsPublic.pagoMovil && typeof fsPublic.pagoMovil === 'object' ? fsPublic.pagoMovil : {});
  const usdtDoc = (fsPublic.usdt && typeof fsPublic.usdt === 'object' ? fsPublic.usdt : {});
  const supportDoc = (fsPublic.support && typeof fsPublic.support === 'object' ? fsPublic.support : {});

  const publicConfig = {
    pagoMovil: {
      bank: String(pmDoc.banco || pmDoc.bank || env.PRO_PM_BANK || 'Banco de Venezuela (BDV · 0102)').trim(),
      cedulaRif: String(pmDoc.cedulaRif || env.PRO_PM_CEDULA || '31955598').trim(),
      phone: String(pmDoc.telefono || pmDoc.phone || env.PRO_PM_PHONE || '04220336568').trim(),
      holder: String(pmDoc.titular || pmDoc.holder || env.PRO_PM_HOLDER || '').trim(),
      autoVerify: Boolean(apiKey && pmBankId),
    },
    usdt: {
      network: String(usdtDoc.red || usdtDoc.network || env.PRO_USDT_NETWORK || 'Binance Pay (USDT)').trim(),
      binanceId: String(usdtDoc.binanceId || env.PRO_BINANCE_PAY_ID || '916942742').trim(),
      address: String(usdtDoc.direccion || usdtDoc.address || env.PRO_USDT_ADDRESS || '').trim(),
      autoVerify: Boolean(apiKey && binanceBankId),
    },
    support: {
      email: String(supportDoc.email || env.PRO_SUPPORT_EMAIL || 'soporterefillstore@gmail.com').trim(),
      whatsapp: String(supportDoc.whatsapp || env.PRO_SUPPORT_WHATSAPP || '+584161740312').trim(),
    },
  };

  return {
    publicConfig,
    secrets: {
      apiKey,
      pmBankId,
      binanceBankId,
      baseUrl,
      webhookSecret,
    },
  };
}

/**
 * Rate limiter por bucket temporal usando transacción en Firestore (`rateLimits/`).
 * Fail-open ante errores de Firestore para no bloquear cobros reales por contención.
 */
async function checkRateLimit({ db, name, key, maxRequests, windowMs, nowMs = Date.now() }) {
  if (!db) return;
  const bucket = Math.floor(nowMs / windowMs);
  const safeKey = String(key || 'anon').replace(/[^a-zA-Z0-9_.-]/g, '_').slice(0, 80);
  const docId = `${name}__${safeKey}__${bucket}`;
  const ref = db.collection('rateLimits').doc(docId);

  let allowed = true;
  try {
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const count = snap.exists ? Number(snap.data().count || 0) : 0;
      if (count >= maxRequests) {
        allowed = false;
        return;
      }
      tx.set(
        ref,
        {
          count: count + 1,
          bucket,
          expiresAt: new Date((bucket + 2) * windowMs).toISOString(),
          updatedAt: new Date(nowMs).toISOString(),
        },
        { merge: true },
      );
    });
  } catch {
    return;
  }

  if (!allowed) {
    throw new ProPaymentError(
      429,
      'RATE_LIMIT_EXCEEDED',
      'Demasiadas solicitudes seguidas. Espera un minuto e inténtalo de nuevo.',
    );
  }
}

async function getProPaymentConfigPayload({
  db,
  fetchImpl = globalThis.fetch,
  env = process.env,
  runtimeSecrets = {},
}) {
  const { publicConfig, secrets } = await loadPublicPaymentConfig({ db, env, runtimeSecrets });
  let bcvRate = null;
  try {
    bcvRate = await resolveAuthoritativeBcvRate({
      fetchImpl,
      pabiloConfig: { baseUrl: secrets.baseUrl, apiKey: secrets.apiKey },
    });
  } catch {
    bcvRate = null;
  }

  const plans = Object.values(PRO_PLANS).map((p) => ({
    ...p,
    estimatedBs: bcvRate ? round(p.priceUsd * bcvRate.usd, 2) : null,
  }));

  return {
    ok: true,
    plans,
    bcvRate,
    methods: {
      pago_movil: publicConfig.pagoMovil,
      usdt: publicConfig.usdt,
    },
    support: publicConfig.support,
  };
}

async function createProCheckout({
  db,
  uid,
  email = '',
  planId,
  methodId,
  createLink = true,
  fetchImpl = globalThis.fetch,
  env = process.env,
  runtimeSecrets = {},
  nowMs = Date.now(),
  orderIdGenerator = () => `pro_${crypto.randomUUID().replace(/-/g, '').slice(0, 16)}`,
}) {
  const plan = PRO_PLANS[planId];
  if (!plan) {
    throw new ProPaymentError(
      400,
      'INVALID_PLAN',
      'Plan inválido. Elige Mensual, Trimestral, 6 Meses o Anual.',
    );
  }
  const method = PAYMENT_METHODS[methodId];
  if (!method) {
    throw new ProPaymentError(400, 'INVALID_METHOD', 'Método de pago inválido.');
  }

  const { publicConfig, secrets } = await loadPublicPaymentConfig({ db, env, runtimeSecrets });
  const bcvRate = await resolveAuthoritativeBcvRate({
    fetchImpl,
    pabiloConfig: { baseUrl: secrets.baseUrl, apiKey: secrets.apiKey },
  });

  const expectedAmountUsd = round(plan.priceUsd, 2);
  const expectedAmountBs = round(expectedAmountUsd * bcvRate.usd, 2);
  const expectedTotal = method.currency === 'BS' ? expectedAmountBs : expectedAmountUsd;
  const nowIso = new Date(nowMs).toISOString();
  const expiresAt = new Date(nowMs + ORDER_TTL_MS).toISOString();
  const orderId = orderIdGenerator();
  const autoVerify =
    method.id === 'pago_movil' ? publicConfig.pagoMovil.autoVerify : publicConfig.usdt.autoVerify;
  const bankId = method.id === 'pago_movil' ? secrets.pmBankId : secrets.binanceBankId;

  let linkResult = null;
  if (autoVerify && secrets.apiKey && bankId && createLink !== false) {
    try {
      linkResult = await createPaymentLink({
        baseUrl: secrets.baseUrl,
        apiKey: secrets.apiKey,
        userBankId: bankId,
        amount: expectedTotal,
        currency: method.currency === 'BS' ? 'VEF' : 'USDT',
        name: `${plan.name} · MargenCalcu`,
        description: `Orden ${orderId}${email ? ` · ${email}` : ''}`.slice(0, 120),
        redirectUrl: `https://margencalcu.online/gracias?orderId=${encodeURIComponent(orderId)}`,
        webhookUrl: String(
          runtimeSecrets.webhookUrl ||
            env.PABILO_WEBHOOK_URL ||
            'https://pabilowebhook-yqgkyclg5a-uc.a.run.app',
        ).trim(),
        notificationByWhatsapp: true,
        fetchImpl,
      });
    } catch {
      linkResult = null;
    }
  }

  const orderDoc = {
    v: 1,
    id: orderId,
    uid,
    email: String(email || ''),
    plan: plan.id,
    planName: plan.name,
    durationDays: plan.durationDays,
    method: method.id,
    currency: method.currency,
    expectedAmountUsd,
    expectedAmountBs,
    expectedTotal,
    paidAmount: 0,
    remainingAmount: expectedTotal,
    partials: [],
    partialRefs: [],
    rateBs: bcvRate.usd,
    rateSource: bcvRate.source,
    rateEffectiveDate: bcvRate.effectiveDate,
    status: 'awaiting_payment',
    attempts: 0,
    maxAttempts: MAX_VERIFY_ATTEMPTS,
    autoVerify,
    paymentLinkId: linkResult && linkResult.ok ? linkResult.id : null,
    paymentLinkUrl: linkResult && linkResult.ok ? linkResult.url : null,
    paymentLinkStatus: linkResult && linkResult.ok ? linkResult.status : null,
    lastAttemptedReference: null,
    providerErrorAt: null,
    retriableRefs: [],
    activeVerifyingRef: null,
    verifyingStartedAt: null,
    payment: null,
    expiresAt,
    createdAt: nowIso,
    updatedAt: nowIso,
  };

  await db.collection('proOrders').doc(orderId).set(orderDoc);

  return {
    ok: true,
    order: orderDoc,
    paymentConfig: {
      pago_movil: publicConfig.pagoMovil,
      usdt: publicConfig.usdt,
      support: publicConfig.support,
    },
  };
}

/**
 * Busca si existe otra orden ya pagada (o abonada parcialmente) que haya consumido
 * la misma referencia normalizada en el mismo método. Usa consultas de campo único
 * para no requerir índices compuestos en Firestore.
 */
async function findConflictingOrderWithReference({ db, methodId, normalizedRef, excludeOrderId }) {
  const paidSnap = await db
    .collection('proOrders')
    .where('payment.reference', '==', normalizedRef)
    .limit(10)
    .get();

  for (const doc of paidSnap.docs) {
    if (doc.id === excludeOrderId) continue;
    const data = doc.data() || {};
    if (data.method === methodId && data.status === 'paid') {
      return { id: doc.id, ...data };
    }
  }

  const partialSnap = await db
    .collection('proOrders')
    .where('partialRefs', 'array-contains', normalizedRef)
    .limit(10)
    .get();

  for (const doc of partialSnap.docs) {
    if (doc.id === excludeOrderId) continue;
    const data = doc.data() || {};
    if (data.method === methodId) {
      return { id: doc.id, ...data };
    }
  }

  return null;
}

async function recordVerificationLog({ db, entry }) {
  const payload = {
    recordedAt: new Date().toISOString(),
    ...entry,
  };
  try {
    console.log(JSON.stringify({ event: 'pro_payment_audit', ...payload }));
  } catch {
    // Ignorar error de serialización en consola
  }
  if (!db) return;
  try {
    const id = `${Date.now()}_${crypto.randomUUID().slice(0, 8)}`;
    await db.collection('pabiloLogs').doc(id).set(payload);
  } catch {
    // El log nunca debe bloquear un cobro válido
  }
}

/**
 * Busca si este usuario tiene una orden abierta marcada para reconciliación
 * por el incidente del doble POST del 2026-11-11 que aún no haya sido consumida.
 */
async function findReconcilableIncidentOrder({ db, uid, methodId, excludeOrderId }) {
  const snap = await db.collection('proOrders').where('uid', '==', uid).limit(20).get();
  for (const doc of snap.docs) {
    if (doc.id === excludeOrderId) continue;
    const data = doc.data() || {};
    if (
      data.reconcileBugAllow === true &&
      data.status === 'awaiting_payment' &&
      !data.supersededByOrderId &&
      data.method === methodId
    ) {
      return { id: doc.id, ...data };
    }
  }
  return null;
}

async function releaseReferenceLock({
  db,
  lockKey,
  orderId,
  orderStatus = 'awaiting_payment',
  extraOrderPatch = {},
}) {
  const lockRef = lockKey ? db.collection('paymentRefs').doc(lockKey) : null;
  const orderRef = db.collection('proOrders').doc(orderId);
  await db.runTransaction(async (tx) => {
    if (lockRef) {
      const lockSnap = await tx.get(lockRef);
      if (lockSnap.exists && lockSnap.data() && lockSnap.data().orderId === orderId) {
        const lockStatus = lockSnap.data().status;
        if (lockStatus === 'verifying') {
          tx.delete(lockRef);
        }
      }
    }
    tx.set(
      orderRef,
      {
        status: orderStatus,
        activeVerifyingRef: null,
        verifyingStartedAt: null,
        updatedAt: new Date().toISOString(),
        ...extraOrderPatch,
      },
      { merge: true },
    );
  });
}

async function applyPaidOrderAndActivatePro({
  db,
  orderRef,
  orderId,
  claimedOrder,
  uid,
  method,
  lockKey = null,
  linkLockKey = null,
  normalizedRef,
  amountCheck,
  amountVerifiedByProvider = false,
  reconciledDuplicate = false,
  paymentDate = null,
  activatedBy = 'pabilo_auto',
  reconcileOrderId = null,
  nowMs = Date.now(),
}) {
  const plan = PRO_PLANS[claimedOrder.plan] || PRO_PLANS.monthly;
  const alreadyPaid = Number(claimedOrder.paidAmount || 0);
  const subCurrentRef = db.collection('users').doc(uid).collection('subscription').doc('current');
  const subPendingRef = db.collection('users').doc(uid).collection('subscription').doc('pending');
  const lockRef = lockKey ? db.collection('paymentRefs').doc(lockKey) : null;
  const linkLockRef = linkLockKey ? db.collection('paymentRefs').doc(linkLockKey) : null;
  const reconcileOrderRef =
    reconcileOrderId && reconcileOrderId !== orderId
      ? db.collection('proOrders').doc(reconcileOrderId)
      : null;

  let activatedSub;
  let alreadyPaidOrder = false;

  await db.runTransaction(async (tx) => {
    const reads = [tx.get(orderRef), tx.get(subCurrentRef), tx.get(subPendingRef)];
    if (lockRef) reads.push(tx.get(lockRef));
    if (linkLockRef && linkLockRef.path !== (lockRef && lockRef.path)) reads.push(tx.get(linkLockRef));
    if (reconcileOrderRef) reads.push(tx.get(reconcileOrderRef));

    const results = await Promise.all(reads);
    const freshOrderSnap = results[0];
    const subSnap = results[1];
    const pendingSnap = results[2];

    let cursor = 3;
    const lockSnap = lockRef ? results[cursor++] : null;
    const linkLockSnap =
      linkLockRef && linkLockRef.path !== (lockRef && lockRef.path) ? results[cursor++] : null;
    const reconcileSnap = reconcileOrderRef ? results[cursor++] : null;

    const freshOrder = freshOrderSnap.exists ? freshOrderSnap.data() || {} : claimedOrder;
    const existingSub = subSnap.exists ? subSnap.data() : null;

    if (freshOrder.status === 'paid') {
      alreadyPaidOrder = true;
      activatedSub = existingSub;
      return;
    }

    if (lockSnap && lockSnap.exists) {
      const ld = lockSnap.data() || {};
      if (ld.status === 'consumed' && ld.orderId !== orderId) {
        throw new ProPaymentError(
          409,
          'REFERENCE_ALREADY_USED',
          'Esta referencia ya fue aplicada en otra orden.',
        );
      }
    }

    if (linkLockSnap && linkLockSnap.exists) {
      const lld = linkLockSnap.data() || {};
      if (lld.status === 'consumed' && lld.orderId !== orderId) {
        throw new ProPaymentError(
          409,
          'REFERENCE_ALREADY_USED',
          'Este enlace de pago ya fue aplicado anteriormente.',
        );
      }
    }

    if (reconcileOrderRef) {
      if (!reconcileSnap || !reconcileSnap.exists) {
        throw new ProPaymentError(
          409,
          'REFERENCE_ALREADY_USED',
          'Esta referencia ya fue verificada anteriormente en otro pago.',
        );
      }
      const recData = reconcileSnap.data() || {};
      if (recData.status !== 'awaiting_payment' || recData.supersededByOrderId) {
        throw new ProPaymentError(
          409,
          'REFERENCE_ALREADY_USED',
          'Esta referencia ya fue aplicada anteriormente.',
        );
      }
    }

    const { startDate, endDate, nowIso: activatedAt } = computeSubscriptionDates({
      existingSub,
      durationDays: Number(freshOrder.durationDays || claimedOrder.durationDays || plan.durationDays),
      nowMs,
    });

    const totalPaid = round(alreadyPaid + amountCheck.received, 2);
    activatedSub = {
      v: 1,
      plan: plan.id,
      status: 'active',
      startDate,
      endDate,
      provider: method.providerId,
      paymentRef: normalizedRef,
      orderId,
      paymentLinkId: freshOrder.paymentLinkId || claimedOrder.paymentLinkId || null,
      amountUsd: Number(freshOrder.expectedAmountUsd || claimedOrder.expectedAmountUsd || plan.priceUsd),
      paidAmount: totalPaid,
      currency: method.currency,
      overpaidAlert: amountCheck.overpaidAlert,
      activatedBy,
      updatedAt: activatedAt,
    };

    if (lockRef) {
      tx.set(
        lockRef,
        {
          lockKey,
          reference: normalizedRef,
          method: method.id,
          orderId,
          uid,
          status: 'consumed',
          amount: amountCheck.received,
          consumedAt: activatedAt,
          updatedAt: activatedAt,
        },
        { merge: true },
      );
    }

    if (linkLockRef && linkLockRef.path !== (lockRef && lockRef.path)) {
      tx.set(
        linkLockRef,
        {
          lockKey: linkLockKey,
          reference: normalizedRef,
          method: method.id,
          orderId,
          uid,
          status: 'consumed',
          amount: amountCheck.received,
          consumedAt: activatedAt,
          updatedAt: activatedAt,
        },
        { merge: true },
      );
    }

    if (reconcileOrderRef) {
      tx.update(reconcileOrderRef, {
        status: 'superseded',
        supersededByOrderId: orderId,
        reconcileBugAllow: false,
        updatedAt: activatedAt,
      });
    }

    tx.update(orderRef, {
      status: 'paid',
      paidAmount: totalPaid,
      remainingAmount: 0,
      paidAt: activatedAt,
      paymentLinkStatus: freshOrder.paymentLinkId ? 'paid' : freshOrder.paymentLinkStatus || null,
      activeVerifyingRef: null,
      verifyingStartedAt: null,
      lastAttemptedReference: null,
      providerErrorAt: null,
      reconcileBugAllow: false,
      payment: {
        reference: normalizedRef,
        provider: method.providerId,
        reportedAmount: amountCheck.received,
        overpaid: amountCheck.overpaid,
        overpaidAlert: amountCheck.overpaidAlert,
        amountVerifiedByProvider: Boolean(amountVerifiedByProvider),
        reconciledDuplicate: Boolean(reconciledDuplicate),
        activatedBy,
        paymentDate: paymentDate || null,
        paidAt: activatedAt,
      },
      updatedAt: activatedAt,
    });

    tx.set(subCurrentRef, activatedSub);
    if (pendingSnap.exists) {
      tx.delete(subPendingRef);
    }
  });

  return { alreadyPaidOrder, subscription: activatedSub };
}

async function verifyOrderViaPaymentLink({
  db,
  uid,
  orderId,
  preOrder,
  method,
  secrets,
  fetchImpl,
  nowMs,
}) {
  const linkId = String(preOrder.paymentLinkId || '').trim();
  const linkLockKey = `link_${linkId}`;
  const orderRef = db.collection('proOrders').doc(orderId);
  const linkLockRef = db.collection('paymentRefs').doc(linkLockKey);
  const nowIso = new Date(nowMs).toISOString();

  let claimedOrder;
  await db.runTransaction(async (tx) => {
    const [orderSnap, linkLockSnap] = await Promise.all([tx.get(orderRef), tx.get(linkLockRef)]);
    if (!orderSnap.exists) {
      throw new ProPaymentError(404, 'ORDER_NOT_FOUND', 'Orden no encontrada.');
    }
    const order = orderSnap.data() || {};
    if (order.uid !== uid) {
      throw new ProPaymentError(403, 'FORBIDDEN', 'Esta orden no pertenece a tu cuenta.');
    }
    if (order.status === 'paid') {
      throw new ProPaymentError(200, 'ALREADY_PAID', 'Orden ya pagada.');
    }
    if (order.status === 'verifying') {
      const startedMs = Date.parse(order.verifyingStartedAt || order.updatedAt || '');
      if (!Number.isFinite(startedMs) || nowMs - startedMs <= 65_000) {
        throw new ProPaymentError(
          409,
          'VERIFY_IN_PROGRESS',
          'Ya estamos verificando un pago en esta orden. Espera unos segundos.',
        );
      }
    }

    const paidAmount = Number(order.paidAmount || 0);
    const expiresMs = order.expiresAt ? new Date(order.expiresAt).getTime() : 0;
    if (paidAmount <= 0 && expiresMs && expiresMs < nowMs) {
      throw new ProPaymentError(
        400,
        'ORDER_EXPIRED',
        'Esta orden expiró para congelar la tasa BCV. Genera una orden nueva con la tasa vigente.',
      );
    }

    if (linkLockSnap.exists) {
      const ld = linkLockSnap.data() || {};
      if (ld.orderId !== orderId || ld.status === 'consumed') {
        throw new ProPaymentError(
          409,
          'REFERENCE_ALREADY_USED',
          'Este enlace de pago ya fue procesado anteriormente.',
        );
      }
    }

    tx.set(linkLockRef, {
      lockKey: linkLockKey,
      reference: `LINK_${linkId}`,
      method: method.id,
      orderId,
      uid,
      status: 'verifying',
      lockedAt: nowIso,
      updatedAt: nowIso,
    });
    tx.update(orderRef, {
      status: 'verifying',
      activeVerifyingRef: `LINK_${linkId}`,
      verifyingStartedAt: nowIso,
      updatedAt: nowIso,
    });
    claimedOrder = order;
  });

  const linkInfo = await getPaymentLinkInfo({
    baseUrl: secrets.baseUrl,
    apiKey: secrets.apiKey,
    paymentLinkId: linkId,
    fetchImpl,
  });

  await recordVerificationLog({
    db,
    entry: {
      source: 'verifyProPayment_link',
      orderId,
      uid,
      method: method.id,
      paymentLinkId: linkId,
      status: linkInfo.status,
      isPaid: linkInfo.isPaid,
      reference: linkInfo.reference,
      amount: linkInfo.amount,
      paymentDate: linkInfo.paymentDate,
      raw: linkInfo.raw || null,
    },
  });

  if (!linkInfo.ok || !linkInfo.isPaid) {
    await releaseReferenceLock({
      db,
      lockKey: linkLockKey,
      orderId,
      orderStatus: 'awaiting_payment',
    });
    return {
      ok: false,
      httpStatus: 404,
      code: 'PAYMENT_NOT_FOUND',
      retryable: true,
      orderId,
      message:
        'Tu enlace de pago aún aparece pendiente en Pabilo. Si acabas de transferir o pagar, espera unos segundos o ingresa tu referencia bancaria.',
    };
  }

  const reportedAmount = linkInfo.amount;
  if (reportedAmount === null || reportedAmount === undefined || Number(reportedAmount) <= 0) {
    await releaseReferenceLock({ db, lockKey: linkLockKey, orderId, orderStatus: 'awaiting_payment' });
    return {
      ok: false,
      httpStatus: 422,
      code: 'UNREADABLE_AMOUNT',
      retryable: false,
      orderId,
      message: 'No pudimos validar el monto del enlace pagado en Pabilo.',
    };
  }

  const expectedTotal = Number(claimedOrder.expectedTotal);
  const alreadyPaid = Number(claimedOrder.paidAmount || 0);
  const pendingAmount = round(Math.max(0.01, expectedTotal - alreadyPaid), 2);
  const amountCheck = checkAmount(pendingAmount, reportedAmount);
  if (!amountCheck.ok && amountCheck.shortfall > 0) {
    await releaseReferenceLock({ db, lockKey: linkLockKey, orderId, orderStatus: 'awaiting_payment' });
    return {
      ok: false,
      httpStatus: 409,
      code: 'INSUFFICIENT_AMOUNT',
      retryable: false,
      orderId,
      message: `El monto pagado en el enlace (${reportedAmount.toFixed(2)}) es menor al monto del plan (${pendingAmount.toFixed(2)}).`,
    };
  }

  const normalizedRef = linkInfo.reference
    ? normalizeReference(linkInfo.reference, method.allowLetters) || `LINK_${linkId}`
    : `LINK_${linkId}`;

  if (linkInfo.reference) {
    const conflict = await findConflictingOrderWithReference({
      db,
      methodId: method.id,
      normalizedRef,
      excludeOrderId: orderId,
    });
    if (conflict) {
      await releaseReferenceLock({ db, lockKey: linkLockKey, orderId, orderStatus: 'awaiting_payment' });
      return {
        ok: false,
        httpStatus: 409,
        code: 'REFERENCE_ALREADY_USED',
        retryable: false,
        orderId,
        message: 'Esta referencia ya fue verificada anteriormente en otra orden.',
      };
    }
  }

  const refLockKey = linkInfo.reference ? makeReferenceLockKey(method.id, normalizedRef) : null;
  const activation = await applyPaidOrderAndActivatePro({
    db,
    orderRef,
    orderId,
    claimedOrder,
    uid,
    method,
    lockKey: refLockKey,
    linkLockKey,
    normalizedRef,
    amountCheck,
    amountVerifiedByProvider: true,
    reconciledDuplicate: true,
    paymentDate: linkInfo.paymentDate,
    activatedBy: 'pabilo_link',
    nowMs,
  });

  if (activation.alreadyPaidOrder) {
    return {
      ok: true,
      httpStatus: 200,
      code: 'ALREADY_ACTIVATED',
      status: 'paid',
      orderId,
      subscription: activation.subscription,
      message: 'Tu suscripción Pro ya está activa para esta orden.',
    };
  }

  return {
    ok: true,
    httpStatus: 200,
    code: 'ACTIVATED',
    status: 'paid',
    orderId,
    reconciledDuplicate: true,
    subscription: activation.subscription,
    message: '¡Pago confirmado mediante enlace Pabilo! Tu plan Pro ya está activo.',
  };
}

async function verifyProPayment({
  db,
  uid,
  orderId,
  rawReference = '',
  paymentDate = null,
  fetchImpl = globalThis.fetch,
  env = process.env,
  runtimeSecrets = {},
  nowMs = Date.now(),
}) {
  if (!orderId || typeof orderId !== 'string') {
    throw new ProPaymentError(400, 'INVALID_ORDER', 'Falta el identificador de la orden.');
  }

  const preOrderSnap = await db.collection('proOrders').doc(orderId).get();
  if (!preOrderSnap.exists) {
    throw new ProPaymentError(404, 'ORDER_NOT_FOUND', 'No encontramos esta orden de pago.');
  }
  const preOrder = preOrderSnap.data() || {};
  if (preOrder.uid !== uid) {
    throw new ProPaymentError(403, 'FORBIDDEN', 'Esta orden no pertenece a tu cuenta.');
  }

  if (preOrder.status === 'paid') {
    const subSnap = await db.collection('users').doc(uid).collection('subscription').doc('current').get();
    return {
      ok: true,
      httpStatus: 200,
      code: 'ALREADY_ACTIVATED',
      status: 'paid',
      orderId,
      subscription: subSnap.exists ? subSnap.data() : null,
      message: 'Tu suscripción Pro ya está activa para esta orden.',
    };
  }

  const method = PAYMENT_METHODS[preOrder.method];
  if (!method) {
    throw new ProPaymentError(400, 'INVALID_METHOD', 'Método de pago inválido en la orden.');
  }

  const { secrets } = await loadPublicPaymentConfig({ db, env, runtimeSecrets });
  const bankId = method.id === 'pago_movil' ? secrets.pmBankId : secrets.binanceBankId;
  if (!secrets.apiKey || !bankId) {
    throw new ProPaymentError(
      503,
      'AUTO_VERIFY_UNAVAILABLE',
      'La verificación automática de Pabilo no está activa para este método aún. Puedes enviar tu referencia para validación manual.',
      { fallbackManual: true },
    );
  }

  const hasRawRef = Boolean(String(rawReference || '').trim());
  if (!hasRawRef) {
    if (preOrder.paymentLinkId) {
      return verifyOrderViaPaymentLink({
        db,
        uid,
        orderId,
        preOrder,
        method,
        secrets,
        fetchImpl,
        nowMs,
      });
    }
    throw new ProPaymentError(
      400,
      'INVALID_REFERENCE',
      method.allowLetters
        ? `Ingresa un ID de orden/referencia válido (mínimo ${method.minRefLength} caracteres).`
        : `Ingresa los dígitos de la referencia bancaria (mínimo ${method.minRefLength} dígitos).`,
    );
  }

  const normalizedRef = normalizeReference(rawReference, method.allowLetters);
  if (
    !normalizedRef ||
    normalizedRef.length < method.minRefLength ||
    normalizedRef.length > method.maxRefLength
  ) {
    throw new ProPaymentError(
      400,
      'INVALID_REFERENCE',
      method.allowLetters
        ? `Ingresa un ID de orden/referencia válido (mínimo ${method.minRefLength} caracteres).`
        : `Ingresa los dígitos de la referencia bancaria (mínimo ${method.minRefLength} dígitos).`,
    );
  }

  const lockKey = makeReferenceLockKey(method.id, normalizedRef);
  const lockRef = db.collection('paymentRefs').doc(lockKey);
  const orderRef = db.collection('proOrders').doc(orderId);
  const nowIso = new Date(nowMs).toISOString();

  // Paso 1: Reclamación transaccional de la referencia antes de consultar Pabilo.
  let claimedOrder;
  let wasStaleVerifyingSameRef = false;
  await db.runTransaction(async (tx) => {
    const [orderSnap, lockSnap] = await Promise.all([tx.get(orderRef), tx.get(lockRef)]);
    if (!orderSnap.exists) {
      throw new ProPaymentError(404, 'ORDER_NOT_FOUND', 'Orden no encontrada.');
    }
    const order = orderSnap.data() || {};
    if (order.uid !== uid) {
      throw new ProPaymentError(403, 'FORBIDDEN', 'Esta orden no pertenece a tu cuenta.');
    }
    if (order.status === 'paid') {
      throw new ProPaymentError(200, 'ALREADY_PAID', 'Orden ya pagada.');
    }
    if (order.status === 'verifying') {
      const startedMs = Date.parse(order.verifyingStartedAt || order.updatedAt || '');
      const isStale = Number.isFinite(startedMs) && nowMs - startedMs > 65_000;
      if (!isStale) {
        throw new ProPaymentError(
          409,
          'VERIFY_IN_PROGRESS',
          'Ya estamos verificando un pago en esta orden. Espera unos segundos.',
        );
      }
      wasStaleVerifyingSameRef = Boolean(
        order.activeVerifyingRef && order.activeVerifyingRef === normalizedRef,
      );
    }

    const attempts = Number(order.attempts || 0);
    const maxAttempts = Number(order.maxAttempts || MAX_VERIFY_ATTEMPTS);
    if (attempts >= maxAttempts) {
      throw new ProPaymentError(
        400,
        'MAX_ATTEMPTS_EXCEEDED',
        'Alcanzaste el máximo de 5 intentos para esta orden. Genera una nueva orden de pago.',
      );
    }

    const paidAmount = Number(order.paidAmount || 0);
    const expiresMs = order.expiresAt ? new Date(order.expiresAt).getTime() : 0;
    if (paidAmount <= 0 && expiresMs && expiresMs < nowMs) {
      throw new ProPaymentError(
        400,
        'ORDER_EXPIRED',
        'Esta orden expiró para congelar la tasa BCV. Genera una orden nueva con la tasa vigente.',
      );
    }

    const existingPartialRefs = Array.isArray(order.partialRefs) ? order.partialRefs : [];
    if (existingPartialRefs.includes(normalizedRef)) {
      throw new ProPaymentError(
        409,
        'PARTIAL_REF_ALREADY_CREDITED',
        'Esa referencia ya se abonó parcialmente a esta orden. Para completar el resto usa la referencia del nuevo pago.',
      );
    }

    if (lockSnap.exists) {
      const lockData = lockSnap.data() || {};
      if (lockData.orderId !== orderId) {
        throw new ProPaymentError(
          409,
          'REFERENCE_ALREADY_USED',
          'Esta referencia ya está siendo procesada o fue utilizada en otra orden.',
        );
      }
      if (lockData.status === 'consumed' || lockData.status === 'partial') {
        throw new ProPaymentError(
          409,
          'REFERENCE_ALREADY_USED',
          'Esta referencia ya fue aplicada anteriormente.',
        );
      }
    }

    tx.set(lockRef, {
      lockKey,
      reference: normalizedRef,
      method: method.id,
      orderId,
      uid,
      status: 'verifying',
      lockedAt: nowIso,
      updatedAt: nowIso,
    });

    tx.update(orderRef, {
      status: 'verifying',
      attempts: attempts + 1,
      activeVerifyingRef: normalizedRef,
      verifyingStartedAt: nowIso,
      updatedAt: nowIso,
    });

    claimedOrder = { ...order, attempts: attempts + 1 };
  });

  // Paso 2: Consultar Pabilo por referencia (con amount: 0 primero y fecha_pago en Caracas).
  const expectedTotal = Number(claimedOrder.expectedTotal);
  const alreadyPaid = Number(claimedOrder.paidAmount || 0);
  const pendingAmount = round(Math.max(0.01, expectedTotal - alreadyPaid), 2);
  const validFechaPago =
    typeof paymentDate === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(paymentDate.trim())
      ? paymentDate.trim()
      : getCaracasDateString(nowMs, 0);

  const verification = await verifyPayment({
    baseUrl: secrets.baseUrl,
    apiKey: secrets.apiKey,
    userBankId: bankId,
    bankReference: normalizedRef,
    amount: pendingAmount,
    fechaPago: validFechaPago,
    nowMs,
    fetchImpl,
  });

  await recordVerificationLog({
    db,
    entry: {
      source: 'verifyProPayment',
      orderId,
      uid,
      method: method.id,
      reference: normalizedRef,
      requestedAmount: pendingAmount,
      fecha_pago: validFechaPago,
      found: Boolean(verification.found),
      is_new: verification.isNew,
      reportedAmount: verification.reportedAmount ?? null,
      credit_cost: verification.creditCost ?? null,
      payment_date: verification.paymentDate ?? null,
      payment_status: verification.paymentStatus ?? null,
      payment_link_id: verification.paymentLinkId ?? null,
      providerError: Boolean(verification.providerError),
      raw: verification.raw || null,
    },
  });

  // Paso 3A: Error temporal o de red/timeout/banco desconocido -> liberar lock y marcar para autoreconciliación.
  if (verification.providerError) {
    const prevRetriable = Array.isArray(claimedOrder.retriableRefs)
      ? claimedOrder.retriableRefs.filter((r) => r !== normalizedRef)
      : [];
    const nextRetriable = verification.unknownBankAccount
      ? prevRetriable
      : [...prevRetriable, normalizedRef].slice(-5);
    await releaseReferenceLock({
      db,
      lockKey,
      orderId,
      orderStatus: 'awaiting_payment',
      extraOrderPatch: {
        lastAttemptedReference: normalizedRef,
        providerErrorAt: new Date().toISOString(),
        retriableRefs: nextRetriable,
      },
    });
    return {
      ok: false,
      httpStatus: verification.unknownBankAccount ? 500 : 502,
      code: verification.unknownBankAccount
        ? 'PABILO_BANK_NOT_FOUND'
        : verification.timedOut
          ? 'PROVIDER_TIMEOUT'
          : 'PROVIDER_ERROR',
      retryable: !verification.unknownBankAccount,
      orderId,
      message: verification.message,
    };
  }

  // Paso 3B: Pago aún no encontrado en Pabilo -> liberar lock para permitir reintento o corrección.
  if (!verification.found) {
    await releaseReferenceLock({
      db,
      lockKey,
      orderId,
      orderStatus: 'awaiting_payment',
    });
    return {
      ok: false,
      httpStatus: 404,
      code: 'PAYMENT_NOT_FOUND',
      retryable: true,
      orderId,
      attemptsRemaining: Math.max(0, MAX_VERIFY_ATTEMPTS - claimedOrder.attempts),
      message:
        verification.message ||
        'No encontramos un pago con esa referencia todavía. Si acabas de transferir, espera 15 segundos y vuelve a verificar.',
    };
  }

  // Paso 3C: `is_new: false` -> verificar si pertenece legítimamente a este pedido/enlace y nunca a otro pedido.
  let reconciledDuplicate = false;
  let isPaidViaOrderLink = false;
  let reconcileOrderId = null;

  if (!verification.isNew) {
    const conflictingOrder = await findConflictingOrderWithReference({
      db,
      methodId: method.id,
      normalizedRef,
      excludeOrderId: orderId,
    });

    if (conflictingOrder) {
      await releaseReferenceLock({
        db,
        lockKey,
        orderId,
        orderStatus: 'awaiting_payment',
      });
      return {
        ok: false,
        httpStatus: 409,
        code: 'REFERENCE_ALREADY_USED',
        retryable: false,
        orderId,
        message: 'Esta referencia ya fue verificada anteriormente en otro pedido.',
      };
    }

    // Idempotencia si el usuario ya tiene Pro activo con esta misma referencia
    const subSnap = await db.collection('users').doc(uid).collection('subscription').doc('current').get();
    const currentSub = subSnap.exists ? subSnap.data() : null;
    if (
      currentSub &&
      currentSub.status === 'active' &&
      currentSub.paymentRef === normalizedRef &&
      currentSub.endDate &&
      new Date(currentSub.endDate).getTime() > nowMs
    ) {
      await releaseReferenceLock({ db, lockKey, orderId, orderStatus: 'paid' });
      return {
        ok: true,
        httpStatus: 200,
        code: 'ALREADY_ACTIVATED',
        status: 'paid',
        orderId,
        subscription: currentSub,
        message: 'Tu suscripción Pro ya está activa con esta referencia.',
      };
    }

    // Caso 1: Pago realizado mediante enlace de Pabilo de ESTE pedido (`GET /paymentlink/{id}/info`).
    if (claimedOrder.paymentLinkId) {
      if (
        verification.paymentLinkId &&
        String(verification.paymentLinkId) === String(claimedOrder.paymentLinkId)
      ) {
        isPaidViaOrderLink = true;
      } else {
        const linkInfo = await getPaymentLinkInfo({
          baseUrl: secrets.baseUrl,
          apiKey: secrets.apiKey,
          paymentLinkId: claimedOrder.paymentLinkId,
          fetchImpl,
        });
        if (linkInfo.ok && linkInfo.isPaid) {
          const linkRefNorm = linkInfo.reference
            ? normalizeReference(linkInfo.reference, method.allowLetters)
            : null;
          if (!linkRefNorm || linkRefNorm === normalizedRef) {
            isPaidViaOrderLink = true;
          }
        }
      }
    }

    const retriableRefs = Array.isArray(claimedOrder.retriableRefs) ? claimedOrder.retriableRefs : [];
    const isSelfRetryAfterError =
      (claimedOrder.lastAttemptedReference === normalizedRef && Boolean(claimedOrder.providerErrorAt)) ||
      retriableRefs.includes(normalizedRef) ||
      wasStaleVerifyingSameRef ||
      Boolean(claimedOrder.reconcileBugAllow);

    let incidentOrder = null;
    if (!isPaidViaOrderLink && !isSelfRetryAfterError) {
      incidentOrder = await findReconcilableIncidentOrder({
        db,
        uid,
        methodId: method.id,
        excludeOrderId: orderId,
      });
      if (incidentOrder) {
        reconcileOrderId = incidentOrder.id;
      }
    }

    if (!isPaidViaOrderLink && !isSelfRetryAfterError && !incidentOrder) {
      await releaseReferenceLock({
        db,
        lockKey,
        orderId,
        orderStatus: 'awaiting_payment',
      });
      return {
        ok: false,
        httpStatus: 409,
        code: 'REFERENCE_ALREADY_USED',
        retryable: false,
        orderId,
        message: 'Esta referencia ya fue verificada anteriormente en otro pago.',
      };
    }
    reconciledDuplicate = true;
  }

  // Paso 3D: Verificación estricta de monto (nunca aprueba sin reportedAmount).
  const reportedAmount = verification.reportedAmount;
  if (reportedAmount === null || reportedAmount === undefined || Number(reportedAmount) <= 0) {
    await releaseReferenceLock({
      db,
      lockKey,
      orderId,
      orderStatus: 'awaiting_payment',
    });
    return {
      ok: false,
      httpStatus: 422,
      code: 'UNREADABLE_AMOUNT',
      retryable: false,
      orderId,
      message: 'No pudimos validar el monto del pago reportado por el banco.',
    };
  }

  const amountCheck = checkAmount(pendingAmount, reportedAmount);

  // Si `is_new: false` y el monto reportado no alcanza el esperado, rechazar en lugar de aceptar parcial ambiguo.
  if (!verification.isNew && !amountCheck.ok && amountCheck.shortfall > 0) {
    await releaseReferenceLock({
      db,
      lockKey,
      orderId,
      orderStatus: 'awaiting_payment',
    });
    return {
      ok: false,
      httpStatus: 409,
      code: 'INSUFFICIENT_AMOUNT',
      retryable: false,
      orderId,
      message: `El monto reportado (${amountCheck.received.toFixed(2)}) es menor al monto esperado (${pendingAmount.toFixed(2)}).`,
    };
  }

  // Paso 3E: Pago parcial nuevo (`is_new: true`) -> conservar lock sobre esta referencia, acumular `paidAmount`.
  if (!amountCheck.ok && amountCheck.shortfall > 0) {
    const newPaidAmount = round(alreadyPaid + amountCheck.received, 2);
    const newRemainingAmount = round(Math.max(0, expectedTotal - newPaidAmount), 2);
    const extendedExpiry = new Date(
      Math.max(nowMs + ORDER_TTL_MS, new Date(claimedOrder.expiresAt || nowMs).getTime()),
    ).toISOString();
    const finishIso = new Date().toISOString();

    await db.runTransaction(async (tx) => {
      const freshOrderSnap = await tx.get(orderRef);
      const freshOrder = freshOrderSnap.data() || {};
      const nextPartials = Array.isArray(freshOrder.partials) ? [...freshOrder.partials] : [];
      nextPartials.push({
        reference: normalizedRef,
        amount: amountCheck.received,
        currency: method.currency,
        recordedAt: finishIso,
        reconciledDuplicate,
      });
      const nextPartialRefs = Array.isArray(freshOrder.partialRefs) ? [...freshOrder.partialRefs] : [];
      if (!nextPartialRefs.includes(normalizedRef)) nextPartialRefs.push(normalizedRef);

      tx.set(
        lockRef,
        {
          lockKey,
          reference: normalizedRef,
          method: method.id,
          orderId,
          uid,
          status: 'partial',
          amount: amountCheck.received,
          updatedAt: finishIso,
        },
        { merge: true },
      );

      tx.update(orderRef, {
        status: 'awaiting_payment',
        paidAmount: newPaidAmount,
        remainingAmount: newRemainingAmount,
        partials: nextPartials,
        partialRefs: nextPartialRefs,
        expiresAt: extendedExpiry,
        activeVerifyingRef: null,
        verifyingStartedAt: null,
        lastAttemptedReference: null,
        providerErrorAt: null,
        updatedAt: finishIso,
      });
    });

    return {
      ok: false,
      httpStatus: 200,
      code: 'PARTIAL_PAYMENT',
      retryable: true,
      orderId,
      currency: method.currency,
      reportedAmount: amountCheck.received,
      paidAmount: newPaidAmount,
      remainingAmount: newRemainingAmount,
      expectedTotal,
      expiresAt: extendedExpiry,
      message:
        method.currency === 'BS'
          ? `Recibimos Bs ${amountCheck.received.toFixed(2)}. Faltan Bs ${newRemainingAmount.toFixed(2)} para completar el plan. Transfiere la diferencia e ingresa la nueva referencia.`
          : `Recibimos $${amountCheck.received.toFixed(2)} USDT. Faltan $${newRemainingAmount.toFixed(2)} USDT. Envía la diferencia e ingresa la nueva referencia.`,
    };
  }

  // Paso 3F: Pago completo aprobado -> consumir referencia, marcar orden y activar/extender Pro atómicamente.
  const linkLockKey = claimedOrder.paymentLinkId ? `link_${claimedOrder.paymentLinkId}` : null;
  let activation;
  try {
    activation = await applyPaidOrderAndActivatePro({
      db,
      orderRef,
      orderId,
      claimedOrder,
      uid,
      method,
      lockKey,
      linkLockKey,
      normalizedRef,
      amountCheck,
      amountVerifiedByProvider: verification.amountVerifiedByProvider === true,
      reconciledDuplicate,
      paymentDate: verification.paymentDate,
      activatedBy: isPaidViaOrderLink ? 'pabilo_link' : 'pabilo_auto',
      reconcileOrderId,
      nowMs,
    });
  } catch (err) {
    if (err instanceof ProPaymentError && err.code === 'REFERENCE_ALREADY_USED') {
      await releaseReferenceLock({ db, lockKey, orderId, orderStatus: 'awaiting_payment' });
      return {
        ok: false,
        httpStatus: 409,
        code: 'REFERENCE_ALREADY_USED',
        retryable: false,
        orderId,
        message: err.message,
      };
    }
    throw err;
  }

  if (activation.alreadyPaidOrder) {
    return {
      ok: true,
      httpStatus: 200,
      code: 'ALREADY_ACTIVATED',
      status: 'paid',
      orderId,
      subscription: activation.subscription,
      message: 'Tu suscripción Pro ya está activa para esta orden.',
    };
  }

  return {
    ok: true,
    httpStatus: 200,
    code: 'ACTIVATED',
    status: 'paid',
    orderId,
    reconciledDuplicate,
    subscription: activation.subscription,
    message: '¡Pago verificado automáticamente! Tu plan Pro ya está activo.',
  };
}

/**
 * Procesa webhooks de enlaces de pago de Pabilo (`link.paid`, etc.).
 * Reconsulta SIEMPRE `GET /paymentlink/{id}/info` antes de activar Pro.
 */
async function handlePabiloWebhook({
  db,
  rawBody,
  parsedBody,
  headers = {},
  fetchImpl = globalThis.fetch,
  env = process.env,
  runtimeSecrets = {},
  nowMs = Date.now(),
}) {
  const { secrets } = await loadPublicPaymentConfig({ db, env, runtimeSecrets });
  const signatureHeader = headers['x-pabilo-signature'] || headers['X-Pabilo-Signature'] || '';

  if (secrets.webhookSecret) {
    const validSig = verifyWebhookSignature({
      rawBody: rawBody !== undefined ? rawBody : parsedBody,
      signatureHeader,
      webhookSecret: secrets.webhookSecret,
    });
    if (!validSig) {
      await recordVerificationLog({
        db,
        entry: {
          source: 'pabiloWebhook',
          rejected: 'INVALID_SIGNATURE',
          hasSignature: Boolean(signatureHeader),
        },
      });
      return {
        ok: false,
        httpStatus: 401,
        code: 'INVALID_SIGNATURE',
        message: 'Firma X-Pabilo-Signature inválida.',
      };
    }
  }

  const body = parsedBody && typeof parsedBody === 'object' ? parsedBody : {};
  const data = body.data && typeof body.data === 'object' ? body.data : {};
  const ubp = data.user_bank_payment || body.user_bank_payment || null;
  const linkObj = data.payment_link || data.paymentlink || body.payment_link || body.paymentlink || null;

  const paymentLinkId = String(
    data.payment_link_id ||
      body.payment_link_id ||
      (linkObj && linkObj.id) ||
      (ubp && ubp.payment_link_id) ||
      '',
  ).trim();

  await recordVerificationLog({
    db,
    entry: {
      source: 'pabiloWebhook',
      eventType: body.eventType || body.event || null,
      eventId: body.eventId || null,
      paymentLinkId: paymentLinkId || null,
      payloadStatus: (ubp && ubp.status) || (linkObj && linkObj.status) || body.status || null,
      raw: body,
    },
  });

  if (!paymentLinkId) {
    return {
      ok: true,
      httpStatus: 200,
      ignored: true,
      code: 'IGNORED_NO_LINK_ID',
      message: 'Evento recibido sin payment_link_id.',
    };
  }

  const orderSnap = await db
    .collection('proOrders')
    .where('paymentLinkId', '==', paymentLinkId)
    .limit(5)
    .get();

  if (!orderSnap.docs.length) {
    return {
      ok: true,
      httpStatus: 200,
      ignored: true,
      code: 'ORDER_NOT_FOUND',
      paymentLinkId,
      message: 'No hay una orden asociada a este payment_link_id.',
    };
  }

  const orderDoc = orderSnap.docs[0];
  const orderId = orderDoc.id;
  const order = orderDoc.data() || {};

  if (order.status === 'paid') {
    const subSnap = await db.collection('users').doc(order.uid).collection('subscription').doc('current').get();
    return {
      ok: true,
      httpStatus: 200,
      code: 'ALREADY_ACTIVATED',
      orderId,
      subscription: subSnap.exists ? subSnap.data() : null,
      message: 'Orden ya pagada.',
    };
  }

  const method = PAYMENT_METHODS[order.method];
  if (!method || !secrets.apiKey) {
    return {
      ok: false,
      httpStatus: 500,
      code: 'CONFIGURATION_ERROR',
      orderId,
      message: 'Configuración incompleta para verificar enlace Pabilo.',
    };
  }

  // Fuente de verdad obligatoria: reconsultar GET /paymentlink/{id}/info en Pabilo
  const linkInfo = await getPaymentLinkInfo({
    baseUrl: secrets.baseUrl,
    apiKey: secrets.apiKey,
    paymentLinkId,
    fetchImpl,
  });

  await recordVerificationLog({
    db,
    entry: {
      source: 'pabiloWebhook_verifyLink',
      orderId,
      paymentLinkId,
      isPaid: linkInfo.isPaid,
      status: linkInfo.status,
      amount: linkInfo.amount,
      reference: linkInfo.reference,
      raw: linkInfo.raw || null,
    },
  });

  if (!linkInfo.ok || !linkInfo.isPaid) {
    return {
      ok: true,
      httpStatus: 200,
      code: 'LINK_NOT_PAID',
      orderId,
      paymentLinkId,
      status: linkInfo.status || 'pending',
      message: 'El enlace aún no está confirmado como pagado en Pabilo.',
    };
  }

  const reportedAmount = linkInfo.amount;
  if (reportedAmount === null || reportedAmount === undefined || Number(reportedAmount) <= 0) {
    return {
      ok: false,
      httpStatus: 422,
      code: 'UNREADABLE_AMOUNT',
      orderId,
      message: 'No se pudo confirmar el monto pagado del enlace en Pabilo.',
    };
  }

  const expectedTotal = Number(order.expectedTotal);
  const alreadyPaid = Number(order.paidAmount || 0);
  const pendingAmount = round(Math.max(0.01, expectedTotal - alreadyPaid), 2);
  const amountCheck = checkAmount(pendingAmount, reportedAmount);
  if (!amountCheck.ok && amountCheck.shortfall > 0) {
    return {
      ok: false,
      httpStatus: 409,
      code: 'INSUFFICIENT_AMOUNT',
      orderId,
      message: 'El monto del enlace pagado es menor al esperado del plan.',
    };
  }

  const rawRef = linkInfo.reference || (ubp && (ubp.bank_reference_id || ubp.reference)) || '';
  const normalizedRef = rawRef
    ? normalizeReference(rawRef, method.allowLetters) || `LINK_${paymentLinkId}`
    : `LINK_${paymentLinkId}`;

  if (rawRef) {
    const conflict = await findConflictingOrderWithReference({
      db,
      methodId: method.id,
      normalizedRef,
      excludeOrderId: orderId,
    });
    if (conflict) {
      return {
        ok: false,
        httpStatus: 409,
        code: 'REFERENCE_ALREADY_USED',
        orderId,
        message: 'La referencia del enlace ya fue consumida por otra orden.',
      };
    }
  }

  const lockKey = rawRef ? makeReferenceLockKey(method.id, normalizedRef) : null;
  const linkLockKey = `link_${paymentLinkId}`;
  const orderRef = db.collection('proOrders').doc(orderId);

  const activation = await applyPaidOrderAndActivatePro({
    db,
    orderRef,
    orderId,
    claimedOrder: order,
    uid: order.uid,
    method,
    lockKey,
    linkLockKey,
    normalizedRef,
    amountCheck,
    amountVerifiedByProvider: true,
    reconciledDuplicate: true,
    paymentDate: linkInfo.paymentDate,
    activatedBy: 'pabilo_webhook',
    nowMs,
  });

  return {
    ok: true,
    httpStatus: 200,
    code: activation.alreadyPaidOrder ? 'ALREADY_ACTIVATED' : 'ACTIVATED',
    status: 'paid',
    orderId,
    paymentLinkId,
    subscription: activation.subscription,
    message: 'Webhook procesado correctamente.',
  };
}

module.exports = {
  PRO_PLANS,
  PAYMENT_METHODS,
  ORDER_TTL_MS,
  MAX_VERIFY_ATTEMPTS,
  ProPaymentError,
  round,
  checkAmount,
  computeSubscriptionDates,
  makeReferenceLockKey,
  resolveAuthoritativeBcvRate,
  loadPublicPaymentConfig,
  checkRateLimit,
  getProPaymentConfigPayload,
  createProCheckout,
  findConflictingOrderWithReference,
  findReconcilableIncidentOrder,
  verifyProPayment,
  handlePabiloWebhook,
};
