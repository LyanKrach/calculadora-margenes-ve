const functions = require("firebase-functions");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");
const { buildPasswordResetHtml } = require("./email-template");

if (!admin.apps.length) {
  admin.initializeApp();
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

