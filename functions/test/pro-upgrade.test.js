'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  PRO_PLANS,
  ProPaymentError,
  computeUpgradeAdjustment,
  PLAN_ORDER,
  createProCheckout,
} = require('../pro-payments');

function createMinimalFirestore(initial = {}) {
  const store = new Map(Object.entries(initial));
  const clone = (v) => (v === undefined ? undefined : JSON.parse(JSON.stringify(v)));

  function docRef(path) {
    return {
      path,
      id: path.split('/').pop(),
      collection: (sub) => colRef(`${path}/${sub}`),
      get: async () => {
        const val = store.get(path);
        return {
          exists: val !== undefined,
          id: path.split('/').pop(),
          data: () => clone(val),
        };
      },
      set: async (data, opts) => {
        if (opts && opts.merge && store.has(path)) {
          store.set(path, { ...store.get(path), ...clone(data) });
        } else {
          store.set(path, clone(data));
        }
      },
    };
  }

  function colRef(path) {
    return {
      path,
      doc: (id) => docRef(`${path}/${id}`),
    };
  }

  return {
    collection: (name) => colRef(name),
  };
}

function makeMockFetch(bcvUsd = 901.62) {
  return async (url) => {
    if (String(url).includes('ve.dolarapi.com')) {
      return {
        ok: true,
        status: 200,
        json: async () => ({ promedio: bcvUsd, fechaActualizacion: '2026-11-11' }),
      };
    }
    return { ok: true, status: 200, json: async () => ({}) };
  };
}

const TEST_ENV = {
  PABILO_API_KEY: 'test-pabilo-secret',
  PABILO_USER_BANK_ID: '777',
  PABILO_BINANCE_USER_BANK_ID: '888',
  PRO_PM_BANK: 'BDV',
  PRO_PM_PHONE: '04120000000',
};

test('computeUpgradeAdjustment calcula bloqueo de plan actual/inferior y acumulación de días', () => {
  assert.deepEqual(PLAN_ORDER, { monthly: 1, quarterly: 2, semiannual: 3, annual: 4 });
  const nowMs = Date.UTC(2026, 10, 11, 16, 0, 0);
  const subMonthly = {
    plan: 'monthly',
    status: 'active',
    startDate: new Date(nowMs).toISOString(),
    endDate: new Date(nowMs + 30 * 86_400_000).toISOString(),
  };

  const same = computeUpgradeAdjustment({ existingSub: subMonthly, targetPlanId: 'monthly', nowMs });
  assert.equal(same.isCurrentPlan, true);
  assert.equal(same.isLowerPlan, false);
  assert.equal(same.isUpgrade, false);
  assert.equal(same.remainingDays, 30);

  const upQ = computeUpgradeAdjustment({ existingSub: subMonthly, targetPlanId: 'quarterly', nowMs });
  assert.equal(upQ.isCurrentPlan, false);
  assert.equal(upQ.isLowerPlan, false);
  assert.equal(upQ.isUpgrade, true);
  assert.equal(upQ.remainingDays, 30);
  assert.equal(upQ.addedDays, PRO_PLANS.quarterly.durationDays);
  assert.equal(upQ.totalDaysAfter, 120);
  assert.equal(new Date(upQ.newEndDate).getTime(), nowMs + 120 * 86_400_000);

  const subSemi = {
    plan: 'semiannual',
    status: 'active',
    startDate: new Date(nowMs).toISOString(),
    endDate: new Date(nowMs + 180 * 86_400_000).toISOString(),
  };
  const lower = computeUpgradeAdjustment({ existingSub: subSemi, targetPlanId: 'quarterly', nowMs });
  assert.equal(lower.isLowerPlan, true);
  assert.equal(lower.isUpgrade, false);
});

test('createProCheckout bloquea recomprar el mismo plan o bajar de plan mientras está activo', async () => {
  const nowMs = Date.UTC(2026, 10, 11, 16, 0, 0);
  const db = createMinimalFirestore({
    'users/u_active/subscription/current': {
      v: 1,
      plan: 'semiannual',
      status: 'active',
      startDate: new Date(nowMs).toISOString(),
      endDate: new Date(nowMs + 180 * 86_400_000).toISOString(),
    },
  });

  await assert.rejects(
    () => createProCheckout({
      db,
      uid: 'u_active',
      planId: 'semiannual',
      methodId: 'pago_movil',
      createLink: false,
      fetchImpl: makeMockFetch(),
      env: TEST_ENV,
      nowMs,
    }),
    (err) => err instanceof ProPaymentError && err.code === 'ALREADY_ON_THIS_PLAN' && err.status === 409,
  );

  await assert.rejects(
    () => createProCheckout({
      db,
      uid: 'u_active',
      planId: 'monthly',
      methodId: 'pago_movil',
      createLink: false,
      fetchImpl: makeMockFetch(),
      env: TEST_ENV,
      nowMs,
    }),
    (err) => err instanceof ProPaymentError && err.code === 'CANNOT_DOWNGRADE_ACTIVE_PLAN' && err.status === 409,
  );

  const up = await createProCheckout({
    db,
    uid: 'u_active',
    planId: 'annual',
    methodId: 'pago_movil',
    createLink: false,
    fetchImpl: makeMockFetch(),
    env: TEST_ENV,
    nowMs,
    orderIdGenerator: () => 'ord_up_annual',
  });
  assert.equal(up.order.plan, 'annual');
  assert.equal(up.order.upgradeFromPlan, 'semiannual');
  assert.equal(up.order.accumulatedDays, 180);
  assert.equal(up.order.totalDaysWithAccumulation, 545);
  assert.equal(new Date(up.order.projectedEndDate).getTime(), nowMs + 545 * 86_400_000);
});
