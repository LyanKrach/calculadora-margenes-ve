'use strict';

const functions = require('firebase-functions');
const admin = require('firebase-admin');
const {
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
} = require('./admin-pro');

if (!admin.apps.length) {
  admin.initializeApp();
}

function applyCors(res) {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
}

function getClientIp(req) {
  const fwd = req.headers && req.headers['x-forwarded-for'];
  if (typeof fwd === 'string' && fwd.trim()) {
    return fwd.split(',')[0].trim();
  }
  return req.ip || 'unknown';
}

async function requireAdminUser(req) {
  const authHeader = String((req.headers && req.headers.authorization) || '');
  if (!authHeader.startsWith('Bearer ')) {
    throw new AdminError(401, 'UNAUTHORIZED', 'Debes iniciar sesión para continuar.');
  }
  const idToken = authHeader.slice(7).trim();
  if (!idToken) {
    throw new AdminError(401, 'UNAUTHORIZED', 'Sesión inválida.');
  }
  let decoded;
  try {
    decoded = await admin.auth().verifyIdToken(idToken);
  } catch {
    throw new AdminError(401, 'INVALID_TOKEN', 'Tu sesión expiró. Vuelve a iniciar sesión.');
  }
  if (!isAdminDecodedToken(decoded)) {
    if (isOwnerEmail(decoded.email) && decoded.email_verified !== true) {
      throw new AdminError(
        403,
        'EMAIL_NOT_VERIFIED',
        'Verifica tu correo electrónico o entra con Google para acceder al panel administrador.',
      );
    }
    throw new AdminError(
      403,
      'FORBIDDEN_ADMIN',
      'Esta acción es exclusiva para administradores autorizados.',
    );
  }
  return {
    uid: decoded.uid,
    email: normalizeEmail(decoded.email),
  };
}

/**
 * Panel administrador para cuentas propietarias (activar/regalar/desactivar Pro).
 * Se despliega en codebase independiente (`functions-admin`) sin requerir secretos de Pabilo.
 */
exports.adminManagePro = functions.https.onRequest(
  {
    cors: true,
    timeoutSeconds: 30,
  },
  async (req, res) => {
    applyCors(res);
    if (req.method === 'OPTIONS') return res.status(204).send('');
    if (req.method !== 'POST') {
      return res.status(405).json({ ok: false, message: 'Método no permitido. Usa POST.' });
    }
    try {
      const adminUser = await requireAdminUser(req);
      const db = admin.firestore();
      const auth = admin.auth();
      await checkAdminRateLimit({
        db,
        key: `${adminUser.uid}_${getClientIp(req)}`,
      });

      const body = req.body && typeof req.body === 'object' ? req.body : {};
      const action = String(body.action || '').trim().toLowerCase();

      if (action === 'overview') {
        const result = await adminListOverview({ auth, db, limit: body.limit });
        return res.status(200).json(result);
      }
      if (action === 'lookup') {
        const result = await adminLookupUserByEmail({ auth, db, email: body.email });
        return res.status(200).json(result);
      }
      if (action === 'activate') {
        const result = await adminSetUserPro({
          auth,
          db,
          uid: body.uid,
          email: body.email,
          planId: body.plan,
          durationDays: body.days,
          extend: body.extend === true,
          note: body.note,
          adminEmail: adminUser.email,
        });
        return res.status(200).json(result);
      }
      if (action === 'deactivate') {
        const result = await adminDeactivateUserPro({
          auth,
          db,
          uid: body.uid,
          email: body.email,
          note: body.note,
          adminEmail: adminUser.email,
        });
        return res.status(200).json(result);
      }
      if (action === 'bootstrap_owners') {
        const result = await adminBootstrapOwners({ auth, db });
        return res.status(200).json(result);
      }

      throw new AdminError(
        400,
        'INVALID_ACTION',
        'Acción admin inválida. Usa overview, lookup, activate, deactivate o bootstrap_owners.',
      );
    } catch (err) {
      if (err instanceof AdminError) {
        return res.status(err.status).json({
          ok: false,
          code: err.code,
          message: err.message,
        });
      }
      console.error('Error inesperado en adminManagePro:', err && err.message ? err.message : err);
      return res.status(500).json({
        ok: false,
        code: 'INTERNAL_ERROR',
        message: 'Error interno en el panel administrador.',
      });
    }
  },
);

