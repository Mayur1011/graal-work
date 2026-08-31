#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
COMPILER_DIR="$WORKSPACE_DIR/graal/compiler"
BUILD_DIR="$SCRIPT_DIR/classes"
RESULTS_DIR="$SCRIPT_DIR/results/$(date +%Y%m%d-%H%M%S)"
TOOLS_DIR="$WORKSPACE_DIR/graal-programs/pea-tools"
echo "Results directory: $RESULTS_DIR"

mkdir -p "$BUILD_DIR" "$RESULTS_DIR"
javac -d "$BUILD_DIR" "$SCRIPT_DIR/Test.java"

# run AllocationInventory to collect allocation bytecodes
javac -d "$BUILD_DIR" "$TOOLS_DIR/AllocationInventory.java"
java -cp "$BUILD_DIR" AllocationInventory \
  --input "$BUILD_DIR" --include Test --output "$RESULTS_DIR/allocation-inventory.csv"

cd "$COMPILER_DIR"
mx vm \
  -XX:+UnlockExperimentalVMOptions \
  -XX:+EnableJVMCI \
  -XX:+UseJVMCICompiler \
  -XX:-TieredCompilation \
  -XX:-BackgroundCompilation \
  -XX:CompileThreshold=100 \
  -XX:CompileCommand=compileonly,Test.* \
  -XX:CompileCommand=dontinline,Test.* \
  -XX:+PrintCompilation \
  -Djdk.graal.TrackNodeSourcePosition=true \
  -Djdk.graal.Counters=PEA_VirtualizedObjects,PEA_MaterializedObjects \
  -Djdk.graal.AggregatedMetricsFile="$RESULTS_DIR/pea-static-aggregate.csv" \
  -Djdk.graal.MetricsFile="$RESULTS_DIR/pea-static-per-compilation.csv" \
  -Djdk.graal.PEARuntimeCounters=true \
  -Djdk.graal.BenchmarkDynamicCounters="out,PEA-MEASUREMENT-START,PEA-MEASUREMENT-END" \
  -Djdk.graal.BenchmarkCountersFile="$RESULTS_DIR/pea-runtime.csv" \
  -Djdk.graal.BenchmarkCountersDumpDynamic=true \
  -Djdk.graal.BenchmarkCountersDumpStatic=false \
  -Djdk.graal.AbortOnBenchmarkCounterOverflow=true \
  -XX:JVMCICounterSize=10000 \
  -Djdk.graal.PEAEffectivenessReport=true \
  -Djdk.graal.PEAEffectivenessReportFile="$RESULTS_DIR/pea-effectiveness.csv" \
  -Djdk.graal.PEAEffectivenessReportFilter=Test \
  -cp "$BUILD_DIR" \
  Test 200000 | tee "$RESULTS_DIR/console.log"

printf '\n=== Compile-time PEA totals ===\n'
grep '^PEA_' "$RESULTS_DIR/pea-static-aggregate.csv" || true

printf '\n=== Runtime PEA totals ===\n'
grep -i 'PEA outcomes' "$RESULTS_DIR/pea-runtime.csv" || true

if [[ ! -f "$RESULTS_DIR/pea-effectiveness.csv" ]]; then
  echo "The compact report was not written." >&2
  echo "Rebuild the modified compiler with: cd /graal-dev/graal/compiler && mx build" >&2
  exit 1
fi
bash "$TOOLS_DIR/pea-summary.sh" \
  "$RESULTS_DIR/allocation-inventory.csv" \
  "$RESULTS_DIR/pea-effectiveness.csv" \
  "$RESULTS_DIR/pea-runtime.csv"
printf '\n=== Detailed PEA allocation-site rows ===\n'
grep '^site;' "$RESULTS_DIR/pea-effectiveness.csv" || true
printf '\nResults directory: %s\n' "$RESULTS_DIR"
