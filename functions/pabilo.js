'use strict';

const DEFAULT_PABILO_BASE_URL = 'https://api.pabilo.app';
const DEFAULT_VERIFY_TIMEOUT_MS = 45_000;
const DEFAULT_RATE_TIMEOUT_MS = 10_000;

function normalizeBaseUrl(raw) {
  const base = String(raw || DEFAULT_PABILO_BASE_URL).trim();
  return (base || DEFAULT_PABILO_BASE_URL).replace(/\/+$/, '');
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

function parseFiniteNumber(raw) {
  if (typeof raw === 'number') {
    return Number.isFinite(raw) ? raw : null;
  }
  if (typeof raw === 'string') {
    const cleaned = raw.trim().replace(',', '.');
    if (!cleaned) return null;
    const n = Number(cleaned);
    return Number.isFinite(n) ? n : null;
  }
  return null;
}

function extractAmount(data) {
  if (!data || typeof data !== 'object') return null;
  const candidates = [
    data.amount,
    data.user_bank_payment && data.user_bank_payment.amount,
    data.userBankPayment && data.userBankPayment.amount,
  ];
  for (const val of candidates) {
    const num = parseFiniteNumber(val);
    if (num !== null) return num;
  }
  return null;
}

function extractDate(data) {
  if (!data || typeof data !== 'object') return null;
  const candidate =
    data.date ||
    (data.user_bank_payment && data.user_bank_payment.date) ||
    (data.userBankPayment && data.userBankPayment.date) ||
    null;
  return candidate ? String(candidate) : null;
}

function isUnknownBankAccount(status, rawText) {
  return status >= 400 && /user_?bank not found/i.test(String(rawText || ''));
}

function isRetryableStatus(status) {
  return status === 408 || status === 429 || status >= 500;
}

function isNotFoundResponse(status, data) {
  if (status === 400 || status === 404 || status === 422) return true;
  if (status >= 200 && status < 300 && (!data || !data.data)) return true;
  return false;
}

/**
 * Ejecuta una petición POST única (retries: 0, timeout 45s) contra Betaserio.
 * Crítico: Betaserio registra la referencia en el primer intento; nunca reintentar
 * automáticamente un POST en caso de timeout.
 */
async function postBetaserio({
  baseUrl,
  apiKey,
  userBankId,
  bankReference,
  amount,
  fetchImpl = globalThis.fetch,
  timeoutMs = DEFAULT_VERIFY_TIMEOUT_MS,
}) {
  const url = `${normalizeBaseUrl(baseUrl)}/userbankpayment/${encodeURIComponent(
    String(userBankId).trim(),
  )}/betaserio`;

  const body = { bank_reference: bankReference };
  if (amount !== undefined && amount !== null) {
    body.amount = Number(Number(amount).toFixed(2));
  }

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetchImpl(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
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
      networkError: true,
      timedOut: isAbort,
    };
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Verificación en 2 pasos idéntica a refill-store:
 * 1) Consulta con monto exacto (`amountVerifiedByProvider: true`).
 * 2) Si responde no encontrado (400/404/422 o sin `data`) y se envió `amount`,
 *    consulta sin `amount` para detectar pagos parciales/sobrepagos, exigiendo
 *    que Pabilo devuelva un `reportedAmount` numérico válido > 0.
 */
async function verifyPayment(params) {
  const {
    baseUrl,
    apiKey,
    userBankId,
    bankReference,
    amount = null,
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

  const first = await postBetaserio({
    baseUrl,
    apiKey,
    userBankId,
    bankReference: normalizedRef,
    amount,
    fetchImpl,
    timeoutMs,
  });

  if (first.ok && first.data && first.data.data) {
    const reportedAmount = extractAmount(first.data.data);
    return {
      configured: true,
      found: true,
      isNew: first.data.is_new === true,
      amountVerifiedByProvider: amount !== null && amount !== undefined,
      reportedAmount: reportedAmount !== null ? reportedAmount : amount,
      paymentDate: extractDate(first.data.data),
      providerError: false,
      message: first.data.message || 'Pago encontrado.',
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

  if (amount !== null && amount !== undefined && !first.networkError && isNotFoundResponse(first.status, first.data)) {
    const second = await postBetaserio({
      baseUrl,
      apiKey,
      userBankId,
      bankReference: normalizedRef,
      amount: null,
      fetchImpl,
      timeoutMs,
    });

    if (second.ok && second.data && second.data.data) {
      const reportedAmount = extractAmount(second.data.data);
      if (reportedAmount === null || reportedAmount <= 0) {
        return {
          configured: true,
          found: true,
          isNew: second.data.is_new === true,
          amountVerifiedByProvider: false,
          reportedAmount: null,
          unreadableAmount: true,
          paymentDate: extractDate(second.data.data),
          providerError: false,
          message: 'Encontramos la referencia pero no pudimos leer el monto reportado por el banco.',
          raw: second.data,
        };
      }
      return {
        configured: true,
        found: true,
        isNew: second.data.is_new === true,
        amountVerifiedByProvider: false,
        reportedAmount,
        paymentDate: extractDate(second.data.data),
        providerError: false,
        message: second.data.message || 'Pago encontrado.',
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
    };
  }

  return {
    configured: true,
    found: false,
    isNew: false,
    providerError: true,
    status: first.status,
    message: (first.data && first.data.message) || 'Error inesperado verificando el pago en Pabilo.',
  };
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
      headers: { Authorization: `Bearer ${apiKey}` },
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
  normalizeReference,
  extractAmount,
  extractDate,
  isUnknownBankAccount,
  verifyPayment,
  getExchangeRate,
};

