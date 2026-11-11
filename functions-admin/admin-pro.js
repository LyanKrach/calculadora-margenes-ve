'use strict';

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
    priceUsd: 14.99,
    durationDays: 365,
    savePercent: 37,
    recommended: true,
  }),
});

class AdminError extends Error {
  constructor(status, code, message) {
    super(message);
    this.name = 'AdminError';
    this.status = status;
    this.code = code;
  }
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

function computeDates({ existingSub, durationDays, extend = false, nowMs = Date.now() }) {
  const nowDate = new Date(nowMs);
  const nowIso = nowDate.toISOString();
  let baseEnd = nowDate;
  let startDate = nowIso;

  if (extend && existingSub && existingSub.status === 'active' && existingSub.endDate) {
    const parsedEnd = new Date(existingSub.endDate);
    if (!Number.isNaN(parsedEnd.getTime()) && parsedEnd.getTime() > nowMs) {
      baseEnd = parsedEnd;
      if (existingSub.startDate) {
        const parsedStart = new Date(existingSub.startDate);
        if (!Number.isNaN(parsedStart.getTime())) {
          startDate = parsedStart.toISOString();
        }
      }
    }
  }

  const endDate = new Date(baseEnd.getTime() + durationDays * 86_400_000).toISOString();
  return { startDate, endDate, nowIso };
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
      throw new AdminError(404, 'USER_NOT_FOUND', 'No encontramos ese usuario por UID.');
    }
  }
  const cleanEmail = normalizeEmail(email);
  if (!cleanEmail || !cleanEmail.includes('@')) {
    throw new AdminError(400, 'INVALID_EMAIL', 'Escribe un correo electrónico válido.');
  }
  try {
    return await auth.getUserByEmail(cleanEmail);
  } catch {
    throw new AdminError(
      404,
      'USER_NOT_FOUND',
      `No encontramos una cuenta registrada con el correo ${cleanEmail}. Pídele que inicie sesión primero al menos una vez.`,
    );
  }
}

async function checkAdminRateLimit({ db, key, maxRequests = 60, windowMs = 60_000, nowMs = Date.now() }) {
  const safeKey = `pro_admin_${String(key || 'anon').replace(/[^a-zA-Z0-9_-]/g, '_').slice(0, 80)}`;
  const ref = db.collection('rateLimits').doc(safeKey);
  const blocked = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.exists ? snap.data() : null;
    const windowStart = Number(data && data.windowStart) || 0;
    const count = Number(data && data.count) || 0;
    if (windowStart > 0 && nowMs - windowStart < windowMs) {
      if (count >= maxRequests) return true;
      tx.set(ref, { windowStart, count: count + 1, updatedAt: new Date(nowMs).toISOString() }, { merge: true });
      return false;
    }
    tx.set(ref, { windowStart: nowMs, count: 1, updatedAt: new Date(nowMs).toISOString() });
    return false;
  });
  if (blocked) {
    throw new AdminError(429, 'RATE_LIMIT_EXCEEDED', 'Demasiadas solicitudes seguidas. Espera un minuto.');
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
      throw new AdminError(
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
    const { startDate, endDate, nowIso } = computeDates({
      existingSub,
      durationDays: days,
      extend,
      nowMs,
    });

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

async function adminBootstrapOwners({ auth, db, durationDays = 3650, nowMs = Date.now() }) {
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

async function adminListOverview({ auth, db, limit = 100, ensureOwners = true, nowMs = Date.now() }) {
  if (ensureOwners) {
    await adminBootstrapOwners({ auth, db, nowMs });
  }
  const safeLimit = Math.min(Math.max(Number(limit) || 100, 1), 200);
  const listRes = await auth.listUsers(safeLimit);
  const authUsers = (listRes && Array.isArray(listRes.users) ? listRes.users : []).filter(
    (u) => u && !u.disabled && (u.email || '').trim().length > 0,
  );
  const subMap = await readSubsBatch(db, authUsers.map((u) => u.uid));
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
  AdminError,
  normalizeEmail,
  isOwnerEmail,
  isAdminDecodedToken,
  checkAdminRateLimit,
  adminListOverview,
  adminLookupUserByEmail,
  adminSetUserPro,
  adminDeactivateUserPro,
  adminBootstrapOwners,
};

