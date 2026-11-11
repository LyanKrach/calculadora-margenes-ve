const functions = require("firebase-functions");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");
const { buildPasswordResetHtml } = require("./email-template");
const {
  ProPaymentError,
  checkRateLimit,
  getProPaymentConfigPayload,
  createProCheckout,
  verifyProPayment,
} = require("./pro-payments");

if (!admin.apps.length) {
  admin.initializeApp();
}

const PABILO_API_KEY = defineSecret("PABILO_API_KEY");
const PABILO_USER_BANK_ID = defineSecret("PABILO_USER_BANK_ID");

function applyCors(res, methods = "POST, OPTIONS") {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
  res.set("Access-Control-Allow-Methods", methods);
}

function getClientIp(req) {
  const fwd = req.headers && req.headers["x-forwarded-for"];
  if (typeof fwd === "string" && fwd.trim()) {
    return fwd.split(",")[0].trim();
  }
  return req.ip || "unknown";
}

function readRuntimeSecrets() {
  return {
    apiKey: PABILO_API_KEY.value() || process.env.PABILO_API_KEY || "",
    userBankId: PABILO_USER_BANK_ID.value() || process.env.PABILO_USER_BANK_ID || "",
    binanceUserBankId: process.env.PABILO_BINANCE_USER_BANK_ID || "",
    baseUrl: process.env.PABILO_BASE_URL || "",
  };
}

async function requireAuthUser(req) {
  const authHeader = String((req.headers && req.headers.authorization) || "");
  if (!authHeader.startsWith("Bearer ")) {
    throw new ProPaymentError(401, "UNAUTHORIZED", "Debes iniciar sesión para continuar con el pago.");
  }
  const idToken = authHeader.slice(7).trim();
  if (!idToken) {
    throw new ProPaymentError(401, "UNAUTHORIZED", "Sesión inválida. Vuelve a iniciar sesión.");
  }
  let decoded;
  try {
    decoded = await admin.auth().verifyIdToken(idToken);
  } catch {
    throw new ProPaymentError(401, "INVALID_TOKEN", "Tu sesión expiró. Vuelve a iniciar sesión.");
  }
  const signInProvider = decoded && decoded.firebase && decoded.firebase.sign_in_provider;
  if (signInProvider === "anonymous") {
    throw new ProPaymentError(
      403,
      "ANONYMOUS_NOT_ALLOWED",
      "Inicia sesión con tu correo o Google para vincular la suscripción Pro a tu cuenta.",
    );
  }
  return { uid: decoded.uid, email: decoded.email || "" };
}

function sendPaymentError(res, err) {
  if (err instanceof ProPaymentError) {
    return res.status(err.status).json({
      ok: false,
      code: err.code,
      message: err.message,
      ...(err.extra || {}),
    });
  }
  console.error("Error inesperado en módulo Pro/Pabilo:", err && err.message ? err.message : err);
  return res.status(500).json({
    ok: false,
    code: "INTERNAL_ERROR",
    message: "No pudimos procesar la verificación en este momento. Intenta de nuevo.",
  });
}

/**
 * Función HTTP / Callable para enviar correo de restablecimiento con plantilla HTML prémium.
 */
exports.sendCustomPasswordResetEmail = functions.https.onRequest(async (req, res) => {
  // Configuración de CORS
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
  res.set("Access-Control-Allow-Methods", "POST, OPTIONS");

  if (req.method === "OPTIONS") {
    return res.status(204).send("");
  }

  if (req.method !== "POST") {
    return res.status(405).json({ error: "Método no permitido. Usa POST." });
  }

  try {
    const email = (req.body && req.body.email ? req.body.email : "").trim();
    if (!email || !email.includes("@")) {
      return res.status(400).json({ error: "Ingresa un correo electrónico válido." });
    }

    // 1. Verificar si el usuario existe (buenas prácticas OWASP para evitar enumeración)
    try {
      await admin.auth().getUserByEmail(email);
    } catch (userErr) {
      if (userErr.code === "auth/user-not-found") {
        return res.status(200).json({
          success: true,
          message: "Si la cuenta existe en el sistema, recibirás el correo de restablecimiento.",
        });
      }
      throw userErr;
    }

    // 2. Generar enlace seguro de Firebase
    let resetLink;
    try {
      resetLink = await admin.auth().generatePasswordResetLink(email);
    } catch (linkErr) {
      console.warn(`No se pudo generar el enlace para ${email}:`, linkErr.message);
      return res.status(200).json({
        success: true,
        message: "Si la cuenta existe en el sistema, recibirás el correo de restablecimiento.",
      });
    }

    // 3. Renderizar plantilla HTML personalizada
    const htmlContent = buildPasswordResetHtml({ resetLink, userEmail: email });
    const textFallback = `Hola,\n\nPara restablecer tu contraseña en Calculadora de Márgenes, visita el siguiente enlace:\n${resetLink}\n\nEste enlace expira en 1 hora.`;

    // 4. Enviar correo usando el proveedor configurado (Resend o SMTP)
    const resendApiKey = process.env.RESEND_API_KEY;
    const smtpHost = process.env.SMTP_HOST;

    const replyTo = process.env.REPLY_TO || "sopoterefillstore@gmail.com";

    if (resendApiKey) {
      const { Resend } = require("resend");
      const resend = new Resend(resendApiKey);

      const fromAddress = process.env.FROM_EMAIL || "Calculadora de Márgenes <onboarding@resend.dev>";
      const result = await resend.emails.send({
        from: fromAddress,
        to: email,
        reply_to: replyTo,
        subject: "Restablece tu contraseña - Calculadora de Márgenes",
        html: htmlContent,
        text: textFallback,
      });

      return res.status(200).json({ success: true, provider: "resend", id: result.id });
    } else if (smtpHost) {
      const transporter = nodemailer.createTransport({
        host: smtpHost,
        port: parseInt(process.env.SMTP_PORT || "587", 10),
        secure: process.env.SMTP_SECURE === "true",
        auth: {
          user: process.env.SMTP_USER,
          pass: process.env.SMTP_PASS,
        },
      });

      const fromAddress = process.env.FROM_EMAIL || `"Calculadora de Márgenes" <${process.env.SMTP_USER}>`;
      await transporter.sendMail({
        from: fromAddress,
        to: email,
        replyTo: replyTo,
        subject: "Restablece tu contraseña - Calculadora de Márgenes",
        html: htmlContent,
        text: textFallback,
      });

      return res.status(200).json({ success: true, provider: "smtp" });
    } else {
      // Modo desarrollo / log
      console.log(`[DEV] Enlace de restablecimiento para ${email}: ${resetLink}`);
      return res.status(200).json({
        success: true,
        note: "Proveedor no configurado en variables de entorno. Enlace generado en logs.",
        resetLink,
      });
    }
  } catch (error) {
    console.error("Error al enviar correo de recuperación:", error);
    return res.status(500).json({
      error: error.message || "Error al procesar el restablecimiento.",
    });
  }
});

