'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { verifyPayment, normalizeReference } = require('../pabilo');
const {
  PRO_PLANS,
  checkAmount,
  computeSubscriptionDates,
  createProCheckout,
  verifyProPayment,
  checkRateLimit,
  getProPaymentConfigPayload,
} = require('../pro-payments');

/**
 * Simulador en memoria de Firestore con soporte para `runTransaction`,
 * subcolecciones (`users/{uid}/subscription/{doc}`) y consultas de campo único.
 */
function createMemoryFirestore(initial = {}) {
  const store = new Map(Object.entries(initial));

  function clone(val) {
    return val === undefined ? undefined : JSON.parse(JSON.stringify(val));
  }

  function applyUpdate(existing, patch) {
    const base = existing ? clone(existing) : {};
    for (const [key, value] of Object.entries(patch || {})) {
      if (key.includes('.')) {
        const parts = key.split('.');
        let cursor = base;
        for (let i = 0; i < parts.length - 1; i++) {
          if (!cursor[parts[i]] || typeof cursor[parts[i]] !== 'object') {
            cursor[parts[i]] = {};
          }
          cursor = cursor[parts[i]];
        }
        cursor[parts[parts.length - 1]] = clone(value);
      } else {
        base[key] = clone(value);
      }
    }
    return base;
  }

  function docRef(path) {
    return {
      path,
      id: path.split('/').pop(),
      collection(name) {
        return collectionRef(`${path}/${name}`);
      },
      async get() {
        const val = store.get(path);
        return {
          id: path.split('/').pop(),
          exists: val !== undefined,
          data: () => clone(val),
        };
      },
      async set(data, opts = {}) {
        if (opts && opts.merge) {
          store.set(path, applyUpdate(store.get(path), data));
        } else {
          store.set(path, clone(data));
        }
      },
      async update(patch) {
        if (!store.has(path)) throw new Error(`Missing doc ${path}`);
        store.set(path, applyUpdate(store.get(path), patch));
      },
      async delete() {
        store.delete(path);
      },
    };
  }

  function readNestedField(obj, fieldPath) {
    return fieldPath.split('.').reduce((acc, part) => (acc && acc[part] !== undefined ? acc[part] : undefined), obj);
  }

  function collectionRef(path) {
    return {
      doc(id) {
        return docRef(`${path}/${id}`);
      },
      where(field, op, value) {
        return {
          limit(max) {
            return {
              async get() {
                const prefix = `${path}/`;
                const docs = [];
                for (const [docPath, data] of store.entries()) {
                  if (!docPath.startsWith(prefix)) continue;
                  const remainder = docPath.slice(prefix.length);
                  if (remainder.includes('/')) continue;
                  const v = readNestedField(data, field);
                  const matches =
                    (op === '==' && v === value) ||
                    (op === 'array-contains' && Array.isArray(v) && v.includes(value));
                  if (matches) {
                    docs.push({
                      id: remainder,
                      exists: true,
                      data: () => clone(data),
                    });
                    if (docs.length >= max) break;
                  }
                }
                return { docs };
              },
            };
          },
        };
      },
    };
  }

  return {
    _store: store,
    collection(name) {
      return collectionRef(name);
    },
    async runTransaction(fn) {
      const staged = [];
      const tx = {
        async get(ref) {
          return ref.get();
        },
        set(ref, data, opts) {
          staged.push(() => ref.set(data, opts));
        },
        update(ref, patch) {
          staged.push(() => ref.update(patch));
        },
        delete(ref) {
          staged.push(() => ref.delete());
        },
      };
      const result = await fn(tx);
      for (const apply of staged) {
        await apply();
      }
      return result;
    },
  };
}

