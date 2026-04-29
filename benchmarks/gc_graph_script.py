import numpy as np
import matplotlib.pyplot as plt

# Benchmarks
benchmarks = ["avrora", "lusearch", "luindex", "sunflow", "graphchi", "h2"]

# GC Pause Times (ms)
gc_no_pea = np.array([255.786, 636.664, 365.829, 847.047, 2399.29, 5021.58])
gc_pea = np.array([212.477, 617.211, 274.995, 731.208, 1538.55, 4878.11])

# Compute % reduction (positive = improvement)
reduction_pct = (gc_no_pea - gc_pea) / gc_no_pea * 100
avg_reduction = reduction_pct.mean()

x = np.arange(len(benchmarks))
width = 0.32

# Colors
color1 = "#FEEAC9"  # PEA DISABLED
color2 = "#FD7979"  # PEA ENABLED

fig, ax = plt.subplots(figsize=(14, 8))

# Bars
bars1 = ax.bar(x - width/2, gc_no_pea, width, color=color1, label="PEA DISABLED")
bars2 = ax.bar(x + width/2, gc_pea, width, color=color2, label="PEA ENABLED")

# Title
ax.set_title("GC Pause Time Comparison (PEA Disabled vs PEA Enabled)", fontsize=24, fontweight="bold", pad=20)

# Axes
ax.set_ylabel("GC Pause Time (ms)", fontsize=14)
ax.set_xticks(x)
ax.set_xticklabels(benchmarks, fontsize=13)

ax.spines["top"].set_visible(False)
ax.spines["right"].set_visible(False)

for bar in list(bars1) + list(bars2):
    height = bar.get_height()
    ax.text(
        bar.get_x() + bar.get_width()/2,
        height + max(gc_no_pea)*0.01,
        f"{height:.1f}",
        ha="center",
        va="bottom",
        fontsize=11
    )

# Annotate % reduction above each benchmark
for i, pct in enumerate(reduction_pct):
    y = max(gc_no_pea[i], gc_pea[i]) + max(gc_no_pea)*0.12

    # Optional connecting lines
    ax.plot([x[i]-0.25, x[i]+0.25], [y+150, y+150], color=color1, linewidth=2)
    ax.plot([x[i]-0.25, x[i]+0.25], [y-150, y-150], color=color1, linewidth=2)

    ax.text(
        x[i], y,
        f"{pct:+.1f}%",
        ha="center",
        va="center",
        fontsize=14,
        fontweight="bold"
    )

# Legend
ax.legend(loc="upper center", bbox_to_anchor=(0.5, -0.08), ncol=2, frameon=False)

# Y-axis limit
ax.set_ylim(0, max(gc_no_pea)*1.3)

plt.tight_layout()
plt.show()
