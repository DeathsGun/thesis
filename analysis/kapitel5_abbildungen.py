# Abbildungen fuer Kapitel 5 aus den Tabellenwerten (tab:kaltstart-vergleich, tab:overhead).
# Aufruf aus dem Projektordner: python3 analysis/kapitel5_abbildungen.py  (braucht matplotlib)
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.ticker import FixedLocator, FuncFormatter

C = {"Ausgangszustand": "#2a78d6", "Prototyp, Pool 40": "#eb6834", "Prototyp, Pool 0": "#1baf7a"}
M = {"Ausgangszustand": "o", "Prototyp, Pool 40": "s", "Prototyp, Pool 0": "^"}
plt.rcParams.update({"font.family": "sans-serif", "font.size": 9, "axes.edgecolor": "#52514e",
                     "axes.labelcolor": "#0b0b0b", "xtick.color": "#0b0b0b", "ytick.color": "#0b0b0b",
                     "axes.spines.top": False, "axes.spines.right": False, "grid.color": "#e5e4e0", "grid.linewidth": 0.6})
def fmt(v, _):
    return (f"{v/1000:g} s" if v >= 1000 else f"{v:g} ms").replace(".", ",")

# Abb. 1: Kaltstart je Mandant, hyper-int-otc, tab:kaltstart-vergleich (ms)
pct = ["Median", "P90", "P95", "P99", "Max."]
verteilt = {"Ausgangszustand": [2540, 3150, 3330, 4140, 6070], "Prototyp, Pool 40": [375, 499, 1850, 2400, 2410], "Prototyp, Pool 0": [2030, 6240, 8540, 11000, 12000]}
schub = {"Ausgangszustand": [9060, 18900, 19500, 21200, 22000], "Prototyp, Pool 40": [3420, 9710, 10300, 11100, 11400], "Prototyp, Pool 0": [9850, 17700, 18100, 18800, 19200]}
fig, axes = plt.subplots(1, 2, figsize=(6.3, 3.0), sharey=True)
for ax, data, title in ((axes[0], verteilt, "verteilt, ein Mandant je Sekunde"), (axes[1], schub, "Schub, alle 90 zugleich")):
    for name, ys in data.items():
        ax.plot(pct, ys, marker=M[name], ms=5, lw=1.6, color=C[name], label=name, mec="white", mew=0.8)
    ax.set_yscale("log"); ax.set_title(title, fontsize=9, loc="left")
    ax.yaxis.set_major_locator(FixedLocator([100, 200, 500, 1000, 2000, 5000, 10000, 20000]))
    ax.yaxis.set_major_formatter(FuncFormatter(fmt)); ax.yaxis.set_minor_locator(FixedLocator([]))
    ax.grid(True, axis="y"); ax.axhline(2000, color="#52514e", lw=0.8, ls=(0, (3, 3)))
axes[0].set_ylabel("Kaltstart je Mandant")
axes[1].text(0.98, 2000, "2 s ", va="bottom", ha="right", fontsize=8, color="#52514e", transform=axes[1].get_yaxis_transform())
axes[1].legend(frameon=False, fontsize=8, loc="lower right")
fig.tight_layout()
fig.savefig("abbildungen/kaltstart_vergleich.pdf")

# Abb. 2: Overhead im Lastprofil, tab:overhead, Läufe 18, 28 (ms)
pct2 = ["P50", "P90", "P95", "P99"]
runs = {"Ausgangszustand, otc (Lauf 18)": ([259, 1190, 2310, 4570], "#2a78d6", "o"),
        "Prototyp, otc (Lauf 28)": ([127, 164, 180, 268], "#eb6834", "s")}
fig, ax = plt.subplots(figsize=(6.3, 2.9))
for name, (ys, col, mk) in runs.items():
    ax.plot(pct2, ys, marker=mk, ms=5, lw=1.6, color=col, label=name, mec="white", mew=0.8)
    ax.annotate(fmt(ys[-1], None), (pct2[-1], ys[-1]), xytext=(6, 0), textcoords="offset points", fontsize=8, va="center", color="#0b0b0b")
ax.set_yscale("log"); ax.yaxis.set_major_locator(FixedLocator([100, 200, 500, 1000, 2000, 5000]))
ax.yaxis.set_major_formatter(FuncFormatter(fmt)); ax.yaxis.set_minor_locator(FixedLocator([]))
ax.grid(True, axis="y"); ax.set_ylabel("Overhead je Aufruf"); ax.set_xlim(-0.2, 3.9)
ax.legend(frameon=False, fontsize=8, loc="upper left")
fig.tight_layout()
fig.savefig("abbildungen/overhead_lastprofil.pdf")
print("figs ok")