function makeMockFetch(routes) {
  const calls = [];
  const fn = async (url, init = {}) => {
    const body = init.body ? JSON.parse(init.body) : null;
    calls.push({ url, method: init.method || 'GET', headers: init.headers || {}, body });
    const handler = routes[calls.length - 1] || routes.default;
    if (typeof handler === 'function') {
      const out = await handler({ url, init, body, calls });
      if (out instanceof Error) throw out;
      return {
        ok: out.status >= 200 && out.status < 300,
        status: out.status,
        async text() {
          return typeof out.body === 'string' ? out.body : JSON.stringify(out.body);
        },
        async json() {
          return out.body;
        },
      };
    }
    throw new Error(`Unexpected fetch to ${url} (#${calls.length})`);
  };
  fn.calls = calls;
  return fn;
}

const TEST_ENV = {
  PABILO_API_KEY: 'test-pabilo-secret',
  PABILO_USER_BANK_ID: '777',
  PABILO_BINANCE_USER_BANK_ID: '888',
  PRO_PM_BANK: 'BDV',
  PRO_PM_PHONE: '04120000000',
};

test('normalizeReference limpia dígitos en Pago Móvil y alfanuméricos en Binance Pay', () => {
  assert.equal(normalizeReference('  0012-3456 78 '), '0012345678');
  assert.equal(normalizeReference('bp-99ab-01cd', true), 'BP99AB01CD');
});

test('checkAmount exige 0 déficit en céntimos y permite sobrepago', () => {
  const exact = checkAmount(1794.22, 1794.22);
  assert.equal(exact.ok, true);
  assert.equal(exact.shortfall, 0);

  const short = checkAmount(1794.22, 1794.21);
  assert.equal(short.ok, false);
  assert.equal(short.shortfall, 0.01);

  const over = checkAmount(1794.22, 2200);
  assert.equal(over.ok, true);
  assert.equal(over.overpaid, 405.78);
  assert.equal(over.overpaidAlert, true);
});

test('computeSubscriptionDates extiende desde el vencimiento activo actual cuando renueva', () => {
  const now = Date.UTC(2026, 10, 10, 12, 0, 0);
  const existingEnd = new Date(now + 10 * 86_400_000).toISOString();
  const { startDate, endDate } = computeSubscriptionDates({
    existingSub: {
      status: 'active',
      startDate: '2026-10-20T00:00:00.000Z',
      endDate: existingEnd,
    },
    durationDays: 30,
    nowMs: now,
  });
  assert.equal(startDate, '2026-10-20T00:00:00.000Z');
  assert.equal(new Date(endDate).getTime(), now + 40 * 86_400_000);
});

test('verifyPayment ejecuta búsqueda en 2 pasos (con monto -> sin monto) y rechaza monto ilegible', async () => {
  const mockFetch = makeMockFetch([
    () => ({ status: 404, body: { message: 'not found for exact amount' } }),
    () => ({ status: 200, body: { is_new: true, data: { date: '2026-11-11' } } }),
  ]);

  const res = await verifyPayment({
    apiKey: 'secret',
    userBankId: '777',
    bankReference: '123456',
    amount: 1794.22,
    fetchImpl: mockFetch,
  });

  assert.equal(mockFetch.calls.length, 2);
  assert.equal(mockFetch.calls[0].body.amount, 1794.22);
  assert.equal('amount' in mockFetch.calls[1].body, false);
  assert.equal(res.unreadableAmount, true);
  assert.equal(res.reportedAmount, null);
});

test('verifyPayment detecta user_bank not found inmediatamente sin retry', async () => {
  const mockFetch = makeMockFetch([
    () => ({ status: 500, body: { message: 'user_bank not found' } }),
  ]);
  const res = await verifyPayment({
    apiKey: 'secret',
    userBankId: '999',
    bankReference: '123456',
    amount: 100,
    fetchImpl: mockFetch,
  });
  assert.equal(res.providerError, true);
  assert.equal(res.unknownBankAccount, true);
  assert.equal(mockFetch.calls.length, 1);
});

