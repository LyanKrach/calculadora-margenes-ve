'use strict';

const crypto = require('crypto');

const DEFAULT_PABILO_BASE_URL = 'https://api.pabilo.app';
const DEFAULT_VERIFY_TIMEOUT_MS = 45_000;
const DEFAULT_RATE_TIMEOUT_MS = 10_000;
const DEFAULT_LINK_TIMEOUT_MS = 15_000;

function normalizeBaseUrl(raw) {
  const base = String(raw || DEFAULT_PABILO_BASE_URL).trim();
  return (base || DEFAULT_PABILO_BASE_URL).replace(/\/+$/, '');
}

/**
 * Devuelve la fecha en formato YYYY-MM-DD en zona horaria America/Caracas.
 */
function getCaracasDateString(nowMs = Date.now(), offsetDays = 0) {
  const target = new Date(nowMs + offsetDays * 86_400_000);
  try {
    return new Intl.DateTimeFormat('en-CA', {
      timeZone: 'America/Caracas',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    }).format(target);
  } catch {
    return new Date(target.getTime() - 4 * 3600_000).toISOString().slice(0, 10);
  }
}

/**
 * Normaliza una referencia de pago para evitar discrepancias de espacios/guiones.
 * - Pago Móvil (allowLetters = false): solo dígitos.
 * - Binance Pay / USDT (allowLetters = true): alfanumérico en mayúsculas.
 */
function normalizeReference(raw, allowLetters = false) {
  const s = String(raw || '').trim();
  return allowLetters
    ? s.toUpperCase().replace(/[^A-Z0-9]/g, '')
    : s.replace(/\D/g, '');
}

/**
 * Convierte montos numéricos o en texto (formato internacional o venezolano) a número finito.
 */
function parseFiniteNumber(raw) {
  if (typeof raw === 'number') {
    return Number.isFinite(raw) ? raw : null;
  }
  if (typeof raw === 'string') {
    let s = raw.trim().replace(/[^\d.,-]/g, '');
    if (!s) return null;
    const lastComma = s.lastIndexOf(',');
    const lastDot = s.lastIndexOf('.');
    if (lastComma > -1 && lastDot > -1) {
      s = lastComma > lastDot ? s.replace(/\./g, '').replace(',', '.') : s.replace(/,/g, '');
    } else if (lastComma > -1) {
      const parts = s.split(',');
      const isThousands = parts.length > 2 || (parts.length === 2 && parts[1].length === 3);
      s = isThousands ? parts.join('') : parts.join('.');
    }
    const n = Number(s);
    return Number.isFinite(n) ? n : null;
  }
  return null;
}

/**
 * Extrae de forma unificada los campos de un movimiento de Pabilo tanto cuando
 * la respuesta viene en el nivel raíz (pago nuevo `is_new: true`:
 * `{ user_bank_payment: {...}, is_new: true, credit_cost: 1, payment_date: "..." }`)
 * como cuando viene envuelta en `.data` (pago ya verificado `is_new: false`:
 * `{ data: { is_new: false, credit_cost: 0, user_bank_payment: {...}, payment_date: "..." } }`)
 * o en formato simplificado de pruebas (`{ is_new: true, data: { amount, date } }`).
 */
