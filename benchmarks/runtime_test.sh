#!/bin/bash

benchmarks=("avrora" "lusearch" "luindex" "sunflow" "graphchi" "fop" "h2")
ITERATIONS=10
DACAPO_JAR="dacapo-23.11-MR2-chopin.jar"
OUTPUT_DIR="benchmark_results"

mkdir -p "$OUTPUT_DIR"

HOTSPOT_JAVA="$HOME/.sdkman/candidates/java/21.0.2-tem/bin/java"
GRAALVM_JAVA="$HOME/.sdkman/candidates/java/21.0.2-graalce/bin/java"

for benchmark in "${benchmarks[@]}"; do
    RESULT_FILE="$OUTPUT_DIR/${benchmark}.txt"
    
    > "$RESULT_FILE"

    echo "Running benchmark: $benchmark (Saving to $RESULT_FILE)"

    echo "==========================================" >> "$RESULT_FILE"
    echo " Starting Benchmark: $benchmark" >> "$RESULT_FILE"
    echo "==========================================" >> "$RESULT_FILE"

    echo -e "\n---> [1/4] HotSpot (Baseline: No EA)" >> "$RESULT_FILE"
    $HOTSPOT_JAVA -XX:-DoEscapeAnalysis -XX:-EliminateAllocations -jar $DACAPO_JAR -n $ITERATIONS $benchmark >> "$RESULT_FILE" 2>&1

    echo -e "\n---> [2/4] HotSpot (Traditional EA)" >> "$RESULT_FILE"
    $HOTSPOT_JAVA -XX:+DoEscapeAnalysis -XX:+EliminateAllocations -jar $DACAPO_JAR -n $ITERATIONS $benchmark >> "$RESULT_FILE" 2>&1

    echo -e "\n---> [3/4] GraalVM (Baseline: No PEA)" >> "$RESULT_FILE"
    $GRAALVM_JAVA -Dgraal.PartialEscapeAnalysis=false -jar $DACAPO_JAR -n $ITERATIONS $benchmark >> "$RESULT_FILE" 2>&1

    echo -e "\n---> [4/4] GraalVM (Partial EA)" >> "$RESULT_FILE"
    $GRAALVM_JAVA -Dgraal.PartialEscapeAnalysis=true -jar $DACAPO_JAR -n $ITERATIONS $benchmark >> "$RESULT_FILE" 2>&1

    echo -e "\n\n" >> "$RESULT_FILE"

    sleep 10

done