test('flujo completo createProCheckout + verifyProPayment activa Pro al instante con BCV congelada', async () => {
  const db = createMemoryFirestore();
  const mockFetch = makeMockFetch([
    () => ({ status: 200, body: { current: { usd: 901.62, eur: 1007.96, date: '2026-11-11' } } }),
    () => ({ status: 200, body: { is_new: true, data: { amount: '1794.22', date: '2026-11-11' } } }),
  ]);

  const checkout = await createProCheckout({
    db,
    uid: 'user_1',
    email: 'vendedor@ejemplo.com',
    planId: 'monthly',
    methodId: 'pago_movil',
    fetchImpl: mockFetch,
    env: TEST_ENV,
    orderIdGenerator: () => 'ord_exact_1',
  });

  assert.equal(checkout.order.expectedAmountUsd, PRO_PLANS.monthly.priceUsd);
  assert.equal(checkout.order.expectedAmountBs, 1794.22);
  assert.equal(checkout.order.rateBs, 901.62);

  const verify = await verifyProPayment({
    db,
    uid: 'user_1',
    orderId: 'ord_exact_1',
    rawReference: '0044-5566',
    fetchImpl: mockFetch,
    env: TEST_ENV,
  });

  assert.equal(verify.ok, true);
  assert.equal(verify.code, 'ACTIVATED');
  assert.equal(verify.subscription.status, 'active');
  assert.equal(verify.subscription.plan, 'monthly');
  assert.equal(verify.subscription.provider, 'pabilo_bdv');

  const subSnap = await db.collection('users').doc('user_1').collection('subscription').doc('current').get();
  assert.equal(subSnap.exists, true);
  assert.equal(subSnap.data().paymentRef, '00445566');
});

test('abono parcial mantiene orden abierta y un segundo pago por la diferencia activa Pro', async () => {
  const db = createMemoryFirestore();
  const now = Date.UTC(2026, 10, 11, 10, 0, 0);
  const mockFetch = makeMockFetch([
    () => ({ status: 200, body: { current: { usd: 100, date: '2026-11-11' } } }),
    // Pago 1: con monto 199 no aparece -> fallback sin monto devuelve 120 Bs
    () => ({ status: 404, body: { message: 'amount mismatch' } }),
    () => ({ status: 200, body: { is_new: true, data: { amount: 120 } } }),
    // Reintentar la MISMA ref parcial debe ser bloqueado
    // Pago 2: por los 79 Bs restantes -> aprueba
    () => ({ status: 200, body: { is_new: true, data: { amount: 79 } } }),
  ]);

  await createProCheckout({
    db,
    uid: 'user_partial',
    planId: 'monthly',
    methodId: 'pago_movil',
    fetchImpl: mockFetch,
    env: TEST_ENV,
    nowMs: now,
    orderIdGenerator: () => 'ord_part_1',
  });

  const p1 = await verifyProPayment({
    db,
    uid: 'user_partial',
    orderId: 'ord_part_1',
    rawReference: '11112222',
    fetchImpl: mockFetch,
    env: TEST_ENV,
    nowMs: now + 1000,
  });

  assert.equal(p1.ok, false);
  assert.equal(p1.code, 'PARTIAL_PAYMENT');
  assert.equal(p1.paidAmount, 120);
  assert.equal(p1.remainingAmount, 79);

  await assert.rejects(
    () =>
      verifyProPayment({
        db,
        uid: 'user_partial',
        orderId: 'ord_part_1',
        rawReference: '11112222',
        fetchImpl: mockFetch,
        env: TEST_ENV,
        nowMs: now + 2000,
      }),
    (err) => err.code === 'PARTIAL_REF_ALREADY_CREDITED',
  );

  const p2 = await verifyProPayment({
    db,
    uid: 'user_partial',
    orderId: 'ord_part_1',
    rawReference: '33334444',
    fetchImpl: mockFetch,
    env: TEST_ENV,
    nowMs: now + 3000,
  });

  assert.equal(p2.ok, true);
  assert.equal(p2.code, 'ACTIVATED');
  assert.equal(p2.subscription.paidAmount, 199);
});