function extractPaymentPayload(rawBody) {
  if (!rawBody || typeof rawBody !== 'object') {
    return {
      hasMovement: false,
      isNew: false,
      reportedAmount: null,
      creditCost: null,
      paymentDate: null,
      paymentStatus: null,
      paymentId: null,
      paymentLinkId: null,
      bankReferenceId: null,
    };
  }

  const top = rawBody;
  const inner = top.data && typeof top.data === 'object' ? top.data : {};
  const ubp =
    (inner.user_bank_payment && typeof inner.user_bank_payment === 'object' && inner.user_bank_payment) ||
    (inner.userBankPayment && typeof inner.userBankPayment === 'object' && inner.userBankPayment) ||
    (top.user_bank_payment && typeof top.user_bank_payment === 'object' && top.user_bank_payment) ||
    (top.userBankPayment && typeof top.userBankPayment === 'object' && top.userBankPayment) ||
    null;

  const hasUbp = Boolean(
    ubp &&
      (ubp.amount !== undefined ||
        ubp.id !== undefined ||
        ubp.bank_reference_id !== undefined ||
        ubp.reference !== undefined ||
        ubp.status !== undefined),
  );
  const hasInnerData = Boolean(
    top.data &&
      typeof top.data === 'object' &&
      (inner.amount !== undefined ||
        inner.date !== undefined ||
        inner.payment_date !== undefined ||
        typeof inner.is_new === 'boolean'),
  );
  const hasTopFields = Boolean(
    typeof top.is_new === 'boolean' &&
      (top.amount !== undefined || top.payment_date !== undefined || hasUbp),
  );

  const hasMovement = hasUbp || hasInnerData || hasTopFields;

  let isNew = false;
  if (top.is_new === false || inner.is_new === false || (ubp && ubp.is_new === false)) {
    isNew = false;
  } else if (top.is_new === true || inner.is_new === true || (ubp && ubp.is_new === true)) {
    isNew = true;
  }

  const amountCandidates = [ubp && ubp.amount, inner.amount, top.amount];
  let reportedAmount = null;
  for (const val of amountCandidates) {
    const num = parseFiniteNumber(val);
    if (num !== null) {
      reportedAmount = num;
      break;
    }
  }

  const creditCandidates = [top.credit_cost, inner.credit_cost, ubp && ubp.credit_cost];
  let creditCost = null;
  for (const val of creditCandidates) {
    const num = parseFiniteNumber(val);
    if (num !== null) {
      creditCost = num;
      break;
    }
  }
  if (creditCost === null && hasMovement) {
    creditCost = isNew ? 1 : 0;
  }

  const dateCandidate =
    top.payment_date ||
    inner.payment_date ||
    (ubp && (ubp.payment_date || ubp.date)) ||
    inner.date ||
    top.date ||
    (ubp && ubp.created_at ? String(ubp.created_at).slice(0, 10) : null) ||
    null;
  const paymentDate = dateCandidate ? String(dateCandidate) : null;

  const paymentStatus =
    (ubp && ubp.status) || inner.status || (typeof top.status === 'string' ? top.status : null) || null;
  const paymentId = (ubp && ubp.id) || inner.id || null;
  const paymentLinkId =
    (ubp && (ubp.payment_link_id || ubp.paymentLinkId)) ||
    inner.payment_link_id ||
    inner.paymentLinkId ||
    top.payment_link_id ||
    top.paymentLinkId ||
    null;
  const bankReferenceId =
    (ubp && (ubp.bank_reference_id || ubp.reference)) ||
    inner.bank_reference_id ||
    inner.reference ||
    null;

  return {
    hasMovement,
    isNew,
    reportedAmount,
    creditCost,
    paymentDate,
    paymentStatus: paymentStatus ? String(paymentStatus) : null,
    paymentId: paymentId ? String(paymentId) : null,
    paymentLinkId: paymentLinkId ? String(paymentLinkId) : null,
    bankReferenceId: bankReferenceId ? String(bankReferenceId) : null,
  };
}

function extractAmount(data) {
  return extractPaymentPayload(data).reportedAmount;
}

function extractDate(data) {
  return extractPaymentPayload(data).paymentDate;
}

function isUnknownBankAccount(status, rawText) {
  return status >= 400 && /user_?bank not found/i.test(String(rawText || ''));
}

function isRetryableStatus(status) {
  return status === 408 || status === 429 || status >= 500;
}

function isRouteNotFound(status, data, rawText) {
  if (status !== 404) return false;
  const errCode = String((data && (data.error || data.code)) || '');
  if (/PAYMENT_NOT_FOUND/i.test(errCode) || /movement not found/i.test(String(rawText || ''))) {
    return false;
  }
  return /PAGE_NOT_FOUND|page not found|cannot post/i.test(String(rawText || '')) || !data;
}

function isNotFoundResponse(status, data) {
  if (status === 400 || status === 404 || status === 422) return true;
  if (status >= 200 && status < 300) {
    return !extractPaymentPayload(data).hasMovement;
  }
  return false;
}