/**
 * Devuelve planes Pro, tasa BCV oficial y datos públicos de pago (sin claves).
 */
exports.getProPaymentConfig = functions.https.onRequest(
  {
    cors: true,
    timeoutSeconds: 20,
    secrets: [PABILO_API_KEY, PABILO_USER_BANK_ID],
  },
  async (req, res) => {
    applyCors(res, "GET, POST, OPTIONS");
    if (req.method === "OPTIONS") return res.status(204).send("");
    if (req.method !== "GET" && req.method !== "POST") {
      return res.status(405).json({ ok: false, message: "Usa GET o POST." });
    }
    try {
      const db = admin.firestore();
      await checkRateLimit({
        db,
        name: "pro_config",
        key: getClientIp(req),
        maxRequests: 30,
        windowMs: 60_000,
      });
      const payload = await getProPaymentConfigPayload({
        db,
        runtimeSecrets: readRuntimeSecrets(),
      });
      return res.status(200).json(payload);
    } catch (err) {
      return sendPaymentError(res, err);
    }
  },
);

/**
 * Crea una orden Pro con tasa BCV y monto en bolívares/USD congelados por 30 min.
 */
exports.createProCheckout = functions.https.onRequest(
  {
    cors: true,
    timeoutSeconds: 25,
    secrets: [PABILO_API_KEY, PABILO_USER_BANK_ID],
  },
  async (req, res) => {
    applyCors(res, "POST, OPTIONS");
    if (req.method === "OPTIONS") return res.status(204).send("");
    if (req.method !== "POST") {
      return res.status(405).json({ ok: false, message: "Método no permitido. Usa POST." });
    }
    try {
      const user = await requireAuthUser(req);
      const db = admin.firestore();
      await checkRateLimit({
        db,
        name: "pro_checkout",
        key: `${user.uid}_${getClientIp(req)}`,
        maxRequests: 12,
        windowMs: 5 * 60_000,
      });
      const body = req.body && typeof req.body === "object" ? req.body : {};
      const result = await createProCheckout({
        db,
        uid: user.uid,
        email: user.email,
        planId: body.plan,
        methodId: body.method,
        runtimeSecrets: readRuntimeSecrets(),
      });
      return res.status(200).json(result);
    } catch (err) {
      return sendPaymentError(res, err);
    }
  },
);

/**
 * Verifica automáticamente la referencia con Pabilo Betaserio y activa Pro al instante.
 */
exports.verifyProPayment = functions.https.onRequest(
  {
    cors: true,
    timeoutSeconds: 60,
    secrets: [PABILO_API_KEY, PABILO_USER_BANK_ID],
  },
  async (req, res) => {
    applyCors(res, "POST, OPTIONS");
    if (req.method === "OPTIONS") return res.status(204).send("");
    if (req.method !== "POST") {
      return res.status(405).json({ ok: false, message: "Método no permitido. Usa POST." });
    }
    try {
      const user = await requireAuthUser(req);
      const db = admin.firestore();
      await checkRateLimit({
        db,
        name: "pro_verify",
        key: `${user.uid}_${getClientIp(req)}`,
        maxRequests: 10,
        windowMs: 5 * 60_000,
      });
      const body = req.body && typeof req.body === "object" ? req.body : {};
      const result = await verifyProPayment({
        db,
        uid: user.uid,
        orderId: body.orderId,
        rawReference: body.reference,
        runtimeSecrets: readRuntimeSecrets(),
      });
      return res.status(result.httpStatus || 200).json(result);
    } catch (err) {
      return sendPaymentError(res, err);
    }
  },
);