test('reconciliación tras timeout permite is_new=false para la misma orden y rechaza referencia ajena', async () => {
  const db = createMemoryFirestore();
  const mockFetch = makeMockFetch([
    () => ({ status: 200, body: { current: { usd: 1000, date: '2026-11-11' } } }),
    // Intento 1: timeout (AbortError) después de que Pabilo registró internamente la ref
    () => new Error('The operation was aborted'),
    // Intento 2 (mismo usuario/ref tras error): Pabilo devuelve is_new: false
    () => ({ status: 200, body: { is_new: false, data: { amount: 14990 } } }),
  ]);

  await createProCheckout({
    db,
    uid: 'user_retry',
    planId: 'annual',
    methodId: 'pago_movil',
    fetchImpl: mockFetch,
    env: TEST_ENV,
    orderIdGenerator: () => 'ord_retry_1',
  });

  const firstAttempt = await verifyProPayment({
    db,
    uid: 'user_retry',
    orderId: 'ord_retry_1',
    rawReference: '88776655',
    fetchImpl: mockFetch,
    env: TEST_ENV,
  });
  assert.equal(firstAttempt.ok, false);
  assert.equal(firstAttempt.code, 'PROVIDER_TIMEOUT');
  assert.equal(firstAttempt.retryable, true);

  const secondAttempt = await verifyProPayment({
    db,
    uid: 'user_retry',
    orderId: 'ord_retry_1',
    rawReference: '88776655',
    fetchImpl: mockFetch,
    env: TEST_ENV,
  });
  assert.equal(secondAttempt.ok, true);
  assert.equal(secondAttempt.reconciledDuplicate, true);
  assert.equal(secondAttempt.subscription.plan, 'annual');

  // Otro usuario intentando esa misma referencia ya consumida es rechazado antes de Pabilo
  const mockFetch2 = makeMockFetch([
    () => ({ status: 200, body: { current: { usd: 1000, date: '2026-11-11' } } }),
  ]);
  await createProCheckout({
    db,
    uid: 'user_thief',
    planId: 'annual',
    methodId: 'pago_movil',
    fetchImpl: mockFetch2,
    env: TEST_ENV,
    orderIdGenerator: () => 'ord_thief_1',
  });
  await assert.rejects(
    () =>
      verifyProPayment({
        db,
        uid: 'user_thief',
        orderId: 'ord_thief_1',
        rawReference: '88776655',
        fetchImpl: mockFetch2,
        env: TEST_ENV,
      }),
    (err) => err.code === 'REFERENCE_ALREADY_USED',
  );
  // El fetch no debió ni llegar a Pabilo por el lock en paymentRefs
  assert.equal(mockFetch2.calls.length, 1);
});

test('referencia is_new=false sin error previo en la orden se rechaza inclusive al reintentar', async () => {
  const db = createMemoryFirestore();
  const mockFetch = makeMockFetch([
    () => ({ status: 200, body: { current: { usd: 100, date: '2026-11-11' } } }),
    () => ({ status: 200, body: { is_new: false, data: { amount: 199 } } }),
    () => ({ status: 200, body: { is_new: false, data: { amount: 199 } } }),
  ]);

  await createProCheckout({
    db,
    uid: 'user_reuse',
    planId: 'monthly',
    methodId: 'pago_movil',
    fetchImpl: mockFetch,
    env: TEST_ENV,
    orderIdGenerator: () => 'ord_reuse_1',
  });

  const a1 = await verifyProPayment({
    db,
    uid: 'user_reuse',
    orderId: 'ord_reuse_1',
    rawReference: '55443322',
    fetchImpl: mockFetch,
    env: TEST_ENV,
  });
  assert.equal(a1.ok, false);
  assert.equal(a1.code, 'REFERENCE_ALREADY_USED');

  const a2 = await verifyProPayment({
    db,
    uid: 'user_reuse',
    orderId: 'ord_reuse_1',
    rawReference: '55443322',
    fetchImpl: mockFetch,
    env: TEST_ENV,
  });
  assert.equal(a2.ok, false);
  assert.equal(a2.code, 'REFERENCE_ALREADY_USED');
});