/**
 * Ejecuta una petición POST única (retries: 0, timeout 45s) contra Betaserio:
 * `POST /userbankpayment/{userBankId}/betaserio`.
 * Si responde 404 de ruta inexistente (`PAGE_NOT_FOUND`), prueba el endpoint
 * alternativo `/v1/verify-payments/{userBankId}`.
 */
async function postBetaserio({
  baseUrl,
  apiKey,
  userBankId,
  bankReference,
  amount,
  movementType = 'GENERIC',
  fechaPago = null,
  fetchImpl = globalThis.fetch,
  timeoutMs = DEFAULT_VERIFY_TIMEOUT_MS,
}) {
  const cleanBase = normalizeBaseUrl(baseUrl);
  const encodedBankId = encodeURIComponent(String(userBankId).trim());
  const primaryUrl = `${cleanBase}/userbankpayment/${encodedBankId}/betaserio`;
  const fallbackUrl = `${cleanBase}/v1/verify-payments/${encodedBankId}`;

  const body = {
    bank_reference: bankReference,
    movement_type: movementType || 'GENERIC',
  };
  if (amount !== undefined && amount !== null) {
    body.amount = Number(Number(amount).toFixed(2));
  }
  if (fechaPago) {
    body.fecha_pago = String(fechaPago);
  }

  async function executeSinglePost(url) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const res = await fetchImpl(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${apiKey}`,
          appKey: apiKey,
        },
        body: JSON.stringify(body),
        signal: controller.signal,
      });
      const rawText = await res.text();
      let data = null;
      if (rawText) {
        try {
          data = JSON.parse(rawText);
        } catch {
          data = null;
        }
      }
      return {
        ok: res.ok,
        status: res.status,
        data,
        rawText,
        endpoint: url,
        networkError: false,
        timedOut: false,
      };
    } catch (err) {
      const isAbort = err && (err.name === 'AbortError' || /abort/i.test(String(err.message)));
      return {
        ok: false,
        status: 0,
        data: null,
        rawText: err ? String(err.message || err) : 'Network error',
        endpoint: url,
        networkError: true,
        timedOut: isAbort,
      };
    } finally {
      clearTimeout(timer);
    }
  }

  const primaryRes = await executeSinglePost(primaryUrl);
  if (isRouteNotFound(primaryRes.status, primaryRes.data, primaryRes.rawText)) {
    return executeSinglePost(fallbackUrl);
  }
  return primaryRes;
}

/**
 * Registra en consola cada intento de verificación con referencia, monto,
 * `is_new`, `credit_cost`, `payment_date` y respuesta completa para auditoría.
 */
function logVerificationResult({
  bankReference,
  userBankId,
  requestedAmount,
  fechaPago,
  response,
  parsed,
}) {
  try {
    console.log(
      JSON.stringify({
        event: 'pabilo_verify',
        reference: bankReference,
        userBankIdSuffix: String(userBankId || '').slice(-6),
        requestedAmount,
        fecha_pago: fechaPago || null,
        httpStatus: response ? response.status : 0,
        endpoint: response ? response.endpoint : null,
        found: Boolean(parsed && parsed.hasMovement),
        is_new: parsed ? parsed.isNew : null,
        amount: parsed ? parsed.reportedAmount : null,
        credit_cost: parsed ? parsed.creditCost : null,
        payment_date: parsed ? parsed.paymentDate : null,
        payment_status: parsed ? parsed.paymentStatus : null,
        raw: response ? response.data || response.rawText : null,
      }),
    );
  } catch {
    // Ignorar fallos de serialización en log
  }
}

/**
 * Verifica un pago en Pabilo (`POST /userbankpayment/{userBankId}/betaserio`):
 * 1) Envía `movement_type: "GENERIC"`, `amount: 0` y `fecha_pago` (YYYY-MM-DD Caracas)
 *    para que Pabilo busque por referencia sin descartar montos con diferencia de céntimos,
 *    y el servidor compare `reportedAmount >= expectedAmount`.
 * 2) Si la primera consulta devuelve el movimiento (200 OK con `user_bank_payment` en raíz
 *    o en `.data`), detiene la búsqueda de inmediato sin hacer una segunda llamada.
 * 3) Solo si responde no encontrado (400/404/422, p. ej. cuenta Jurídica que exige `amount > 0`),
 *    repite con el `amount` esperado.
 */
async function verifyPayment(params) {
  const {
    baseUrl,
    apiKey,
    userBankId,
    bankReference,
    amount = null,
    fechaPago = null,
    nowMs = Date.now(),
    fetchImpl = globalThis.fetch,
    timeoutMs = DEFAULT_VERIFY_TIMEOUT_MS,
  } = params || {};

  if (!apiKey || !userBankId) {
    return {
      configured: false,
      found: false,
      isNew: false,
      providerError: false,
      message: 'Pabilo no está configurado para este método de pago.',
    };
  }

  const normalizedRef = String(bankReference || '').trim();
  if (!normalizedRef) {
    return {
      configured: true,
      found: false,
      isNew: false,
      providerError: false,
      message: 'Debes indicar la referencia bancaria.',
    };
  }

  const resolvedFechaPago = fechaPago || getCaracasDateString(nowMs, 0);

  // Paso 1: Consulta por referencia con amount: 0 y movement_type: "GENERIC"
  const first = await postBetaserio({
    baseUrl,
    apiKey,
    userBankId,
    bankReference: normalizedRef,
    amount: 0,
    movementType: 'GENERIC',
    fechaPago: resolvedFechaPago,
    fetchImpl,
    timeoutMs,
  });

  const firstParsed = extractPaymentPayload(first.data);
  logVerificationResult({
    bankReference: normalizedRef,
    userBankId,
    requestedAmount: 0,
    fechaPago: resolvedFechaPago,
    response: first,
    parsed: firstParsed,
  });

  if (first.ok && firstParsed.hasMovement) {
    if (firstParsed.reportedAmount === null || firstParsed.reportedAmount <= 0) {
      return {
        configured: true,
        found: true,
        isNew: firstParsed.isNew,
        creditCost: firstParsed.creditCost,
        amountVerifiedByProvider: false,
        reportedAmount: null,
        unreadableAmount: true,
        paymentDate: firstParsed.paymentDate,
        paymentStatus: firstParsed.paymentStatus,
        paymentId: firstParsed.paymentId,
        paymentLinkId: firstParsed.paymentLinkId,
        providerError: false,
        endpoint: first.endpoint,
        message: 'Encontramos la referencia pero no pudimos leer el monto reportado por el banco.',
        raw: first.data,
      };
    }
    return {
      configured: true,
      found: true,
      isNew: firstParsed.isNew,
      creditCost: firstParsed.creditCost,
      amountVerifiedByProvider: false,
      reportedAmount: firstParsed.reportedAmount,
      paymentDate: firstParsed.paymentDate,
      paymentStatus: firstParsed.paymentStatus,
      paymentId: firstParsed.paymentId,
      paymentLinkId: firstParsed.paymentLinkId,
      providerError: false,
      endpoint: first.endpoint,
      message: (first.data && first.data.message) || 'Pago encontrado.',
      raw: first.data,
    };
  }

  if (isUnknownBankAccount(first.status, first.rawText)) {
    return {
      configured: true,
      found: false,
      isNew: false,
      providerError: true,
      unknownBankAccount: true,
      status: first.status,
      message: 'Cuenta bancaria en Pabilo no encontrada (user_bank not found).',
    };
  }

  // Paso 2 (respaldo): Si el banco exige monto explícito (ej. BDV Jurídico) y se indicó `amount > 0`,
  // probamos enviando el monto esperado exacto.
  if (
    amount !== null &&
    amount !== undefined &&
    Number(amount) > 0 &&
    !first.networkError &&
    isNotFoundResponse(first.status, first.data)
  ) {
    const second = await postBetaserio({
      baseUrl,
      apiKey,
      userBankId,
      bankReference: normalizedRef,
      amount,
      movementType: 'GENERIC',
      fechaPago: resolvedFechaPago,
      fetchImpl,
      timeoutMs,
    });

    const secondParsed = extractPaymentPayload(second.data);
    logVerificationResult({
      bankReference: normalizedRef,
      userBankId,
      requestedAmount: amount,
      fechaPago: resolvedFechaPago,
      response: second,
      parsed: secondParsed,
    });

    if (second.ok && secondParsed.hasMovement) {
      const reportedAmount = secondParsed.reportedAmount;
      if (reportedAmount === null || reportedAmount <= 0) {
        return {
          configured: true,
          found: true,
          isNew: secondParsed.isNew,
          creditCost: secondParsed.creditCost,
          amountVerifiedByProvider: false,
          reportedAmount: null,
          unreadableAmount: true,
          paymentDate: secondParsed.paymentDate,
          paymentStatus: secondParsed.paymentStatus,
          paymentId: secondParsed.paymentId,
          paymentLinkId: secondParsed.paymentLinkId,
          providerError: false,
          endpoint: second.endpoint,
          message: 'Encontramos la referencia pero no pudimos leer el monto reportado por el banco.',
          raw: second.data,
        };
      }
      return {
        configured: true,
        found: true,
        isNew: secondParsed.isNew,
        creditCost: secondParsed.creditCost,
        amountVerifiedByProvider: true,
        reportedAmount,
        paymentDate: secondParsed.paymentDate,
        paymentStatus: secondParsed.paymentStatus,
        paymentId: secondParsed.paymentId,
        paymentLinkId: secondParsed.paymentLinkId,
        providerError: false,
        endpoint: second.endpoint,
        message: (second.data && second.data.message) || 'Pago encontrado.',
        raw: second.data,
      };
    }

    if (isUnknownBankAccount(second.status, second.rawText)) {
      return {
        configured: true,
        found: false,
        isNew: false,
        providerError: true,
        unknownBankAccount: true,
        status: second.status,
        message: 'Cuenta bancaria en Pabilo no encontrada (user_bank not found).',
      };
    }

    if (second.networkError || isRetryableStatus(second.status)) {
      return {
        configured: true,
        found: false,
        isNew: false,
        providerError: true,
        timedOut: second.timedOut,
        status: second.status,
        message: second.timedOut
          ? 'El banco tardó demasiado en responder al verificar la referencia. Reintenta en unos segundos con la misma referencia.'
          : 'Error temporal consultando al proveedor de verificación bancaria.',
      };
    }

    return {
      configured: true,
      found: false,
      isNew: false,
      providerError: false,
      status: second.status,
      message: (second.data && second.data.message) || 'No encontramos un pago con esa referencia todavía.',
      raw: second.data,
    };
  }

  if (first.networkError || isRetryableStatus(first.status)) {
    return {
      configured: true,
      found: false,
      isNew: false,
      providerError: true,
      timedOut: first.timedOut,
      status: first.status,
      message: first.timedOut
        ? 'El banco tardó demasiado en responder al verificar la referencia. Reintenta en unos segundos con la misma referencia.'
        : 'Error temporal consultando al proveedor de verificación bancaria.',
    };
  }

  if (isNotFoundResponse(first.status, first.data)) {
    return {
      configured: true,
      found: false,
      isNew: false,
      providerError: false,
      status: first.status,
      message: (first.data && first.data.message) || 'No encontramos un pago con esa referencia todavía.',
      raw: first.data,
    };
  }

  return {
    configured: true,
    found: false,
    isNew: false,
    providerError: true,
    status: first.status,
    message: (first.data && first.data.message) || 'Error inesperado verificando el pago en Pabilo.',
    raw: first.data,
  };
}

/**
 * Crea un enlace de pago en Pabilo (`POST /v1/paymentlink`).
 * Funciona tanto en Bs (`currency: "VEF"`) como en Binance Pay (`currency: "USDT"`).
 */
async function createPaymentLink({
  baseUrl,
  apiKey,
  userBankId,
  amount,
  currency = 'VEF',
  name = 'Plan Pro',
  description = 'Suscripción Pro - margencalcu',
  redirectUrl = 'https://margencalcu.online/gracias',
  webhookUrl = 'https://margencalcu.online/webhook/pabilo',
  notificationByWhatsapp = true,
  fetchImpl = globalThis.fetch,
  timeoutMs = DEFAULT_LINK_TIMEOUT_MS,
}) {
  if (!apiKey || !userBankId || !(Number(amount) > 0)) {
    return { ok: false, id: null, url: null, status: 'unavailable' };
  }
  const url = `${normalizeBaseUrl(baseUrl)}/v1/paymentlink`;
  const cleanAmount = Number(Number(amount).toFixed(2));
  const payload = {
    user_bank_id: String(userBankId).trim(),
    userBankId: String(userBankId).trim(),
    amount: cleanAmount,
    currency: currency === 'USDT' || currency === 'USD' ? 'USDT' : 'VEF',
    name: String(name),
    description: String(description),
    redirect_url: String(redirectUrl),
    redirectUrl: String(redirectUrl),
    webhook_url: String(webhookUrl),
    webhookUrl: String(webhookUrl),
    notification_by_whatsapp: Boolean(notificationByWhatsapp),
    notificationByWhatsapp: Boolean(notificationByWhatsapp),
  };

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetchImpl(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${apiKey}`,
        appKey: apiKey,
      },
      body: JSON.stringify(payload),
      signal: controller.signal,
    });
    const rawText = await res.text();
    let data = null;
    if (rawText) {
      try {
        data = JSON.parse(rawText);
      } catch {
        data = null;
      }
    }
    const linkObj =
      (data && data.paymentlink) ||
      (data && data.payment_link) ||
      (data && data.data && (data.data.payment_link || data.data.paymentlink)) ||
      (data && data.id ? data : null);

    if (res.ok && linkObj && linkObj.id) {
      const id = String(linkObj.id);
      return {
        ok: true,
        httpStatus: res.status,
        id,
        url: String(linkObj.url || `https://pabilo.app/pay/${id}`),
        status: String(linkObj.status || 'pending'),
        amount: parseFiniteNumber(linkObj.amount) ?? cleanAmount,
        currency: String(linkObj.currency || payload.currency),
        raw: data,
      };
    }
    return {
      ok: false,
      httpStatus: res.status,
      id: null,
      url: null,
      status: 'error',
      raw: data,
    };
  } catch {
    return { ok: false, httpStatus: 0, id: null, url: null, status: 'network_error', raw: null };
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Consulta el estado real de un enlace de pago en Pabilo (`GET /paymentlink/{id}/info`,
 * con respaldo en `GET /v1/paymentlink/{id}`).
 * Fuente de verdad obligatoria antes de activar Pro por enlace o webhook.
 */
async function getPaymentLinkInfo({
  baseUrl,
  apiKey,
  paymentLinkId,
  fetchImpl = globalThis.fetch,
  timeoutMs = DEFAULT_LINK_TIMEOUT_MS,
}) {
  const cleanId = String(paymentLinkId || '').trim();
  if (!apiKey || !cleanId) {
    return { ok: false, isPaid: false, status: 'unavailable', amount: null, reference: null };
  }

  const cleanBase = normalizeBaseUrl(baseUrl);
  const encodedId = encodeURIComponent(cleanId);
  const urls = [
    `${cleanBase}/paymentlink/${encodedId}/info`,
    `${cleanBase}/v1/paymentlink/${encodedId}`,
  ];

  for (const url of urls) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const res = await fetchImpl(url, {
        method: 'GET',
        headers: {
          Authorization: `Bearer ${apiKey}`,
          appKey: apiKey,
        },
        signal: controller.signal,
      });
      const rawText = await res.text();
      let data = null;
      if (rawText) {
        try {
          data = JSON.parse(rawText);
        } catch {
          data = null;
        }
      }

      if (isRouteNotFound(res.status, data, rawText) && url === urls[0]) {
        continue;
      }

      if (!res.ok || !data) {
        return {
          ok: false,
          httpStatus: res.status,
          isPaid: false,
          status: 'not_found',
          amount: null,
          reference: null,
          raw: data,
        };
      }

      const inner = data.data && typeof data.data === 'object' ? data.data : data;
      const linkObj = inner.payment_link || inner.paymentlink || data.paymentlink || data.payment_link || inner;
      const ubp =
        inner.user_bank_payment ||
        (linkObj && linkObj.user_bank_payment) ||
        data.user_bank_payment ||
        null;

      const status = String((linkObj && linkObj.status) || (ubp && ubp.status) || '').toLowerCase();
      const isPaid = status === 'paid' || status === 'verified' || status === 'completed';
      const amount =
        parseFiniteNumber(ubp && ubp.amount) ?? parseFiniteNumber(linkObj && linkObj.amount);
      const reference =
        (ubp && (ubp.bank_reference_id || ubp.reference)) ||
        (linkObj && (linkObj.bank_reference_id || linkObj.reference)) ||
        null;
      const paymentDate =
        (ubp && (ubp.payment_date || ubp.date)) ||
        inner.payment_date ||
        (ubp && ubp.created_at ? String(ubp.created_at).slice(0, 10) : null) ||
        null;

      return {
        ok: true,
        httpStatus: res.status,
        id: String((linkObj && linkObj.id) || cleanId),
        status,
        isPaid,
        amount,
        reference: reference ? String(reference) : null,
        paymentDate: paymentDate ? String(paymentDate) : null,
        paymentLink: linkObj,
        userBankPayment: ubp,
        raw: data,
      };
    } catch {
      return { ok: false, httpStatus: 0, isPaid: false, status: 'network_error', amount: null, reference: null };
    } finally {
      clearTimeout(timer);
    }
  }

  return { ok: false, httpStatus: 404, isPaid: false, status: 'not_found', amount: null, reference: null };
}

