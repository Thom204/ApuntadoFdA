"""Figura 4.1: distancia a la secuencia principal (Richards & Ford, cap. 3).
Datos: tabla Ca/Ce/I/A/D de seccion-4-gobernanza.md (main @ 915652c, arch_scanner.gd).
Uso: python 4.2-secuencia-principal.py  -> 4.2-secuencia-principal.png / .svg
"""
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Polygon

# etiqueta: (I, A, D, grupo, (x_texto, y_texto)) - los modulos en el mismo punto se agrupan
M = {
    "classic, apuntado":         (1.00, 0.00, 0.00, "plugin",  (0.97, 0.31)),
    "rules (kernel)":            (0.26, 0.17, 0.57, "rules",   (0.28, 0.25)),
    "rules/evaluation":          (0.10, 0.00, 0.90, "rules",   (0.13, 0.075)),
    "rules/selection":           (0.43, 0.00, 0.57, "rules",   (0.40, 0.135)),
    "deck, shared":              (0.00, 0.00, 1.00, "core",    (0.02, 0.185)),
    "scoring":                   (0.10, 0.00, 0.90, "core",    (0.13, 0.03)),
    "turn":                      (0.47, 0.13, 0.41, "core",    (0.49, 0.18)),
    "match":                     (0.76, 0.00, 0.24, "core",    (0.735, 0.105)),
    "orchestration":             (0.68, 0.14, 0.17, "core",    (0.70, 0.22)),
    "notification":              (0.67, 0.40, 0.07, "core",    (0.69, 0.44)),
    "persistence":               (0.67, 0.00, 0.33, "adapter", (0.63, 0.06)),
    "network":                   (0.80, 0.00, 0.20, "adapter", (0.83, 0.06)),
}
COL = {"plugin": "#1B7F3B", "rules": "#5B3F99", "core": "#1b365d", "adapter": "#B7791F"}
NAME = {"plugin": "Plug-ins de reglas", "rules": "Núcleo de reglas", "core": "Core de partida",
        "adapter": "Adaptadores"}

fig, ax = plt.subplots(figsize=(7.2, 6.4), dpi=200)
ax.add_patch(Polygon([(0, 0), (0.5, 0), (0, 0.5)], closed=True, color="#FDECEA", zorder=0))
ax.add_patch(Polygon([(1, 1), (0.5, 1), (1, 0.5)], closed=True, color="#FDECEA", zorder=0))
ax.plot([0, 1], [1, 0], color="#555555", lw=1.4, ls="--", zorder=1)
ax.text(0.04, 0.42, "Zona de dolor\n(estable y concreto)", fontsize=9, color="#B03A2E", va="top")
ax.text(0.97, 0.97, "Zona de inutilidad\n(inestable y abstracto)", fontsize=9, color="#B03A2E",
        ha="right", va="top")
ax.text(0.06, 0.97, "Secuencia principal  A + I = 1", fontsize=9, color="#555555", rotation=-41, va="top")
seen = set()
for name, (i, a, d, g, (tx, ty)) in M.items():
    ax.scatter(i, a, s=46, color=COL[g], zorder=3, label=NAME[g] if g not in seen else None,
               edgecolor="white", linewidth=0.8)
    seen.add(g)
    ha = "right" if tx < i else "left"
    ax.annotate(f"{name}  D={d:.2f}".replace(".", ","), (i, a), (tx, ty), fontsize=7.5, ha=ha,
                va="center", color="#222222",
                arrowprops=dict(arrowstyle="-", color="#999999", lw=0.6, shrinkA=0, shrinkB=3))
ax.set_xlim(-0.03, 1.08); ax.set_ylim(-0.03, 1.03)
ax.set_xlabel("Inestabilidad  I = Ce / (Ca + Ce)")
ax.set_ylabel("Abstracción  A = abstractas / clases")
ax.set_title("Distancia a la secuencia principal por módulo", fontsize=11, fontweight="bold")
ax.legend(loc="upper center", fontsize=8, frameon=False, ncol=4, bbox_to_anchor=(0.5, -0.11))
ax.grid(alpha=0.25)
for s in ("top", "right"):
    ax.spines[s].set_visible(False)
fig.tight_layout()
fig.savefig("4.2-secuencia-principal.png")
fig.savefig("4.2-secuencia-principal.svg")
