#!/usr/bin/env bash
# Runs pea-test.sh over several DaCapo benchmarks, 100 iterations per fork
# (WARMUP warm-up + 1 measured), then prints one comparison of runtime reasons.
# Usage: ./pea-testing/dacapo-batch.sh [--build] [--forks N] [--warmup N] [bench ...]
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

BUILD=(); FORKS=5; WARMUP=99; BENCHES=()
while [[ $# -gt 0 ]]; do case "$1" in
  --build) BUILD=(--build); shift;;
  --forks) FORKS="$2"; shift 2;;
  --warmup) WARMUP="$2"; shift 2;;
  *) BENCHES+=("$1"); shift;;
esac; done
[[ ${#BENCHES[@]} -gt 0 ]] || BENCHES=(h2 pmd sunflow xalan fop)

BATCH="$ROOT/dacapo-tests/batch-$(date +%Y%m%d-%H%M%S)"; mkdir -p "$BATCH"
for b in "${BENCHES[@]}"; do
  "$ROOT/pea-test.sh" dacapo "$b" --warmup "$WARMUP" --forks "$FORKS" "${BUILD[@]}" 2>&1 | tee "$BATCH/$b.log"
  BUILD=()  # build only once
  ls -dt "$ROOT"/dacapo-tests/results/"$b"-* | head -1 > "$BATCH/$b.campaign"
done

# One table: mean runtime count per reason, one column per benchmark.
{
  for b in "${BENCHES[@]}"; do
    awk -F'  +' -v b="$b" '/^Runtime (reason|scalar-replacement rate)/ {print b "\t" $1 "\t" $2}' \
      "$(cat "$BATCH/$b.campaign")/aggregate-summary.txt"
  done
} > "$BATCH/long.tsv"
awk -F'\t' '{k[$2]=1; v[$2,$1]=$3; b[$1]=1}
  END{printf "%-45s","metric"; for(x in b)printf " %16s",x; print "";
      for(m in k){printf "%-45s",m; for(x in b)printf " %16s",v[m,x]; print ""}}' "$BATCH/long.tsv" | sort | tee "$BATCH/comparison.txt"
echo "Batch dir: $BATCH"