/**
 * Verifica la firma HMAC-SHA256 del header `X-Pabilo-Signature`.
 */
function verifyWebhookSignature({ rawBody, signatureHeader, webhookSecret }) {
  const secret = String(webhookSecret || '').trim();
  const sigRaw = String(signatureHeader || '').trim();
  if (!secret || !sigRaw) return false;

  const cleanSig = sigRaw.replace(/^sha256=/i, '').trim();
  const payloadBuf = Buffer.isBuffer(rawBody)
    ? rawBody
    : Buffer.from(typeof rawBody === 'string' ? rawBody : JSON.stringify(rawBody || {}), 'utf8');

  const expectedHex = crypto.createHmac('sha256', secret).update(payloadBuf).digest('hex');
  if (cleanSig.length !== expectedHex.length) return false;
  try {
    return crypto.timingSafeEqual(Buffer.from(cleanSig, 'utf8'), Buffer.from(expectedHex, 'utf8'));
  } catch {
    return false;
  }
}

/**
 * Consulta la tasa oficial de respaldo en Pabilo (`GET /exchange/rate`).
 */
async function getExchangeRate({
  baseUrl,
  apiKey,
  fetchImpl = globalThis.fetch,
  timeoutMs = DEFAULT_RATE_TIMEOUT_MS,
}) {
  if (!apiKey) return null;
  const url = `${normalizeBaseUrl(baseUrl)}/exchange/rate`;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetchImpl(url, {
      method: 'GET',
      headers: { Authorization: `Bearer ${apiKey}`, appKey: apiKey },
      signal: controller.signal,
    });
    if (!res.ok) return null;
    const data = await res.json();
    const bcvUsd =
      parseFiniteNumber(data && data.rates && data.rates.USD) ||
      parseFiniteNumber(data && data.price);
    if (!bcvUsd || bcvUsd <= 0) return null;
    return {
      usd: bcvUsd,
      eur: parseFiniteNumber(data && data.rates && data.rates.EUR),
      usdt: parseFiniteNumber(data && data.rates && data.rates.USDT),
      source: 'pabilo',
    };
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

module.exports = {
  DEFAULT_PABILO_BASE_URL,
  DEFAULT_VERIFY_TIMEOUT_MS,
  normalizeBaseUrl,
  getCaracasDateString,
  normalizeReference,
  parseFiniteNumber,
  extractPaymentPayload,
  extractAmount,
  extractDate,
  isUnknownBankAccount,
  verifyPayment,
  createPaymentLink,
  getPaymentLinkInfo,
  verifyWebhookSignature,
  getExchangeRate,
};