test('Binance Pay / USDT limpia referencia alfanumérica y asigna provider pabilo_binance', async () => {
  const db = createMemoryFirestore();
  const mockFetch = makeMockFetch([
    () => ({ status: 200, body: { current: { usd: 900, date: '2026-11-11' } } }),
    () => ({ status: 200, body: { is_new: true, data: { amount: 14.99 } } }),
  ]);

  await createProCheckout({
    db,
    uid: 'user_binance',
    planId: 'annual',
    methodId: 'usdt',
    fetchImpl: mockFetch,
    env: TEST_ENV,
    orderIdGenerator: () => 'ord_bin_1',
  });

  const verify = await verifyProPayment({
    db,
    uid: 'user_binance',
    orderId: 'ord_bin_1',
    rawReference: 'bin-order-2026ab',
    fetchImpl: mockFetch,
    env: TEST_ENV,
  });
  assert.equal(verify.ok, true);
  assert.equal(verify.subscription.provider, 'pabilo_binance');
  assert.equal(verify.subscription.paymentRef, 'BINORDER2026AB');
});

test('getProPaymentConfigPayload nunca expone apiKey ni bankId al cliente', async () => {
  const db = createMemoryFirestore({
    'config/proPayments': {
      pagoMovil: { banco: 'BDV', telefono: '04121234567', cedulaRif: 'V-12345678', titular: 'Comercio' },
      usdt: { red: 'Binance Pay', binanceId: '123456789' },
    },
  });
  const mockFetch = makeMockFetch([
    () => ({ status: 200, body: { current: { usd: 901.62, date: '2026-11-11' } } }),
  ]);

  const cfg = await getProPaymentConfigPayload({ db, fetchImpl: mockFetch, env: TEST_ENV });
  const serialized = JSON.stringify(cfg);
  assert.equal(serialized.includes('test-pabilo-secret'), false);
  assert.equal(serialized.includes('777'), false);
  assert.equal(serialized.includes('888'), false);
  assert.equal(cfg.methods.pago_movil.autoVerify, true);
  assert.equal(cfg.methods.usdt.autoVerify, true);
  assert.equal(cfg.plans.length, 4);
  assert.deepEqual(
    cfg.plans.map((p) => [p.id, p.priceUsd]),
    [
      ['monthly', 1.99],
      ['quarterly', 4.99],
      ['semiannual', 7.99],
      ['annual', 14.99],
    ],
  );
  assert.equal(cfg.plans[3].estimatedBs, 13515.28);
});

test('checkRateLimit bloquea cuando excede el límite dentro de la ventana', async () => {
  const db = createMemoryFirestore();
  await checkRateLimit({ db, name: 'pro_verify', key: 'u1', maxRequests: 2, windowMs: 60_000, nowMs: 1000 });
  await checkRateLimit({ db, name: 'pro_verify', key: 'u1', maxRequests: 2, windowMs: 60_000, nowMs: 2000 });
  await assert.rejects(
    () => checkRateLimit({ db, name: 'pro_verify', key: 'u1', maxRequests: 2, windowMs: 60_000, nowMs: 3000 }),
    (err) => err.code === 'RATE_LIMIT_EXCEEDED',
  );
});

