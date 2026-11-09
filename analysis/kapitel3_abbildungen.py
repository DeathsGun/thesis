# Abbildung zum Hard Floor in Abschnitt 3 (fig:hard-floor-einordnung), zwei Teilgrafiken ohne eigene Titel.
# Die Zahlen stammen aus section_3_2_2_plots.R (Herleitung aus all.ndjson) und stehen so im Kapiteltext.
# Aufruf aus dem Projektordner: python3 analysis/kapitel3_abbildungen.py  (braucht matplotlib)
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt

BLAU, ROT = "steelblue", "firebrick"
plt.rcParams.update({"font.family": "sans-serif", "font.size": 9, "axes.edgecolor": "#52514e",
                     "axes.labelcolor": "#0b0b0b", "xtick.color": "#0b0b0b", "ytick.color": "#0b0b0b",
                     "axes.spines.top": False, "axes.spines.right": False, "grid.color": "#e5e4e0", "grid.linewidth": 0.6})

def balken(datei, namen, werte, beschriftung, ymax):
    fig, ax = plt.subplots(figsize=(3.0, 2.6))
    ax.bar(namen, werte, width=0.6, color=[BLAU, ROT])
    for x, (w, b) in enumerate(zip(werte, beschriftung)):
        ax.annotate(b, (x, w), xytext=(0, 3), textcoords="offset points", ha="center", va="bottom", fontsize=8)
    ax.set_ylim(0, ymax); ax.set_ylabel("Mandanten")
    ax.grid(True, axis="y"); ax.set_axisbelow(True)
    ax.yaxis.set_major_formatter(lambda v, _: f"{v:,.0f}".replace(",", "."))
    fig.subplots_adjust(left=0.25, right=0.97, top=0.95, bottom=0.17)  # feste Ränder, damit beide Achsen gleich hoch sind
    fig.savefig(datei)

GESAMT, HARD_FLOOR = 1718, 713
frei = GESAMT - HARD_FLOOR
anteil = lambda n: f"{n:,}".replace(",", ".") + "\n(" + f"{100 * n / GESAMT:.1f}".replace(".", ",") + " %)"
balken("abbildungen/hard_floor_bestand.pdf", ["Nicht blockiert", "Hard Floor"], [frei, HARD_FLOOR],
       [anteil(frei), anteil(HARD_FLOOR)], 1250)

HTTP, SOCKET = 629, 63
balken("abbildungen/hard_floor_gruppen.pdf", ["HTTP-Gruppe\n(axios u. a.)", "Socket-Gruppe\n(mssql u. a.)"],
       [HTTP, SOCKET], [str(HTTP), str(SOCKET)], 750)
print("figs ok")
