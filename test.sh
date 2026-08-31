 #!/usr/bin/env bash
  set -euo pipefail

  SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  GRAAL_COMPILER_DIR="$SCRIPT_DIR/graal/compiler"
  DACAPO_JAR="$SCRIPT_DIR/benchmarks/dacapo-23.11-MR2-chopin.jar"
  TOOLS_DIR="$SCRIPT_DIR/graal-programs/pea-tools"

  BENCHMARK="${1:-fop}"
  ITERATIONS="${2:-5}"
  # Use --scope <prefix[,prefix]> to override the benchmark's application scope.
  REPORT_FILTER="${3:-}"
  if [[ "$REPORT_FILTER" == "--scope" ]]; then
    REPORT_FILTER="${4:-}"
  fi
  if [[ -z "$REPORT_FILTER" ]]; then
    case "$BENCHMARK" in
      fop)      REPORT_FILTER="org.apache.fop." ;;
      h2)       REPORT_FILTER="org.h2." ;;
      lusearch) REPORT_FILTER="org.apache.lucene." ;;
      luindex)  REPORT_FILTER="org.apache.lucene." ;;
      avrora)   REPORT_FILTER="avrora." ;;
      pmd)      REPORT_FILTER="net.sourceforge.pmd." ;;
      sunflow)  REPORT_FILTER="org.sunflow." ;;
      xalan)    REPORT_FILTER="org.apache.xalan." ;;
      *)
        echo "No default PEA report filter for benchmark '$BENCHMARK'." >&2
        echo "Pass a class prefix with --scope, for example:" >&2
        echo "  $0 $BENCHMARK $ITERATIONS --scope com.example." >&2
        exit 2
        ;;
    esac
  fi
  RUN_ID="$(date +%Y%m%d-%H%M%S)"
  RESULTS="$SCRIPT_DIR/results/${BENCHMARK}-${RUN_ID}"

  mkdir -p "$RESULTS"
  printf 'PEA allocation-site filter: %s\n' "$REPORT_FILTER"
  mkdir -p "$RESULTS/pea-tools"
  javac -d "$RESULTS/pea-tools" "$TOOLS_DIR/AllocationInventory.java"
  java -cp "$RESULTS/pea-tools" AllocationInventory \
    --input "$DACAPO_JAR" --include "$REPORT_FILTER" --output "$RESULTS/allocation-inventory.csv"
  cd "$GRAAL_COMPILER_DIR"

  mx vm \
    -server \
    -XX:+UseJVMCICompiler \
    -Djvmci.Compiler=graal \
    -Djdk.graal.CompilerConfiguration=community \
    -Xms8g \
    -Xmx8g \
    -XX:+UseSerialGC \
    -XX:-UseCompressedOops \
    -Djava.net.preferIPv4Stack=true \
    \
    -Djdk.graal.Counters=PEA_VirtualizedObjects,PEA_MaterializedObjects \
    -Djdk.graal.AggregatedMetricsFile="$RESULTS/pea-static-aggregate.csv" \
    -Djdk.graal.MetricsFile="$RESULTS/pea-static-per-compilation.csv" \
    \
    -Djdk.graal.PEARuntimeCounters=true \
    -Djdk.graal.BenchmarkDynamicCounters="out, starting ====, PASSED in" \
    -Djdk.graal.BenchmarkCountersFile="$RESULTS/pea-runtime.csv" \
    -Djdk.graal.BenchmarkCountersDumpDynamic=true \
    -Djdk.graal.BenchmarkCountersDumpStatic=false \
    -Djdk.graal.PEAEffectivenessReport=true \
    -Djdk.graal.PEAEffectivenessReportFile="$RESULTS/pea-effectiveness.csv" \
    -Djdk.graal.PEAEffectivenessReportFilter="$REPORT_FILTER" \
    -Djdk.graal.AbortOnBenchmarkCounterOverflow=true \
    -Djdk.graal.ProfileAllocations=true \
    -Djdk.graal.ProfileAllocationsContext=Total \
    -Djdk.graal.TrackNodeSourcePosition=true \
    -XX:JVMCICounterSize=10000 \
    \
    -jar "$DACAPO_JAR" \
    -n "$ITERATIONS" \
    --preserve \
    --scratch-directory "$RESULTS/scratch" \
    "$BENCHMARK" \
    2>&1 | tee "$RESULTS/console.log"

  printf '\n=== Compile-time PEA totals ===\n'
  grep '^PEA_' "$RESULTS/pea-static-aggregate.csv" || true

  printf '\n=== Runtime PEA totals ===\n'
  grep -i 'PEA' "$RESULTS/pea-runtime.csv" || true

  if [[ -f "$RESULTS/pea-effectiveness.csv" ]]; then
    bash "$TOOLS_DIR/pea-summary.sh" \
      "$RESULTS/allocation-inventory.csv" \
      "$RESULTS/pea-effectiveness.csv" \
      "$RESULTS/pea-runtime.csv"
    printf '\n=== Detailed PEA allocation-site rows ===\n'
    grep '^site;' "$RESULTS/pea-effectiveness.csv" || true
  else
    echo 'PEA effectiveness report was not written; rebuild the modified compiler first.' >&2
  fi

  printf '\nResults directory: %s\n' "$RESULTS"
