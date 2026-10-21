#!/usr/bin/env bash
# Baseline vs offline-hint sweep over the inliner's expansion budget (TypicalGraphSize).
# Lower TypicalGraphSize => higher expansion threshold => marginal callees stop being inlined.
# Usage: sweep.sh [TypicalGraphSize...]   env: SIZE=160 (consume padding), AMP=3.0, BUILD=1
set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PEA="$(cd -- "$HERE/../../.." && pwd)"
GEN="$PEA/self-tests/cases/PEASMITest_sweep"
RES="$HERE/PEASMITest.res"
LIMITS=("$@"); [[ ${#LIMITS[@]} -gt 0 ]] || LIMITS=(1000 750 500 250 0 -250 -500 -750 -1000 -1250 -1500 -1750 -2000 -2500)
SIZE="${SIZE:-160}"; AMP="${AMP:-3.0}"
BUILD_FLAG=(); [[ "${BUILD:-1}" == 1 ]] && BUILD_FLAG=(--build)

run() {  # run [pea-test.sh args...] -> one-line verdict
  "$PEA/pea-test.sh" self PEASMITest_sweep "${BUILD_FLAG[@]}" --vm-option -XX:-UseOnStackReplacement "$@" > /dev/null 2>&1 || { echo "FAILED"; return; }
  BUILD_FLAG=()
  local d; d="$(ls -td "$PEA"/self-tests/results/PEASMITest_sweep-* | head -1)"
  awk -F';' -v d="$d" '$1=="site"{printf "contexts=%s outcomes=%s reasons=%s", $6,$7,$8}' "$d/pea-effectiveness.csv"
  printf ' hint_matched=%s\n' "$(grep -c 'OfflineEscapeHints\] matched' "$d/console.log" || true)"
}

mkdir -p "$GEN"; cp "$HERE/PEACompilationBarrier.java" "$GEN/"
python3 - "$HERE/Test.java" "$GEN/Test.java" "$SIZE" <<'PY'
import re, sys
src, dst, n = sys.argv[1], sys.argv[2], int(sys.argv[3])
lines = [l for l in open(src) if not re.match(r"\s+v = v \* 31 \+ \d+;", l)]
i = next(k for k, l in enumerate(lines) if "int v = h.value;" in l) + 1
lines[i:i] = [f"        v = v * 31 + {k};\n" for k in range(1, n + 1)]
open(dst, "w").writelines(lines)
PY

echo "consume padding=$SIZE, hint amplifier=$AMP, OSR off"
for t in "${LIMITS[@]}"; do
  base="$(run --vm-option "-Djdk.graal.TypicalGraphSize=$t")"
  hint="$(run --vm-option "-Djdk.graal.TypicalGraphSize=$t" --vm-option "-Djdk.graal.OfflineEscapeSummaryFile=$RES" --vm-option "-Djdk.graal.OfflineEscapeBenefitAmplifier=$AMP")"
  printf 'TypicalGraphSize=%-6s base: %s\n%-23s hint: %s\n' "$t" "$base" '' "$hint"
done
echo "Target row: base outcomes=finally_materialized (reasons=call_argument), hint outcomes=scalar_replaced."
