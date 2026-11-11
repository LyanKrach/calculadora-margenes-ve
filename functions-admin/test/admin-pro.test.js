'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  ADMIN_EMAILS,
  PRO_PLANS,
  isAdminDecodedToken,
  adminListOverview,
  adminLookupUserByEmail,
  adminSetUserPro,
  adminDeactivateUserPro,
  adminBootstrapOwners,
} = require('../admin-pro');

function createMemoryFirestore(initial = {}) {
  const store = new Map(Object.entries(initial));
  const clone = (v) => (v === undefined ? undefined : JSON.parse(JSON.stringify(v)));
  function docRef(path) {
    return {
      path,
      id: path.split('/').pop(),
      collection(name) { return collectionRef(`${path}/${name}`); },
      async get() {
        const val = store.get(path);
        return { id: path.split('/').pop(), exists: val !== undefined, data: () => clone(val) };
      },
      async set(data, opts = {}) {
        if (opts && opts.merge) {
          store.set(path, Object.assign({}, store.get(path) || {}, clone(data)));
        } else {
          store.set(path, clone(data));
        }
      },
      async delete() { store.delete(path); },
    };
  }
  function collectionRef(path) {
    return { doc(id) { return docRef(`${path}/${id}`); } };
  }
  return {
    collection(name) { return collectionRef(name); },
    async getAll(...refs) { return Promise.all(refs.map((r) => r.get())); },
    async runTransaction(fn) {
      const tx = {
        get: (r) => r.get(),
        set: (r, d, o) => r.set(d, o),
        delete: (r) => r.delete(),
      };
      return fn(tx);
    },
  };
}

test('panel admin: autoriza owners verificados, bootstrap, activa/regala y desactiva Pro', async () => {
  assert.deepEqual([...ADMIN_EMAILS], ['layankrach@gmail.com', 'soporterefillstore@gmail.com']);
  assert.deepEqual(
    Object.values(PRO_PLANS).map((p) => [p.id, p.priceUsd]),
    [
      ['monthly', 1.99],
      ['quarterly', 4.99],
      ['semiannual', 7.99],
      ['annual', 14.99],
    ],
  );
  assert.equal(isAdminDecodedToken({ email: 'layankrach@gmail.com', email_verified: true }), true);
  assert.equal(isAdminDecodedToken({ email: 'SOPORTEREFILLSTORE@GMAIL.COM', email_verified: true }), true);
  assert.equal(isAdminDecodedToken({ email: 'layankrach@gmail.com', email_verified: false }), false);
  assert.equal(isAdminDecodedToken({ email: 'otro@gmail.com', email_verified: true }), false);
  assert.equal(isAdminDecodedToken({ email: 'otro@gmail.com', admin: true }), true);

  const authUsers = [
    { uid: 'uid_owner_1', email: 'layankrach@gmail.com', emailVerified: true, displayName: 'Layan', metadata: {} },
    { uid: 'uid_owner_2', email: 'soporterefillstore@gmail.com', emailVerified: true, displayName: 'Soporte', metadata: {} },
    { uid: 'uid_cliente', email: 'cliente@tienda.com', emailVerified: true, displayName: 'Cliente', metadata: {} },
  ];
  const mockAuth = {
    async listUsers() { return { users: authUsers }; },
    async getUser(uid) {
      const found = authUsers.find((u) => u.uid === uid);
      if (!found) throw new Error('not-found');
      return found;
    },
    async getUserByEmail(email) {
      const norm = String(email || '').trim().toLowerCase();
      const found = authUsers.find((u) => u.email.toLowerCase() === norm);
      if (!found) throw new Error('not-found');
      return found;
    },
  };

  const db = createMemoryFirestore({
    'users/uid_cliente/subscription/pending': {
      plan: 'quarterly',
      method: 'pago_movil',
      reference: '998877',
      status: 'pending',
    },
  });

  const nowMs = Date.UTC(2026, 10, 11, 12, 0, 0);
  const boot = await adminBootstrapOwners({ auth: mockAuth, db, nowMs });
  assert.equal(boot.owners.every((o) => o.status === 'activated'), true);

  const lookup = await adminLookupUserByEmail({ auth: mockAuth, db, email: 'CLIENTE@TIENDA.COM', nowMs });
  assert.equal(lookup.user.uid, 'uid_cliente');
  assert.equal(lookup.user.isPro, false);
  assert.equal(lookup.user.pending.reference, '998877');

  const act = await adminSetUserPro({
    auth: mockAuth,
    db,
    email: 'cliente@tienda.com',
    planId: 'monthly',
    durationDays: 30,
    note: 'Regalo mes amigo',
    adminEmail: 'layankrach@gmail.com',
    nowMs,
  });
  assert.equal(act.ok, true);
  assert.equal(act.user.isPro, true);
  assert.equal(act.user.daysLeft, 30);
  assert.equal(act.user.pending, null);

  const overview = await adminListOverview({ auth: mockAuth, db, nowMs });
  assert.equal(overview.stats.totalUsers, 3);
  assert.equal(overview.stats.activePro, 3);
  assert.equal(overview.stats.pendingManual, 0);

  const deact = await adminDeactivateUserPro({
    auth: mockAuth,
    db,
    uid: 'uid_cliente',
    note: 'Fin de prueba',
    adminEmail: 'soporterefillstore@gmail.com',
    nowMs: nowMs + 1000,
  });
  assert.equal(deact.ok, true);
  assert.equal(deact.user.isPro, false);
  assert.equal(deact.user.status, 'canceled');
});

