/**
 * Genera la plantilla HTML prémium para el correo de restablecimiento de contraseña.
 * Diseño dark/light responsive con acentos verde esmeralda (#10b981) para Calculadora de Márgenes.
 */
function buildPasswordResetHtml({ resetLink, userEmail }) {
  const currentYear = new Date().getFullYear();
  return `<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Restablecer contraseña - Calculadora de Márgenes</title>
  <style>
    body {
      margin: 0;
      padding: 0;
      background-color: #0b1120;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
      color: #e2e8f0;
      -webkit-font-smoothing: antialiased;
    }
    table {
      border-collapse: collapse;
    }
    .wrapper {
      width: 100%;
      background-color: #0b1120;
      padding: 40px 16px;
    }
    .card {
      max-width: 520px;
      margin: 0 auto;
      background-color: #1e293b;
      border: 1px solid #334155;
      border-radius: 16px;
      overflow: hidden;
      box-shadow: 0 10px 25px -5px rgba(0, 0, 0, 0.5);
    }
    .header {
      padding: 32px 32px 24px;
      text-align: center;
      background-color: #162032;
      border-bottom: 1px solid #334155;
    }
    .badge {
      display: inline-block;
      width: 48px;
      height: 48px;
      line-height: 48px;
      background-color: #064e3b;
      border: 1px solid #10b981;
      border-radius: 12px;
      font-size: 24px;
      margin-bottom: 12px;
    }
    .app-title {
      margin: 0;
      font-size: 20px;
      font-weight: 700;
      color: #f8fafc;
      letter-spacing: -0.02em;
    }
    .body-content {
      padding: 32px;
      color: #cbd5e1;
      font-size: 15px;
      line-height: 1.6;
    }
    .headline {
      margin: 0 0 16px;
      font-size: 18px;
      font-weight: 600;
      color: #ffffff;
    }
    .btn-container {
      text-align: center;
      margin: 32px 0;
    }
    .btn {
      display: inline-block;
      background-color: #10b981;
      color: #ffffff !important;
      text-decoration: none;
      font-weight: 600;
      font-size: 15px;
      padding: 14px 32px;
      border-radius: 10px;
      box-shadow: 0 4px 14px 0 rgba(16, 185, 129, 0.4);
    }
    .secondary-box {
      margin-top: 24px;
      padding: 16px;
      background-color: #0f172a;
      border-radius: 8px;
      border: 1px solid #334155;
      font-size: 13px;
      color: #94a3b8;
      word-break: break-all;
    }
    .secondary-box a {
      color: #34d399;
      text-decoration: none;
    }
    .footer {
      padding: 24px 32px;
      background-color: #131c2e;
      border-top: 1px solid #334155;
      text-align: center;
      font-size: 12px;
      color: #64748b;
      line-height: 1.5;
    }
  </style>
</head>
<body>
  <div class="wrapper">
    <div class="card">
      <div class="header">
        <div class="badge">📊</div>
        <h1 class="app-title">Calculadora de Márgenes</h1>
      </div>
      <div class="body-content">
        <h2 class="headline">Restablece tu contraseña</h2>
        <p>Hola,</p>
        <p>Recibimos una solicitud para restablecer la contraseña de tu cuenta <strong>${userEmail || ''}</strong> en <strong>Calculadora de Márgenes</strong>.</p>
        <p>Para ingresar tu nueva contraseña, presiona el siguiente botón:</p>
        
        <div class="btn-container">
          <a href="${resetLink}" class="btn" target="_blank" rel="noopener noreferrer">
            Cambiar Contraseña
          </a>
        </div>

        <p style="font-size: 13px; color: #94a3b8;">
          Este enlace es seguro y expirará en <strong>1 hora</strong>. Si tú no realizaste esta solicitud, puedes ignorar este mensaje; tu contraseña actual continuará siendo segura y no se modificará.
        </p>

        <div class="secondary-box">
          Si el botón no abre correctamente, copia y pega este enlace en tu navegador:<br>
          <a href="${resetLink}" target="_blank" rel="noopener noreferrer">${resetLink}</a>
        </div>
      </div>
      <div class="footer">
        © ${currentYear} Calculadora de Márgenes · Todos los derechos reservados.<br>
        Este es un correo de seguridad automatizado.
      </div>
    </div>
  </div>
</body>
</html>`;
}

module.exports = { buildPasswordResetHtml };

