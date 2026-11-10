"""
Script para generar el logotipo y los iconos de la app "Calculadora de Márgenes VE".
Genera una composición profesional de alta resolución:
- Fondo redondeado (squircle) con gradiente moderno slate-dark y acentos verde esmeralda.
- Silueta de calculadora moderna con pantalla digital neon.
- Flecha de crecimiento de margen financiero (trend-up arrow) y símbolos % y $.
- Exporta en todas las densidades de Android (mdpi, hdpi, xhdpi, xxhdpi, xxxhdpi) y assets.
"""

import math
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

def create_app_logo(size=1024):
    # Imagen RGBA con supersampling 2x para antialiasing perfecto
    scale = 2
    canvas_size = size * scale
    img = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    pad = int(48 * scale)
    box = [pad, pad, canvas_size - pad, canvas_size - pad]
    radius = int(220 * scale)

    # 1. Base del icono: Squircle con gradiente vertical elegante
    # (de #0F172A slate oscuro a #064E3B verde oscuro/esmeralda)
    mask = Image.new("L", (canvas_size, canvas_size), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle(box, radius=radius, fill=255)

    gradient = Image.new("RGBA", (canvas_size, canvas_size))
    g_draw = ImageDraw.Draw(gradient)
    top_color = (15, 23, 42, 255)      # #0F172A
    mid_color = (13, 37, 34, 255)      # Tono medio verdoso
    bottom_color = (6, 78, 59, 255)    # #064E3B

    for y in range(canvas_size):
        ratio = y / canvas_size
        if ratio < 0.5:
            sub = ratio / 0.5
            r = int(top_color[0] + (mid_color[0] - top_color[0]) * sub)
            g = int(top_color[1] + (mid_color[1] - top_color[1]) * sub)
            b = int(top_color[2] + (mid_color[2] - top_color[2]) * sub)
        else:
            sub = (ratio - 0.5) / 0.5
            r = int(mid_color[0] + (bottom_color[0] - mid_color[0]) * sub)
            g = int(mid_color[1] + (bottom_color[1] - mid_color[1]) * sub)
            b = int(mid_color[2] + (bottom_color[2] - mid_color[2]) * sub)
        g_draw.line([(0, y), (canvas_size, y)], fill=(r, g, b, 255))

    img.paste(gradient, (0, 0), mask)

    # 2. Borde exterior brillante verde esmeralda neón (#22C55E)
    border_width = int(12 * scale)
    draw.rounded_rectangle(
        box,
        radius=radius,
        outline=(34, 197, 94, 200),
        width=border_width,
    )

    # 3. Silueta de la calculadora en el centro
    # Dimensiones de la calculadora
    calc_left = int(240 * scale)
    calc_top = int(220 * scale)
    calc_right = int(784 * scale)
    calc_bottom = int(820 * scale)
    calc_box = [calc_left, calc_top, calc_right, calc_bottom]
    calc_radius = int(80 * scale)

    # Sombra de la calculadora
    shadow_mask = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    s_draw = ImageDraw.Draw(shadow_mask)
    s_draw.rounded_rectangle(calc_box, radius=calc_radius, fill=(0, 0, 0, 160))
    shadow_mask = shadow_mask.filter(ImageFilter.GaussianBlur(int(20 * scale)))
    img = Image.alpha_composite(img, shadow_mask)
    draw = ImageDraw.Draw(img)

    # Cuerpo de la calculadora: gris pizarra oscuro (#1E293B)
    draw.rounded_rectangle(
        calc_box,
        radius=calc_radius,
        fill=(30, 41, 59, 245),
        outline=(51, 65, 85, 255),
        width=int(6 * scale),
    )

    # 4. Pantalla de la calculadora: Neon Emerald Glow
    screen_left = calc_left + int(48 * scale)
    screen_top = calc_top + int(48 * scale)
    screen_right = calc_right - int(48 * scale)
    screen_bottom = screen_top + int(140 * scale)
    screen_box = [screen_left, screen_top, screen_right, screen_bottom]
    screen_radius = int(32 * scale)

    # Fondo de la pantalla
    draw.rounded_rectangle(
        screen_box,
        radius=screen_radius,
        fill=(6, 78, 59, 255),
        outline=(34, 197, 94, 230),
        width=int(5 * scale),
    )

    # Elementos en la pantalla digital: símbolo "$" a la izquierda, "%" y números a la derecha
    # Líneas estilo display digital neon
    # Dibujamos las barras luminosas de la pantalla digital
    text_color = (34, 197, 94, 255)  # #22C55E

    # 5. Teclado de la calculadora (matriz de teclas elegantes)
    grid_top = screen_bottom + int(44 * scale)
    grid_bottom = calc_bottom - int(54 * scale)
    grid_left = screen_left
    grid_right = screen_right

    rows = 4
    cols = 3
    spacing_x = int(24 * scale)
    spacing_y = int(22 * scale)
    key_w = (grid_right - grid_left - (cols - 1) * spacing_x) // cols
    key_h = (grid_bottom - grid_top - (rows - 1) * spacing_y) // rows
    key_radius = int(24 * scale)

    # Colores de teclas: la mayoría pizarra medio, la tecla de igual o porcentaje en verde neon
    for r in range(rows):
        for c in range(cols):
            kx1 = grid_left + c * (key_w + spacing_x)
            ky1 = grid_top + r * (key_h + spacing_y)
            kx2 = kx1 + key_w
            ky2 = ky1 + key_h
            kbox = [kx1, ky1, kx2, ky2]

            # Tecla destacada en (3, 2): Acción / =
            if r == 3 and c == 2:
                # Tecla verde esmeralda destacada
                draw.rounded_rectangle(
                    kbox,
                    radius=key_radius,
                    fill=(34, 197, 94, 255),
                    outline=(74, 222, 128, 255),
                    width=int(4 * scale),
                )
            elif r == 0:
                # Teclas de funciones superiores (slate más claro)
                draw.rounded_rectangle(
                    kbox,
                    radius=key_radius,
                    fill=(51, 65, 85, 230),
                    outline=(71, 85, 105, 200),
                    width=int(3 * scale),
                )
            else:
                # Teclas numéricas estándar
                draw.rounded_rectangle(
                    kbox,
                    radius=key_radius,
                    fill=(15, 23, 42, 220),
                    outline=(51, 65, 85, 180),
                    width=int(3 * scale),
                )

    # 6. Gran Flecha de Crecimiento / Margen (Trend-Up Arrow) Neón
    # Superpuesta elegantemente desde la esquina inferior izquierda hacia arriba a la derecha
    # Con brillo exterior (glow)
    arrow_overlay = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    a_draw = ImageDraw.Draw(arrow_overlay)

    # Coordenadas de la flecha de ganancia / margen
    # Curva o línea que asciende diagonalmente con cabeza de flecha
    start_pt = (calc_left - int(30 * scale), calc_bottom - int(80 * scale))
    mid_pt = (canvas_size // 2, canvas_size // 2 - int(40 * scale))
    end_pt = (calc_right + int(60 * scale), calc_top - int(60 * scale))

    # Glow de la flecha
    glow_color = (34, 197, 94, 90)
    arrow_color = (240, 253, 244, 255) # Blanco suave con tinte esmeralda
    stroke_w = int(28 * scale)

    # Trazo de la flecha con cabeza
    ax1, ay1 = int(320 * scale), int(680 * scale)
    ax2, ay2 = int(720 * scale), int(260 * scale)

    # Cabeza de flecha
    head_len = int(90 * scale)
    angle = math.atan2(ay2 - ay1, ax2 - ax1)

    # Dibujar glow
    for w in [stroke_w + int(24 * scale), stroke_w + int(12 * scale), stroke_w]:
        col = (34, 197, 94, 70 if w > stroke_w else 240)
        a_draw.line([(ax1, ay1), (ax2, ay2)], fill=col, width=w)
        # Cabeza
        left_angle = angle + math.pi - math.radians(30)
        right_angle = angle + math.pi + math.radians(30)
        p1 = (ax2 + head_len * math.cos(left_angle), ay2 + head_len * math.sin(left_angle))
        p2 = (ax2 + head_len * math.cos(right_angle), ay2 + head_len * math.sin(right_angle))
        a_draw.polygon([(ax2, ay2), p1, p2], fill=col)

    # Núcleo brillante blanco/esmeralda
    a_draw.line([(ax1, ay1), (ax2, ay2)], fill=(255, 255, 255, 255), width=int(14 * scale))
    head_inner = int(76 * scale)
    p1_in = (ax2 + head_inner * math.cos(angle + math.pi - math.radians(28)),
             ay2 + head_inner * math.sin(angle + math.pi - math.radians(28)))
    p2_in = (ax2 + head_inner * math.cos(angle + math.pi + math.radians(28)),
             ay2 + head_inner * math.sin(angle + math.pi + math.radians(28)))
    a_draw.polygon([(ax2, ay2), p1_in, p2_in], fill=(255, 255, 255, 255))

    # Badge circular con el símbolo "%" en la esquina superior izquierda
    badge_center = (calc_left + int(40 * scale), calc_top + int(40 * scale))
    badge_r = int(72 * scale)
    badge_box = [badge_center[0] - badge_r, badge_center[1] - badge_r,
                 badge_center[0] + badge_r, badge_center[1] + badge_r]
    a_draw.ellipse(badge_box, fill=(34, 197, 94, 255), outline=(255, 255, 255, 240), width=int(6 * scale))

    # Símbolo % dentro del badge (dibujado geométricamente para evitar dependencia de fuentes)
    bx, by = badge_center
    s_r = int(14 * scale)
    # círculo superior izquierdo
    a_draw.ellipse([bx - int(34 * scale) - s_r, by - int(30 * scale) - s_r,
                    bx - int(34 * scale) + s_r, by - int(30 * scale) + s_r],
                   outline=(255, 255, 255, 255), width=int(8 * scale))
    # círculo inferior derecho
    a_draw.ellipse([bx + int(34 * scale) - s_r, by + int(30 * scale) - s_r,
                    bx + int(34 * scale) + s_r, by + int(30 * scale) + s_r],
                   outline=(255, 255, 255, 255), width=int(8 * scale))
    # barra diagonal
    a_draw.line([(bx + int(38 * scale), by - int(40 * scale)),
                 (bx - int(38 * scale), by + int(40 * scale))],
                fill=(255, 255, 255, 255), width=int(10 * scale))

    # Fusionar flecha y badge con la imagen principal
    img = Image.alpha_composite(img, arrow_overlay)

    # Reducir con Lanczos de alta calidad a tamaño final
    final_icon = img.resize((size, size), Image.Resampling.LANCZOS)
    return final_icon

if __name__ == "__main__":
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    res_dir = os.path.join(base_dir, "android", "app", "src", "main", "res")
    assets_dir = os.path.join(base_dir, "assets", "icon")
    os.makedirs(assets_dir, exist_ok=True)

    print("Generando logo maestro de 1024x1024...")
    master = create_app_logo(1024)

    # Guardar logo en assets (512x512 y 1024x1024)
    master.save(os.path.join(assets_dir, "app_logo_1024.png"), "PNG")
    master.resize((512, 512), Image.Resampling.LANCZOS).save(
        os.path.join(assets_dir, "app_logo.png"), "PNG"
    )
    print("Guardado en assets/icon/app_logo.png")

    # Densidades de Android para ic_launcher.png
    densities = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }

    for folder, px in densities.items():
        target_folder = os.path.join(res_dir, folder)
        os.makedirs(target_folder, exist_ok=True)
        target_path = os.path.join(target_folder, "ic_launcher.png")
        resized = master.resize((px, px), Image.Resampling.LANCZOS)
        resized.save(target_path, "PNG")
        print(f"Generado {folder}/ic_launcher.png ({px}x{px})")

    print("¡Todos los iconos y logos se generaron con éxito!")

