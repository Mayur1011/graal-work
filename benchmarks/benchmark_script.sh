#!/usr/bin/env bash

# Usage: ./run_benchmark.sh <benchmark_name> <iterations>

set -euo pipefail

BENCHMARK=${1:-luindex}
ITERATIONS=${2:-5}
DACAPO_JAR=/graal-dev/benchmarks/dacapo-23.11-MR2-chopin.jar
GRAAL_DIR=/graal-dev/graal/compiler
RESULTS_DIR=/graal-dev/benchmarks/results/${BENCHMARK}
DUMP_BASE=/graal-dev/graal_IR

mkdir -p "$RESULTS_DIR"

GRAAL_BASE_FLAGS=(
  -XX:+UnlockExperimentalVMOptions
  -XX:+EnableJVMCI
  -XX:+UseJVMCICompiler
  -XX:+PrintCompilation
  -Xms512m -Xmx2g          # fixed heap so GC noise is consistent (got from GPT)
)

run_config() {
  local MODE=$1          # "pea_on" or "pea_off"
  local EXTRA_FLAGS=("${@:2}")
  local OUT="$RESULTS_DIR/${MODE}.txt"
  local GC_LOG="$RESULTS_DIR/${MODE}_gc.log"
  local DUMP_PATH="${DUMP_BASE}/${BENCHMARK}_${MODE}"

  mkdir -p "$DUMP_PATH"

  echo "========================================"
  echo " Running: $BENCHMARK | Mode: $MODE"
  echo " Iterations: $ITERATIONS"
  echo "========================================"

  cd "$GRAAL_DIR"

  mx vm \
    "${GRAAL_BASE_FLAGS[@]}" \
    "${EXTRA_FLAGS[@]}" \
    "-Xlog:gc*:file=${GC_LOG}:time,uptime,level,tags" \
    -jar "$DACAPO_JAR" \
    --iterations "$ITERATIONS" \
    --no-pre-iteration-gc \
    "$BENCHMARK" \
    2>&1 | tee "$OUT"

  echo ""
  echo ">>> Output saved: $OUT"
  echo ">>> GC log saved: $GC_LOG"
}

echo "Starting benchmark: $BENCHMARK with $ITERATIONS iterations"


echo "=============================================Running with Partial Escape Analysis ON...================================"
run_config "pea_on" \
  -Dgraal.PartialEscapeAnalysis=true

sleep 10

echo ""
echo "=============================================Running with Partial Escape Analysis OFF...==============================="
run_config "pea_off" \
  -Dgraal.PartialEscapeAnalysis=false

echo ""
echo "Both runs complete. Results in: $RESULTS_DIR"