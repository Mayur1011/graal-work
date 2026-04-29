#!/bin/bash

benchmarks=("avrora" "lusearch" "luindex" "sunflow" "graphchi" "fop" "h2")
ITERATIONS=10
DACAPO_JAR="dacapo-23.11-MR2-chopin.jar"
OUTPUT_DIR="gc_eval_results"

mkdir -p "$OUTPUT_DIR"

HOTSPOT_JAVA="$HOME/.sdkman/candidates/java/21.0.2-tem/bin/java"
GRAALVM_JAVA="$HOME/.sdkman/candidates/java/21.0.2-graalce/bin/java"

for benchmark in "${benchmarks[@]}"; do
    echo "Processing $benchmark..."

    GRAAL_NO_PEA_LOG="$OUTPUT_DIR/${benchmark}_graal_no_pea.gc.log"
    GRAAL_WITH_PEA_LOG="$OUTPUT_DIR/${benchmark}_graal_with_pea.gc.log"

    echo "Running Graal Baseline (No PEA)..."
    $GRAALVM_JAVA -Dgraal.PartialEscapeAnalysis=false \
                  -Xlog:gc:file=$GRAAL_NO_PEA_LOG \
                  -Xlog:gc+heap=debug \
                  -jar $DACAPO_JAR -n $ITERATIONS $benchmark > /dev/null 2>&1

    sleep 10

    echo "Running Graal Optimized (With PEA)..."
    $GRAALVM_JAVA -Dgraal.PartialEscapeAnalysis=true \
                  -Xlog:gc:file=$GRAAL_WITH_PEA_LOG \
                  -Xlog:gc+heap=debug \
                  -jar $DACAPO_JAR -n $ITERATIONS $benchmark > /dev/null 2>&1

    sum_gc_time() {
        grep "ms" "$1" | sed 's/.* \([0-9.]*\)ms/\1/' | awk '{sum+=$1} END {print sum}'
    }

    TIME_NO_PEA=$(sum_gc_time "$GRAAL_NO_PEA_LOG")
    TIME_WITH_PEA=$(sum_gc_time "$GRAAL_WITH_PEA_LOG")

    echo "------------------------------------------"
    echo "Results for $benchmark:"
    echo "Total GC Pause Time (No PEA):   $TIME_NO_PEA ms"
    echo "Total GC Pause Time (With PEA): $TIME_WITH_PEA ms"
    
    REDUCTION=$(echo "scale=2; (($TIME_NO_PEA - $TIME_WITH_PEA) / $TIME_NO_PEA) * 100" | bc)
    echo "GC Load Reduction: $REDUCTION %"
    echo "------------------------------------------"

    sleep 10
done
