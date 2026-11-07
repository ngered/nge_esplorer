"""Icône de NgeEsPlorer : casque de chantier vu de trois quarts et boussole de poche au premier plan, couleurs NGE.

Usage : python tools/icon/app_icon.py assets/icon, puis dart run flutter_launcher_icons.
"""
import math
import sys

from PIL import Image, ImageDraw

NAVY, WHITE, STEEL, STEEL_DARK = '#1E376A', '#FFFFFF', '#C9D3E6', '#8A9BBE'
YELLOW, SHADE, HIGHLIGHT = '#F6C111', '#DDA70C', '#FFE48A'
BRIM_EDGE, CONTACT, RIDGE = '#B8860B', '#D49E0A', '#E3AA0D'
SIZE, SS = 1024, 4

YAW = math.radians(22)  # rotation du casque : l'avant tourné vers la gauche
ROLL = 8  # inclinaison du casque (degrés)

# Point du casque ramené au centre de l'icône : le casque est décalé en haut à gauche pour laisser la place à la
# boussole. Icône adaptative Android : le lanceur peut rogner jusqu'au cercle sûr de 66 dp sur 108 (rayon 0,306 du
# côté) ; l'ensemble est réduit pour y tenir (rayon 0,298), sans retrait supplémentaire du lanceur
# (adaptive_icon_foreground_inset: 0 dans pubspec.yaml).
CENTER = (552, 590)
ADAPTIVE_SCALE = 0.68

# Calotte : demi-ellipsoïde de base (CX, BASE), rayon RX, hauteur H, vu du dessus avec l'aplatissement FLAT
CX, BASE, RX, H = 512, 610, 330, 300
FLAT = 80 / 330

# Boussole, en coordonnées de l'icône : centre, rayons du cadran vu un peu de biais
COMPASS = (690, 690)
COMPASS_RX, COMPASS_RY = 185, 172


def shell(phi, elev, r=RX):
    """Point de la calotte à l'azimut phi (0 : avant du casque) et à l'élévation elev, en coordonnées du dessin."""
    theta = phi - YAW
    return (CX + r * math.cos(elev) * math.sin(theta),
            BASE + r * FLAT * math.cos(elev) * math.cos(theta) - H * math.sin(elev))


def draw_helmet(img, scale):
    def t(x, y):
        return ((512 + (x - CENTER[0]) * scale) * SS, (512 + (y - CENTER[1]) * scale) * SS)

    def ellipse(d, cx, cy, rx, ry, fill):
        d.ellipse([*t(cx - rx, cy - ry), *t(cx + rx, cy + ry)], fill=fill)

    d = ImageDraw.Draw(img)

    # Rebord : mince sur les côtés, visière avancée à l'avant ; tranche puis dessus, ombre portée de la calotte
    def brim(dy):
        pts = []
        for i in range(181):
            phi = math.radians(i * 2)
            r = 360 + 170 * max(0.0, math.cos(phi)) ** 3
            x, y = shell(phi, 0, r)
            pts.append(t(x, y + 15 + dy))
        return pts

    d.polygon(brim(20), fill=BRIM_EDGE)
    d.polygon(brim(0), fill=YELLOW)
    ellipse(d, CX, BASE + 8, RX + 8, (RX + 8) * FLAT, CONTACT)

    # Calotte : ombrée à droite, reflet à gauche, nervure centrale et nervures latérales le long des méridiens
    mask = Image.new('L', img.size, 0)
    md = ImageDraw.Draw(mask)
    md.pieslice([*t(CX - RX, BASE - H), *t(CX + RX, BASE + H)], 180, 360, fill=255)
    ellipse(md, CX, BASE, RX, RX * FLAT, 255)
    dome = Image.new('RGBA', img.size, SHADE)
    dd = ImageDraw.Draw(dome)
    ellipse(dd, 470, 590, 320, 330, YELLOW)
    hx, hy = shell(math.radians(-60), math.radians(48))
    ellipse(dd, hx, hy, 30, 72, HIGHLIGHT)

    def meridian(phi, width):
        pts = [t(*shell(phi, math.radians(e))) for e in range(0, 86, 3)]
        dd.line(pts, fill=RIDGE, width=round(width * scale * SS), joint='curve')

    for deg in (-40, 40):
        meridian(math.radians(deg), 20)
    meridian(0, 56)
    img.paste(dome, (0, 0), mask)


def draw_compass(img, scale):
    def t(x, y):
        return ((512 + (x - 512) * scale) * SS, (512 + (y - 512) * scale) * SS)

    def ellipse(d, cx, cy, rx, ry, fill):
        d.ellipse([*t(cx - rx, cy - ry), *t(cx + rx, cy + ry)], fill=fill)

    cx, cy = COMPASS
    rx, ry = COMPASS_RX, COMPASS_RY
    k = ry / rx

    # Ombre portée sur le casque
    shadow = Image.new('RGBA', img.size, (0, 0, 0, 0))
    ellipse(ImageDraw.Draw(shadow), cx - 22, cy + 6, rx + 6, ry + 6, (20, 30, 60, 90))
    img.alpha_composite(shadow)

    d = ImageDraw.Draw(img)
    # Anneau de suspension, boîtier en relief (tranche décalée), lunette, cadran
    ring_cy = cy - ry - 18
    ellipse(d, cx, ring_cy, 46, 40, STEEL_DARK)
    ellipse(d, cx, ring_cy + 4, 26, 21, NAVY)
    d.rounded_rectangle([*t(cx - 30, cy - ry - 22), *t(cx + 30, cy - ry + 14)], radius=10 * scale * SS, fill=STEEL_DARK)
    ellipse(d, cx + 10, cy + 16, rx, ry, STEEL_DARK)
    ellipse(d, cx, cy, rx, ry, STEEL)
    face = rx - 30
    ellipse(d, cx, cy, face, face * k, NAVY)

    def c(dx, dy):
        return t(cx + dx, cy + dy * k)

    # Graduations : repères cardinaux et intermédiaires
    for ang in range(0, 360, 45):
        a = math.radians(ang)
        major = ang % 90 == 0
        r0, r1 = face * (0.78 if major else 0.85), face * 0.94
        d.line([c(r0 * math.sin(a), -r0 * math.cos(a)), c(r1 * math.sin(a), -r1 * math.cos(a))],
               fill=WHITE, width=round((14 if major else 8) * scale * SS))
    n, w = face * 0.82, face * 0.25
    d.polygon([c(0, -n), c(w, 0), c(-w, 0)], fill=YELLOW)
    d.polygon([c(0, n), c(w, 0), c(-w, 0)], fill=WHITE)
    ellipse(d, cx, cy, face * 0.12, face * 0.12 * k, STEEL)
    ellipse(d, cx, cy, face * 0.05, face * 0.05 * k, NAVY)


def render(path, background, scale):
    helmet = Image.new('RGBA', (SIZE * SS, SIZE * SS), (0, 0, 0, 0))
    draw_helmet(helmet, scale)
    helmet = helmet.rotate(ROLL, resample=Image.BICUBIC, center=(512 * SS, 512 * SS))
    img = Image.new('RGBA', helmet.size, background)
    img.alpha_composite(helmet)
    draw_compass(img, scale)
    img.resize((SIZE, SIZE), Image.LANCZOS).save(path)


out = sys.argv[1]
render(f'{out}/app_icon.png', WHITE, 1)
render(f'{out}/app_icon_foreground.png', (0, 0, 0, 0), ADAPTIVE_SCALE)
