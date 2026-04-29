import numpy as np
import matplotlib.pyplot as plt

benchmarks = ["lusearch", "luindex", "sunflow", "graphchi", "fop", "h2"]
graal_no_pea = np.array([2482, 3175, 4026, 2932, 566, 3921])
graal_pea = np.array([2477, 2952, 3753, 2781, 486, 3854])

# Compute % improvement (positive = speedup)
speedup_pct = (graal_no_pea - graal_pea) / graal_no_pea * 100
avg_speedup = speedup_pct.mean()

x = np.arange(len(benchmarks))
width = 0.32

# # orange = "#ff6a00"
# gray = "#545c6e"

color1 = "#FEEAC9" 
color2 = "#FD7979"

fig, ax = plt.subplots(figsize=(14, 8))

# Bars
bars1 = ax.bar(x - width/2, graal_no_pea, width, color=color1, label="PEA DISABLED")
bars2 = ax.bar(x + width/2, graal_pea, width, color=color2, label="PEA ENABLED")

# Title
ax.set_title("Comparison (PEA disabled vs PEA enabled)", fontsize=28, fontweight="bold", pad=20)

# Axes
ax.set_ylabel("Runtime (ms)", fontsize=14)
ax.set_xticks(x)
ax.set_xticklabels(benchmarks, fontsize=13)

ax.spines["top"].set_visible(False)
ax.spines["right"].set_visible(False)

for bar in list(bars1) + list(bars2):
    height = bar.get_height()
    ax.text(
        bar.get_x() + bar.get_width()/2,
        height + max(graal_no_pea)*0.01,
        f"{int(height)}",
        ha="center",
        va="bottom",
        fontsize=11
    )

for i, pct in enumerate(speedup_pct):
    y = max(graal_no_pea[i], graal_pea[i]) + max(graal_no_pea)*0.12

    ax.plot([x[i]-0.25, x[i]+0.25], [y+200, y+200], color=color2, linewidth=2)
    ax.plot([x[i]-0.25, x[i]+0.25], [y-200, y-200], color=color2, linewidth=2)

    ax.text(
        x[i], y,
        f"{pct:+.2f}%",
        ha="center",
        va="center",
        fontsize=14,
        fontweight="bold"
    )

# ax.text(
#     -0.6,
#     max(graal_no_pea)*0.15,
#     f"Avg. {avg_speedup:.2f}%\nspeed up\nwith PEA",
#     fontsize=14,
#     fontweight="bold",
#     bbox=dict(boxstyle="round,pad=0.5", edgecolor=color1, facecolor="none", linewidth=2)
# )

ax.legend(loc="upper center", bbox_to_anchor=(0.5, -0.08), ncol=2, frameon=False)

ax.set_ylim(0, max(graal_no_pea)*1.3)

plt.tight_layout()
plt.savefig("graal_pea_styled.png", dpi=300, bbox_inches="tight")
plt.show()
