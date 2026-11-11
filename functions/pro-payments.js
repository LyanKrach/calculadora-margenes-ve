'use strict';

const crypto = require('crypto');
const { verifyPayment, getExchangeRate, normalizeReference } = require('./pabilo');

const ADMIN_EMAILS = Object.freeze([
  'layankrach@gmail.com',
  'soporterefillstore@gmail.com',
]);

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
    priceUsd: 15.99,
    durationDays: 365,
    savePercent: 33,
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
    label: 'USDT / Binance Pay',
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

  const pmDoc = (fsPublic.pagoMovil && typeof fsPublic.pagoMovil === 'object' ? fsPublic.pagoMovil : {});
  const usdtDoc = (fsPublic.usdt && typeof fsPublic.usdt === 'object' ? fsPublic.usdt : {});
  const supportDoc = (fsPublic.support && typeof fsPublic.support === 'object' ? fsPublic.support : {});

  const publicConfig = {
    pagoMovil: {
      bank: String(pmDoc.banco || pmDoc.bank || env.PRO_PM_BANK || '').trim(),
      cedulaRif: String(pmDoc.cedulaRif || env.PRO_PM_CEDULA || '').trim(),
      phone: String(pmDoc.telefono || pmDoc.phone || env.PRO_PM_PHONE || '').trim(),
      holder: String(pmDoc.titular || pmDoc.holder || env.PRO_PM_HOLDER || '').trim(),
      autoVerify: Boolean(apiKey && pmBankId),
    },
    usdt: {
      network: String(usdtDoc.red || usdtDoc.network || env.PRO_USDT_NETWORK || 'Binance Pay / TRC20').trim(),
      binanceId: String(usdtDoc.binanceId || env.PRO_BINANCE_PAY_ID || '').trim(),
      address: String(usdtDoc.direccion || usdtDoc.address || env.PRO_USDT_ADDRESS || '').trim(),
      autoVerify: Boolean(apiKey && binanceBankId),
    },
    support: {
      email: String(supportDoc.email || env.PRO_SUPPORT_EMAIL || '').trim(),
      whatsapp: String(supportDoc.whatsapp || env.PRO_SUPPORT_WHATSAPP || '').trim(),
    },
  };

  return {
    publicConfig,
    secrets: {
      apiKey,
      pmBankId,
      binanceBankId,
      baseUrl,
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
    lastAttemptedReference: null,
    providerErrorAt: null,
    retriableRefs: [],
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

async function releaseReferenceLock({ db, lockKey, orderId, orderStatus = 'awaiting_payment', extraOrderPatch = {} }) {
  const lockRef = db.collection('paymentRefs').doc(lockKey);
  const orderRef = db.collection('proOrders').doc(orderId);
  await db.runTransaction(async (tx) => {
    const lockSnap = await tx.get(lockRef);
    if (lockSnap.exists && lockSnap.data() && lockSnap.data().orderId === orderId) {
      const lockStatus = lockSnap.data().status;
      if (lockStatus === 'verifying') {
        tx.delete(lockRef);
      }
    }
    tx.set(
      orderRef,
      {
        status: orderStatus,
        updatedAt: new Date().toISOString(),
        ...extraOrderPatch,
      },
      { merge: true },
    );
  });
}

async function verifyProPayment({
  db,
  uid,
  orderId,
  rawReference,
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

  const lockKey = makeReferenceLockKey(method.id, normalizedRef);
  const lockRef = db.collection('paymentRefs').doc(lockKey);
  const orderRef = db.collection('proOrders').doc(orderId);
  const nowIso = new Date(nowMs).toISOString();

  // Paso 1: Reclamación transaccional de la referencia antes de consultar Pabilo.
  let claimedOrder;
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
      throw new ProPaymentError(
        409,
        'VERIFY_IN_PROGRESS',
        'Ya estamos verificando un pago en esta orden. Espera unos segundos.',
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
      updatedAt: nowIso,
    });

    claimedOrder = { ...order, attempts: attempts + 1 };
  });

  // Paso 2: Consultar Pabilo por el monto pendiente exacto.
  const expectedTotal = Number(claimedOrder.expectedTotal);
  const alreadyPaid = Number(claimedOrder.paidAmount || 0);
  const pendingAmount = round(Math.max(0.01, expectedTotal - alreadyPaid), 2);

  const verification = await verifyPayment({
    baseUrl: secrets.baseUrl,
    apiKey: secrets.apiKey,
    userBankId: bankId,
    bankReference: normalizedRef,
    amount: pendingAmount,
    fetchImpl,
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
      message: verification.message || 'No encontramos un pago con esa referencia todavía. Si acabas de transferir, espera 15 segundos y vuelve a verificar.',
    };
  }

  // Paso 3C: `is_new: false` -> verificar si es una reconciliación legítima del propio usuario tras timeout.
  let reconciledDuplicate = false;
  if (!verification.isNew) {
    const conflictingOrder = await findConflictingOrderWithReference({
      db,
      methodId: method.id,
      normalizedRef,
      excludeOrderId: orderId,
    });
    const retriableRefs = Array.isArray(claimedOrder.retriableRefs) ? claimedOrder.retriableRefs : [];
    const isSelfRetryAfterError =
      (claimedOrder.lastAttemptedReference === normalizedRef && Boolean(claimedOrder.providerErrorAt)) ||
      retriableRefs.includes(normalizedRef);

    if (conflictingOrder || !isSelfRetryAfterError) {
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

  // Paso 3D: Verificación estricta de monto (fallback sin `amount` nunca aprueba sin reportedAmount).
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

  // Paso 3E: Pago parcial -> conservar lock sobre esta referencia, acumular `paidAmount` y extender vigencia 30m.
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
  const plan = PRO_PLANS[claimedOrder.plan] || PRO_PLANS.monthly;
  const subCurrentRef = db.collection('users').doc(uid).collection('subscription').doc('current');
  const subPendingRef = db.collection('users').doc(uid).collection('subscription').doc('pending');

  let activatedSub;
  await db.runTransaction(async (tx) => {
    const [subSnap, pendingSnap] = await Promise.all([tx.get(subCurrentRef), tx.get(subPendingRef)]);
    const existingSub = subSnap.exists ? subSnap.data() : null;
    const { startDate, endDate, nowIso: activatedAt } = computeSubscriptionDates({
      existingSub,
      durationDays: Number(claimedOrder.durationDays || plan.durationDays),
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
      amountUsd: Number(claimedOrder.expectedAmountUsd || plan.priceUsd),
      paidAmount: totalPaid,
      currency: method.currency,
      overpaidAlert: amountCheck.overpaidAlert,
      activatedBy: 'pabilo_auto',
      updatedAt: activatedAt,
    };

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

    tx.update(orderRef, {
      status: 'paid',
      paidAmount: totalPaid,
      remainingAmount: 0,
      paidAt: activatedAt,
      lastAttemptedReference: null,
      providerErrorAt: null,
      payment: {
        reference: normalizedRef,
        provider: method.providerId,
        reportedAmount: amountCheck.received,
        overpaid: amountCheck.overpaid,
        overpaidAlert: amountCheck.overpaidAlert,
        amountVerifiedByProvider: verification.amountVerifiedByProvider === true,
        reconciledDuplicate,
        paymentDate: verification.paymentDate || null,
        paidAt: activatedAt,
      },
      updatedAt: activatedAt,
    });

    tx.set(subCurrentRef, activatedSub);
    if (pendingSnap.exists) {
      tx.delete(subPendingRef);
    }
  });

  return {
    ok: true,
    httpStatus: 200,
    code: 'ACTIVATED',
    status: 'paid',
    orderId,
    reconciledDuplicate,
    subscription: activatedSub,
    message: '¡Pago verificado automáticamente! Tu plan Pro ya está activo.',
  };
}

function normalizeEmail(raw) {
  return String(raw || '').trim().toLowerCase();
}

function isOwnerEmail(email) {
  return ADMIN_EMAILS.includes(normalizeEmail(email));
}

function isAdminDecodedToken(decoded) {
  if (!decoded || typeof decoded !== 'object') return false;
  if (decoded.admin === true) return true;
  const email = normalizeEmail(decoded.email);
  return decoded.email_verified === true && ADMIN_EMAILS.includes(email);
}

function summarizeSubForAdmin(currentSub, nowMs = Date.now()) {
  if (!currentSub || typeof currentSub !== 'object') {
    return {
      isPro: false,
      status: 'free',
      plan: null,
      startDate: null,
      endDate: null,
      daysLeft: 0,
      provider: null,
      paymentRef: null,
      note: null,
      activatedBy: null,
    };
  }
  const rawStatus = String(currentSub.status || '').trim().toLowerCase();
  const endMs = currentSub.endDate ? Date.parse(String(currentSub.endDate)) : NaN;
  const isPro = rawStatus === 'active' && Number.isFinite(endMs) && endMs > nowMs;
  const daysLeft = isPro ? Math.max(1, Math.ceil((endMs - nowMs) / 86_400_000)) : 0;
  const effectiveStatus = isPro
    ? 'active'
    : rawStatus === 'canceled'
      ? 'canceled'
      : rawStatus === 'active' || rawStatus === 'expired'
        ? 'expired'
        : 'free';

  return {
    isPro,
    status: effectiveStatus,
    plan: currentSub.plan || null,
    startDate: currentSub.startDate || null,
    endDate: currentSub.endDate || null,
    daysLeft,
    provider: currentSub.provider || null,
    paymentRef: currentSub.paymentRef || null,
    note: currentSub.note || null,
    activatedBy: currentSub.activatedBy || null,
    updatedAt: currentSub.updatedAt || null,
  };
}

function buildAdminUserRecord({ authUser, currentSub, pendingSub, nowMs = Date.now() }) {
  const email = String((authUser && authUser.email) || '');
  const summary = summarizeSubForAdmin(currentSub, nowMs);
  return {
    uid: authUser.uid,
    email,
    displayName: String((authUser && authUser.displayName) || ''),
    emailVerified: Boolean(authUser && authUser.emailVerified),
    createdAt: (authUser && authUser.metadata && authUser.metadata.creationTime) || null,
    lastSignInAt: (authUser && authUser.metadata && authUser.metadata.lastSignInTime) || null,
    isOwner: isOwnerEmail(email),
    isPro: summary.isPro,
    status: summary.status,
    plan: summary.plan,
    startDate: summary.startDate,
    endDate: summary.endDate,
    daysLeft: summary.daysLeft,
    provider: summary.provider,
    paymentRef: summary.paymentRef,
    note: summary.note,
    activatedBy: summary.activatedBy,
    pending: pendingSub && pendingSub.status === 'pending' ? pendingSub : null,
  };
}

async function readSubsBatch(db, uids) {
  if (!uids.length) return new Map();
  const refs = [];
  for (const uid of uids) {
    refs.push(db.collection('users').doc(uid).collection('subscription').doc('current'));
    refs.push(db.collection('users').doc(uid).collection('subscription').doc('pending'));
  }
  const snaps =
    typeof db.getAll === 'function'
      ? await db.getAll(...refs)
      : await Promise.all(refs.map((ref) => ref.get()));

  const map = new Map();
  for (let i = 0; i < uids.length; i++) {
    const curSnap = snaps[i * 2];
    const pendSnap = snaps[i * 2 + 1];
    map.set(uids[i], {
      current: curSnap && curSnap.exists ? curSnap.data() : null,
      pending: pendSnap && pendSnap.exists ? pendSnap.data() : null,
    });
  }
  return map;
}

async function resolveTargetAuthUser({ auth, uid, email }) {
  if (uid && typeof uid === 'string' && uid.trim()) {
    try {
      return await auth.getUser(uid.trim());
    } catch {
      throw new ProPaymentError(404, 'USER_NOT_FOUND', 'No encontramos ese usuario por UID.');
    }
  }
  const cleanEmail = normalizeEmail(email);
  if (!cleanEmail || !cleanEmail.includes('@')) {
    throw new ProPaymentError(400, 'INVALID_EMAIL', 'Escribe un correo electrónico válido.');
  }
  try {
    return await auth.getUserByEmail(cleanEmail);
  } catch {
    throw new ProPaymentError(
      404,
      'USER_NOT_FOUND',
      `No encontramos una cuenta registrada con el correo ${cleanEmail}. Pídele que inicie sesión primero al menos una vez.`,
    );
  }
}

async function adminSetUserPro({
  auth,
  db,
  uid,
  email,
  planId = 'monthly',
  durationDays,
  extend = false,
  note = '',
  adminEmail = '',
  provider = 'admin_panel',
  nowMs = Date.now(),
}) {
  const authUser = await resolveTargetAuthUser({ auth, uid, email });
  const chosenPlanId = PRO_PLANS[planId] ? planId : 'monthly';
  const plan = PRO_PLANS[chosenPlanId];

  let days = plan.durationDays;
  if (durationDays !== undefined && durationDays !== null && durationDays !== '') {
    const parsedDays = Math.round(Number(durationDays));
    if (!Number.isFinite(parsedDays) || parsedDays < 1 || parsedDays > 3650) {
      throw new ProPaymentError(
        400,
        'INVALID_DURATION',
        'La duración personalizada debe estar entre 1 y 3650 días.',
      );
    }
    days = parsedDays;
  }

  const targetUid = authUser.uid;
  const subCurrentRef = db.collection('users').doc(targetUid).collection('subscription').doc('current');
  const subPendingRef = db.collection('users').doc(targetUid).collection('subscription').doc('pending');
  const userDocRef = db.collection('users').doc(targetUid);
  const cleanNote = String(note || '').trim().slice(0, 160);
  const cleanAdmin = normalizeEmail(adminEmail) || 'admin';

  let nextSub;
  await db.runTransaction(async (tx) => {
    const [subSnap, pendSnap] = await Promise.all([tx.get(subCurrentRef), tx.get(subPendingRef)]);
    const existingSub = subSnap.exists ? subSnap.data() : null;
    const nowDate = new Date(nowMs);
    const nowIso = nowDate.toISOString();

    let startDate = nowIso;
    let endDate = new Date(nowMs + days * 86_400_000).toISOString();
    if (extend) {
      const computed = computeSubscriptionDates({
        existingSub,
        durationDays: days,
        nowMs,
      });
      startDate = computed.startDate;
      endDate = computed.endDate;
    }

    nextSub = {
      v: 1,
      plan: plan.id,
      status: 'active',
      startDate,
      endDate,
      provider: String(provider || 'admin_panel'),
      paymentRef: cleanNote || (existingSub && existingSub.paymentRef) || 'ADMIN',
      amountUsd: 0,
      durationDays: days,
      note: cleanNote,
      activatedBy: cleanAdmin,
      updatedAt: nowIso,
    };

    tx.set(subCurrentRef, nextSub);
    if (pendSnap.exists) {
      tx.delete(subPendingRef);
    }
    tx.set(
      userDocRef,
      {
        email: normalizeEmail(authUser.email),
        displayName: String(authUser.displayName || ''),
        updatedAt: nowIso,
      },
      { merge: true },
    );
  });

  return {
    ok: true,
    code: 'PRO_ACTIVATED',
    user: buildAdminUserRecord({
      authUser,
      currentSub: nextSub,
      pendingSub: null,
      nowMs,
    }),
    message: `Pro (${plan.name}, ${days} días) activado para ${authUser.email || targetUid}.`,
  };
}

async function adminDeactivateUserPro({
  auth,
  db,
  uid,
  email,
  note = '',
  adminEmail = '',
  nowMs = Date.now(),
}) {
  const authUser = await resolveTargetAuthUser({ auth, uid, email });
  const targetUid = authUser.uid;
  const subCurrentRef = db.collection('users').doc(targetUid).collection('subscription').doc('current');
  const subPendingRef = db.collection('users').doc(targetUid).collection('subscription').doc('pending');
  const cleanNote = String(note || '').trim().slice(0, 160);
  const cleanAdmin = normalizeEmail(adminEmail) || 'admin';
  const nowIso = new Date(nowMs).toISOString();

  let canceledSub;
  await db.runTransaction(async (tx) => {
    const [subSnap, pendSnap] = await Promise.all([tx.get(subCurrentRef), tx.get(subPendingRef)]);
    const existingSub = subSnap.exists ? subSnap.data() : null;
    const prevPlan = existingSub && PRO_PLANS[existingSub.plan] ? existingSub.plan : 'monthly';
    canceledSub = {
      v: 1,
      plan: prevPlan,
      status: 'canceled',
      startDate: (existingSub && existingSub.startDate) || nowIso,
      endDate: nowIso,
      provider: 'admin_panel',
      paymentRef: (existingSub && existingSub.paymentRef) || 'ADMIN_REVOKED',
      amountUsd: 0,
      note: cleanNote,
      activatedBy: cleanAdmin,
      updatedAt: nowIso,
    };
    tx.set(subCurrentRef, canceledSub);
    if (pendSnap.exists) {
      tx.delete(subPendingRef);
    }
  });

  return {
    ok: true,
    code: 'PRO_DEACTIVATED',
    user: buildAdminUserRecord({
      authUser,
      currentSub: canceledSub,
      pendingSub: null,
      nowMs,
    }),
    message: `Suscripción Pro desactivada para ${authUser.email || targetUid}.`,
  };
}

async function adminBootstrapOwners({
  auth,
  db,
  durationDays = 3650,
  nowMs = Date.now(),
}) {
  const results = [];
  for (const ownerEmail of ADMIN_EMAILS) {
    let authUser = null;
    try {
      authUser = await auth.getUserByEmail(ownerEmail);
    } catch {
      results.push({ email: ownerEmail, status: 'not_registered_yet' });
      continue;
    }
    const existingSnap = await db
      .collection('users')
      .doc(authUser.uid)
      .collection('subscription')
      .doc('current')
      .get();
    const existingSummary = summarizeSubForAdmin(
      existingSnap.exists ? existingSnap.data() : null,
      nowMs,
    );
    if (existingSummary.isPro && existingSummary.plan === 'annual' && existingSummary.daysLeft >= 300) {
      results.push({
        email: ownerEmail,
        uid: authUser.uid,
        status: 'already_active',
        daysLeft: existingSummary.daysLeft,
      });
      continue;
    }
    await adminSetUserPro({
      auth,
      db,
      uid: authUser.uid,
      email: ownerEmail,
      planId: 'annual',
      durationDays,
      extend: false,
      note: 'Cuenta propietaria',
      adminEmail: 'system_owner_bootstrap',
      provider: 'admin_owner',
      nowMs,
    });
    results.push({ email: ownerEmail, uid: authUser.uid, status: 'activated', daysLeft: durationDays });
  }
  return { ok: true, owners: results };
}

async function adminLookupUserByEmail({ auth, db, email, nowMs = Date.now() }) {
  const authUser = await resolveTargetAuthUser({ auth, email });
  const subMap = await readSubsBatch(db, [authUser.uid]);
  const entry = subMap.get(authUser.uid) || { current: null, pending: null };
  return {
    ok: true,
    user: buildAdminUserRecord({
      authUser,
      currentSub: entry.current,
      pendingSub: entry.pending,
      nowMs,
    }),
  };
}

async function adminListOverview({
  auth,
  db,
  limit = 100,
  ensureOwners = true,
  nowMs = Date.now(),
}) {
  if (ensureOwners) {
    await adminBootstrapOwners({ auth, db, nowMs });
  }
  const safeLimit = Math.min(Math.max(Number(limit) || 100, 1), 200);
  const listRes = await auth.listUsers(safeLimit);
  const authUsers = (listRes && Array.isArray(listRes.users) ? listRes.users : []).filter(
    (u) => u && !u.disabled && (u.email || '').trim().length > 0,
  );
  const subMap = await readSubsBatch(
    db,
    authUsers.map((u) => u.uid),
  );
  const users = authUsers.map((authUser) => {
    const entry = subMap.get(authUser.uid) || { current: null, pending: null };
    return buildAdminUserRecord({
      authUser,
      currentSub: entry.current,
      pendingSub: entry.pending,
      nowMs,
    });
  });

  users.sort((a, b) => {
    const aPend = a.pending ? 1 : 0;
    const bPend = b.pending ? 1 : 0;
    if (aPend !== bPend) return bPend - aPend;
    if (a.isPro !== b.isPro) return (b.isPro ? 1 : 0) - (a.isPro ? 1 : 0);
    if (a.isOwner !== b.isOwner) return (b.isOwner ? 1 : 0) - (a.isOwner ? 1 : 0);
    return String(b.lastSignInAt || b.createdAt || '').localeCompare(
      String(a.lastSignInAt || a.createdAt || ''),
    );
  });

  let activePro = 0;
  let pendingManual = 0;
  for (const u of users) {
    if (u.isPro) activePro += 1;
    if (u.pending) pendingManual += 1;
  }

  return {
    ok: true,
    ownerEmails: [...ADMIN_EMAILS],
    plans: Object.values(PRO_PLANS),
    stats: {
      totalUsers: users.length,
      activePro,
      pendingManual,
    },
    users,
  };
}

module.exports = {
  ADMIN_EMAILS,
  PRO_PLANS,
  PAYMENT_METHODS,
  ORDER_TTL_MS,
  MAX_VERIFY_ATTEMPTS,
  ProPaymentError,
  round,
  normalizeEmail,
  isOwnerEmail,
  isAdminDecodedToken,
  checkAmount,
  computeSubscriptionDates,
  makeReferenceLockKey,
  resolveAuthoritativeBcvRate,
  loadPublicPaymentConfig,
  checkRateLimit,
  getProPaymentConfigPayload,
  createProCheckout,
  findConflictingOrderWithReference,
  verifyProPayment,
  adminListOverview,
  adminLookupUserByEmail,
  adminSetUserPro,
  adminDeactivateUserPro,
  adminBootstrapOwners,
};