test('planes quarterly ($4.99) y semiannual ($7.99) crean orden y verifican con Pabilo', async () => {
  const db = createMemoryFirestore();
  const mockFetch = makeMockFetch([
    () => ({ status: 200, body: { current: { usd: 100, date: '2026-11-11' } } }),
    () => ({ status: 200, body: { is_new: true, data: { amount: 499 } } }),
    () => ({ status: 200, body: { current: { usd: 100, date: '2026-11-11' } } }),
    () => ({ status: 200, body: { is_new: true, data: { amount: 799 } } }),
  ]);

  await createProCheckout({
    db,
    uid: 'u_q',
    planId: 'quarterly',
    methodId: 'pago_movil',
    fetchImpl: mockFetch,
    env: TEST_ENV,
    orderIdGenerator: () => 'ord_q_1',
  });
  const resQ = await verifyProPayment({
    db,
    uid: 'u_q',
    orderId: 'ord_q_1',
    rawReference: '123456',
    fetchImpl: mockFetch,
    env: TEST_ENV,
  });
  assert.equal(resQ.ok, true);
  assert.equal(resQ.subscription.plan, 'quarterly');
  assert.equal(resQ.subscription.amountUsd, 4.99);

  await createProCheckout({
    db,
    uid: 'u_s',
    planId: 'semiannual',
    methodId: 'pago_movil',
    fetchImpl: mockFetch,
    env: TEST_ENV,
    orderIdGenerator: () => 'ord_s_1',
  });
  const resS = await verifyProPayment({
    db,
    uid: 'u_s',
    orderId: 'ord_s_1',
    rawReference: '654321',
    fetchImpl: mockFetch,
    env: TEST_ENV,
  });
  assert.equal(resS.ok, true);
  assert.equal(resS.subscription.plan, 'semiannual');
  assert.equal(resS.subscription.amountUsd, 7.99);
});

test('configuración pública por defecto expone BDV 0102 y Binance Pay ID 916942742 y enruta Pabilo por bankId separado', async () => {
  const db = createMemoryFirestore();
  const mockFetch = makeMockFetch([
    () => ({ status: 200, body: { current: { usd: 900, date: '2026-11-11' } } }),
    () => ({ status: 200, body: { current: { usd: 900, date: '2026-11-11' } } }),
    () => ({ status: 200, body: { is_new: true, data: { amount: 1.99 } } }),
    () => ({ status: 200, body: { current: { usd: 900, date: '2026-11-11' } } }),
    () => ({ status: 200, body: { is_new: true, data: { amount: 1791 } } }),
  ]);

  const cleanEnv = {
    PABILO_API_KEY: 'test-pabilo-secret',
    PABILO_USER_BANK_ID: '777',
    PABILO_BINANCE_USER_BANK_ID: '888',
  };
  const cfg = await getProPaymentConfigPayload({ db, fetchImpl: mockFetch, env: cleanEnv });
  assert.equal(cfg.methods.pago_movil.bank, 'Banco de Venezuela (BDV · 0102)');
  assert.equal(cfg.methods.pago_movil.cedulaRif, '31955598');
  assert.equal(cfg.methods.pago_movil.phone, '04220336568');
  assert.equal(cfg.methods.pago_movil.autoVerify, true);
  assert.equal(cfg.methods.usdt.network, 'Binance Pay (USDT)');
  assert.equal(cfg.methods.usdt.binanceId, '916942742');
  assert.equal(cfg.methods.usdt.autoVerify, true);

  await createProCheckout({
    db,
    uid: 'u_bp_route',
    planId: 'monthly',
    methodId: 'usdt',
    fetchImpl: mockFetch,
    env: TEST_ENV,
    orderIdGenerator: () => 'ord_bp_route',
  });
  const binRes = await verifyProPayment({
    db,
    uid: 'u_bp_route',
    orderId: 'ord_bp_route',
    rawReference: '319400112233',
    fetchImpl: mockFetch,
    env: TEST_ENV,
  });
  assert.equal(binRes.ok, true);
  assert.equal(binRes.subscription.provider, 'pabilo_binance');
  assert.ok(mockFetch.calls[2].url.includes('/userbankpayment/888/betaserio'));

  await createProCheckout({
    db,
    uid: 'u_pm_route',
    planId: 'monthly',
    methodId: 'pago_movil',
    fetchImpl: mockFetch,
    env: TEST_ENV,
    orderIdGenerator: () => 'ord_pm_route',
  });
  const pmRes = await verifyProPayment({
    db,
    uid: 'u_pm_route',
    orderId: 'ord_pm_route',
    rawReference: '00112233',
    fetchImpl: mockFetch,
    env: TEST_ENV,
  });
  assert.equal(pmRes.ok, true);
  assert.equal(pmRes.subscription.provider, 'pabilo_bdv');
  assert.ok(mockFetch.calls[4].url.includes('/userbankpayment/777/betaserio'));
});


