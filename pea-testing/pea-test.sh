#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$(cd -- "$ROOT/.." && pwd)"
COMPILER="${GRAAL_COMPILER_DIR:-$WORKSPACE/graal/compiler}"
DACAPO_JAR_DEFAULT="${DACAPO_JAR:-$WORKSPACE/benchmarks/dacapo-23.11-MR2-chopin.jar}"
INVENTORY_SOURCE="$ROOT/tools/AllocationInventory.java"

usage() {
  cat <<'EOF'
Usage:
  ./pea-testing/pea-test.sh dacapo BENCHMARK [--warmup N] [--forks N]
      [--scope PREFIX[,PREFIX]] [--jar PATH] [--build] [--compiler-events]
      [--vm-option OPTION]

  ./pea-testing/pea-test.sh self CASE [--main CLASS] [--scope PREFIX[,PREFIX]]
      [--classpath PATH] [--markers START END | --whole-process]
      [--build] [--compiler-events] [--vm-option OPTION]
      [-- application-arguments...]

Examples:
  ./pea-testing/pea-test.sh dacapo h2 --warmup 20 --forks 10 --build
  ./pea-testing/pea-test.sh self PEAAllocationTest -- 200000

Self-test cases live in pea-testing/self-tests/cases/CASE and contain Test.java.
EOF
}

die() { printf 'error: %s\n' "$*" >&2; exit 2; }
sanitize() { printf '%s' "$1" | tr -cs '[:alnum:]_.-' '_'; }
summary_value() { awk -F';' -v key="$2" '$1=="summary" && $2==key {print $3; exit}' "$1"; }
runtime_value() { awk -F';' -v key="$2" '$2=="PEA outcomes" && $3==key {print $4; exit}' "$1"; }
counter_value() { awk -F';' -v group="$2" -v key="$3" '$2==group && $3==key {print $4; exit}' "$1"; }
percent() { awk -v n="$1" -v d="$2" 'BEGIN {if(d==0) print "n/a"; else printf "%.2f%%",100*n/d}'; }
rate() { awk -v n="$1" -v d="$2" 'BEGIN {if(d==0) print 0; else printf "%.8f",100*n/d}'; }

MATERIALIZATION_REASONS=(
  call_argument method_return exception_unwind static_field_store instance_field_store array_store
  unsupported_use merge_incompatible phi_incompatible loop_exit_state loop_analysis_limit lock_constraint
  virtualizer_requested object_graph_dependency lock_order_dependency other_unknown
)

effectiveness_value() {
  local value
  value="$(summary_value "$1" "$2")"
  if [[ -n "$value" ]]; then printf '%s\n' "$value"; return; fi
  case "$2" in
    total_candidates) awk -F';' '$1=="site" {n++} END {print n+0}' "$1" ;;
    always_not_virtualized|always_scalar_replaced|always_materialized|mixed)
      awk -F';' -v key="$2" '$1=="site" && $NF==key {n++} END {print n+0}' "$1" ;;
  esac
}

default_scope() {
  # case "$1" in
  #   avrora) printf 'avrora.' ;;
  #   fop) printf 'org.apache.fop.' ;;
  #   h2) printf 'org.h2.' ;;
  #   luindex|lusearch) printf 'org.apache.lucene.' ;;
  #   pmd) printf 'net.sourceforge.pmd.' ;;
  #   sunflow) printf 'org.sunflow.' ;;
  #   xalan) printf 'org.apache.xalan.,org.apache.xpath.,org.apache.xml.' ;;
  #   *) return 1 ;;
  # esac
  case "$1" in
    avrora)     printf 'avrora.' ;;
    batik)      printf 'org.apache.batik.' ;;
    biojava)    printf 'org.biojava.' ;;
    cassandra)  printf 'org.apache.cassandra.,site.ycsb.,com.yahoo.ycsb.' ;;
    eclipse)    printf 'org.eclipse.' ;;
    fop)        printf 'org.apache.fop.' ;;
    graphchi)   printf 'edu.cmu.graphchi.' ;;
    h2)         printf 'org.h2.' ;;
    h2o)        printf 'water.,hex.,ai.h2o.' ;;
    jme)        printf 'com.jme3.' ;;
    jython)     printf 'org.python.' ;;
    kafka)      printf 'org.apache.kafka.,kafka.' ;;
    luindex|lusearch) printf 'org.apache.lucene.' ;;
    pmd)        printf 'net.sourceforge.pmd.' ;;
    spring)     printf 'org.springframework.' ;;
    sunflow)    printf 'org.sunflow.' ;;
    tomcat)     printf 'org.apache.catalina.,org.apache.coyote.,org.apache.tomcat.,org.apache.jasper.' ;;
    tradebeans|tradesoap)
                printf 'org.apache.geronimo.,org.apache.openejb.,org.apache.openjpa.,org.apache.axis2.,org.apache.derby.' ;;
    xalan)      printf 'org.apache.xalan.,org.apache.xpath.,org.apache.xml.' ;;
    zxing)      printf 'com.google.zxing.' ;;
  esac
}

select_jdk() {
  local home="${PEA_TEST_JAVA_HOME:-${JAVA_HOME:-}}" feature
  if [[ -n "$home" ]]; then JAVA="$home/bin/java"; JAVAC="$home/bin/javac";
  else JAVA="$(command -v java || true)"; JAVAC="$(command -v javac || true)"; fi
  [[ -x "$JAVA" && -x "$JAVAC" ]] || die 'java and javac were not found'
  feature="$($JAVAC -version 2>&1 | awk '{split($2,v,".");print v[1]}')"
  [[ "$feature" =~ ^[0-9]+$ && "$feature" -ge 24 ]] || die "JDK 24+ required; found javac $feature"
}

prepare() {
  command -v mx >/dev/null || die 'mx is not on PATH'
  [[ -d "$COMPILER" ]] || die "compiler suite not found: $COMPILER"
  select_jdk
  if "$BUILD"; then (cd "$COMPILER" && mx build --build-logs=silent); fi
}

inventory() {
  local classes="$1" input="$2" scope="$3" output="$4"
  mkdir -p "$classes"
  "$JAVAC" -d "$classes" "$INVENTORY_SOURCE"
  "$JAVA" -cp "$classes" AllocationInventory --input "$input" --include "$scope" --output "$output"
}

vm_options() {
  local directory="$1" scope="$2" start="$3" end="$4"
  VM_OPTS=(
    -XX:+UnlockExperimentalVMOptions -XX:+EnableJVMCI -XX:+UseJVMCICompiler
    -XX:+BackgroundCompilation
    -Djvmci.Compiler=graal -Djdk.graal.CompilerConfiguration=community
    -Djdk.graal.TrackNodeSourcePosition=true
    -Djdk.graal.PEAEffectivenessReport=true
    "-Djdk.graal.PEAEffectivenessReportFile=$directory/pea-effectiveness.csv"
    "-Djdk.graal.PEAMaterializationReasonReportFile=$directory/pea-materialization-reasons.csv"
    "-Djdk.graal.PEAEffectivenessReportFilter=$scope"
    -Djdk.graal.PEARuntimeCounters=true
    "-Djdk.graal.BenchmarkCountersFile=$directory/pea-runtime.csv"
    -Djdk.graal.BenchmarkCountersDumpDynamic=true
    -Djdk.graal.BenchmarkCountersDumpStatic=false
    -Djdk.graal.AbortOnBenchmarkCounterOverflow=true -XX:JVMCICounterSize=10000
  )
  if [[ -n "$start" ]]; then VM_OPTS+=("-Djdk.graal.BenchmarkDynamicCounters=out,$start,$end")
  else VM_OPTS+=(-Djdk.graal.GenericDynamicCounters=true); fi
  if "$COMPILER_EVENTS"; then
    VM_OPTS+=(
      -Djdk.graal.Counters=PEA_VirtualizedObjects,PEA_MaterializedObjects
      "-Djdk.graal.AggregatedMetricsFile=$directory/pea-compiler-events-aggregate.csv"
      "-Djdk.graal.MetricsFile=$directory/pea-compiler-events-per-compilation.csv"
    )
  fi
}

metadata() {
  local output="$1"; shift
  { printf '%s\n' "$@"; "$JAVA" -version 2>&1 | head -1;
    git -C "$WORKSPACE/graal" rev-parse HEAD 2>/dev/null | sed 's/^/graal_commit=/' || true; } > "$output"
}

write_vm_options() {
  local output="$1"; shift
  printf '%s\n' "$@" > "$output"
}

check_output() {
  [[ -f "$1/pea-effectiveness.csv" ]] || die "missing $1/pea-effectiveness.csv"
  [[ -f "$1/pea-runtime.csv" ]] || die "missing $1/pea-runtime.csv; check measurement markers"
  [[ -f "$1/pea-materialization-reasons.csv" ]] || die "missing $1/pea-materialization-reasons.csv"
  grep -q '^summary;total_candidates;' "$1/pea-effectiveness.csv" || \
    die "incomplete PEA effectiveness snapshot in $1/pea-effectiveness.csv; rebuild the reporter and rerun this sample"
  grep -q '^summary;total_final_materialization_occurrences;' "$1/pea-materialization-reasons.csv" || \
    die "incomplete PEA materialization-reason snapshot in $1/pea-materialization-reasons.csv"

  local materialized reason reason_sum=0 value compile_total compile_reason_sum=0
  materialized="$(runtime_value "$1/pea-runtime.csv" 'final materialized')"; materialized="${materialized:-0}"
  for reason in "${MATERIALIZATION_REASONS[@]}"; do
    value="$(counter_value "$1/pea-runtime.csv" 'PEA materialization reasons' "$reason")"; value="${value:-0}"
    reason_sum=$((reason_sum + value))
  done
  [[ "$reason_sum" -eq "$materialized" ]] || \
    die "runtime reason total $reason_sum does not equal final materialized count $materialized"
  compile_total="$(summary_value "$1/pea-materialization-reasons.csv" total_final_materialization_occurrences)"; compile_total="${compile_total:-0}"
  for reason in "${MATERIALIZATION_REASONS[@]}"; do
    value="$(summary_value "$1/pea-materialization-reasons.csv" "reason_$reason")"; value="${value:-0}"
    compile_reason_sum=$((compile_reason_sum + value))
  done
  [[ "$compile_reason_sum" -eq "$compile_total" ]] || \
    die "compile-time reason total $compile_reason_sum does not equal final materialization occurrences $compile_total"
}

print_one_summary() {
  local inv="$1" eff="$2" run="$3" reasons_file="$4"
  local total eligible observed nv ss mat mixed c v m scalar never heap
  total="$(summary_value "$inv" total_explicit_allocation_sites)"; total="${total:-0}"
  eligible="$(summary_value "$inv" pea_eligible_allocation_sites)"; eligible="${eligible:-0}"
  observed="$(effectiveness_value "$eff" total_candidates)"
  nv="$(effectiveness_value "$eff" always_not_virtualized)"
  ss="$(effectiveness_value "$eff" always_scalar_replaced)"
  mat="$(effectiveness_value "$eff" always_materialized)"
  mixed="$(effectiveness_value "$eff" mixed)"
  c="$(runtime_value "$run" 'candidate executions')"; c="${c:-0}"
  v="$(runtime_value "$run" 'initially virtualized')"; v="${v:-0}"
  m="$(runtime_value "$run" 'final materialized')"; m="${m:-0}"
  scalar=$((v-m)); never=$((c-v)); heap=$((never+m))
  printf '=== Static allocation-site outcomes ===\n'
  printf 'Total explicit allocation sites: %d\nPEA-eligible sites by opcode: %d\n' "$total" "$eligible"
  printf 'Sites observed by PEA: %d\nAlways scalar replaced: %d\nAlways materialized: %d\n' "$observed" "$ss" "$mat"
  printf 'Always not virtualized: %d\nMixed across compilation contexts: %d\n' "$nv" "$mixed"
  printf '\n=== Runtime outcomes in measured machine code ===\n'
  printf 'Candidate executions: %d\nInitially virtualized: %d\nScalar replaced: %d\n' "$c" "$v" "$scalar"
  printf 'Virtualized then materialized: %d\nNever virtualized: %d\nFinal heap allocations: %d\n' "$m" "$never" "$heap"
  printf 'Scalar-replacement rate: %s\nFinal-heap rate: %s\n' "$(percent "$scalar" "$c")" "$(percent "$heap" "$c")"
  printf '\n=== Final PEA materialization reasons ===\n'
  printf 'Compile-time final IR occurrences: %s\n' "$(summary_value "$reasons_file" total_final_materialization_occurrences)"
  local reason compile_count runtime_count
  for reason in "${MATERIALIZATION_REASONS[@]}"; do
    compile_count="$(summary_value "$reasons_file" "reason_$reason")"; compile_count="${compile_count:-0}"
    runtime_count="$(counter_value "$run" 'PEA materialization reasons' "$reason")"; runtime_count="${runtime_count:-0}"
    if [[ "$compile_count" -ne 0 || "$runtime_count" -ne 0 ]]; then
      printf '%-32s compile=%5d | runtime=%10d\n' "$reason" "$compile_count" "$runtime_count"
    fi
  done
}

stats() {
  awk -F';' -v col="$2" -v label="$3" 'NR>1 {x=$col+0;n++;s+=x;q+=x*x;if(n==1||x<lo)lo=x;if(n==1||x>hi)hi=x}
    END {mean=n?s/n:0; variance=n>1?(q-s*s/n)/(n-1):0; if(variance<0)variance=0;
      printf "%-42s %15.4f %15.4f %15.4f %15.4f\n",label,mean,sqrt(variance),lo,hi}' "$1"
}

aggregate() {
  local campaign="$1" benchmark="$2" warmup="$3" forks="$4"
  local static="$campaign/aggregate-static.csv" dynamic="$campaign/aggregate-runtime.csv"
  local reason_static="$campaign/aggregate-materialization-reasons-static.csv"
  local reason_dynamic="$campaign/aggregate-materialization-reasons-runtime.csv"
  local stability="$campaign/site-stability.csv" out="$campaign/aggregate-summary.txt"
  local d e r mr c v m scalar never heap reason value
  printf 'fork;observed;not_virtualized;scalar_replaced;materialized;mixed\n' > "$static"
  printf 'fork;candidates;virtualized;scalar_replaced;materialized;never_virtualized;final_heap;scalar_rate;heap_rate\n' > "$dynamic"
  printf 'fork;total' > "$reason_static"; for reason in "${MATERIALIZATION_REASONS[@]}"; do printf ';%s' "$reason" >> "$reason_static"; done; printf '\n' >> "$reason_static"
  printf 'fork;total' > "$reason_dynamic"; for reason in "${MATERIALIZATION_REASONS[@]}"; do printf ';%s' "$reason" >> "$reason_dynamic"; done; printf '\n' >> "$reason_dynamic"
  REPORTS=()
  for ((i=1;i<=forks;i++)); do
    d="$campaign/fork-$(printf '%02d' "$i")"; e="$d/pea-effectiveness.csv"; r="$d/pea-runtime.csv"; mr="$d/pea-materialization-reasons.csv"; REPORTS+=("$e")
    printf '%d;%s;%s;%s;%s;%s\n' "$i" "$(effectiveness_value "$e" total_candidates)" \
      "$(effectiveness_value "$e" always_not_virtualized)" "$(effectiveness_value "$e" always_scalar_replaced)" \
      "$(effectiveness_value "$e" always_materialized)" "$(effectiveness_value "$e" mixed)" >> "$static"
    c="$(runtime_value "$r" 'candidate executions')"; c="${c:-0}"
    v="$(runtime_value "$r" 'initially virtualized')"; v="${v:-0}"
    m="$(runtime_value "$r" 'final materialized')"; m="${m:-0}"
    scalar=$((v-m)); never=$((c-v)); heap=$((never+m))
    printf '%d;%d;%d;%d;%d;%d;%d;%s;%s\n' "$i" "$c" "$v" "$scalar" "$m" "$never" "$heap" \
      "$(rate "$scalar" "$c")" "$(rate "$heap" "$c")" >> "$dynamic"
    printf '%d;%s' "$i" "$(summary_value "$mr" total_final_materialization_occurrences)" >> "$reason_static"
    printf '%d;%d' "$i" "$m" >> "$reason_dynamic"
    for reason in "${MATERIALIZATION_REASONS[@]}"; do
      value="$(summary_value "$mr" "reason_$reason")"; printf ';%s' "${value:-0}" >> "$reason_static"
      value="$(counter_value "$r" 'PEA materialization reasons' "$reason")"; printf ';%s' "${value:-0}" >> "$reason_dynamic"
    done
    printf '\n' >> "$reason_static"; printf '\n' >> "$reason_dynamic"
  done
  awk -F';' -v forks="$forks" 'BEGIN{print "record;class;method;descriptor;bci;forks_observed;not_virtualized;scalar_replaced;materialized;mixed;cross_fork_result"}
    $1=="site" {k=$2 FS $3 FS $4 FS $5; if(!seen[FILENAME SUBSEP k]++){obs[k]++;count[k SUBSEP $NF]++;keys[k]=1}}
    END {for(k in keys){split(k,p,FS); split("always_not_virtualized always_scalar_replaced always_materialized mixed",n," "); kinds=0;last="";
      for(i=1;i<=4;i++)if(count[k SUBSEP n[i]]){kinds++;last=n[i]}
      result=obs[k]<forks?"not_observed_in_all_forks":(kinds==1?"stable_" last:"varies_across_forks");
      printf "site;%s;%s;%s;%s;%d;%d;%d;%d;%d;%s\n",p[1],p[2],p[3],p[4],obs[k],count[k SUBSEP n[1]]+0,count[k SUBSEP n[2]]+0,count[k SUBSEP n[3]]+0,count[k SUBSEP n[4]]+0,result}}' \
    "${REPORTS[@]}" > "$stability"
  {
    printf '=== DaCapo PEA campaign ===\nBenchmark: %s\nWarmups per fork: %d\nMeasured iterations per fork: 1\nIndependent JVM forks: %d\n' "$benchmark" "$warmup" "$forks"
    printf 'Total explicit allocation sites: %s\nPEA-eligible sites: %s\n\n' \
      "$(summary_value "$campaign/allocation-inventory.csv" total_explicit_allocation_sites)" \
      "$(summary_value "$campaign/allocation-inventory.csv" pea_eligible_allocation_sites)"
    printf '%-42s %15s %15s %15s %15s\n' Metric Mean Stddev Minimum Maximum
    stats "$static" 2 'Static sites observed'; stats "$static" 3 'Static always not virtualized'
    stats "$static" 4 'Static always scalar replaced'; stats "$static" 5 'Static always materialized'; stats "$static" 6 'Static mixed'
    stats "$dynamic" 2 'Runtime candidate executions'; stats "$dynamic" 4 'Runtime scalar-replaced executions'
    stats "$dynamic" 5 'Runtime materialized executions'; stats "$dynamic" 6 'Runtime never-virtualized executions'
    stats "$dynamic" 7 'Runtime final heap allocations'; stats "$dynamic" 8 'Runtime scalar-replacement rate (%)'; stats "$dynamic" 9 'Runtime final-heap rate (%)'
    printf '\n=== Final materialization reasons ===\n'
    local column=3
    for reason in "${MATERIALIZATION_REASONS[@]}"; do
      stats "$reason_static" "$column" "Compile-time reason: $reason"
      stats "$reason_dynamic" "$column" "Runtime reason: $reason"
      column=$((column + 1))
    done
    printf '\n=== Cross-fork site stability ===\n'; awk -F';' 'NR>1{n[$NF]++}END{for(k in n)printf "%-42s %d\n",k,n[k]}' "$stability" | sort
  } > "$out"
  cat "$out"
}

MODE="${1:---help}"; [[ "$MODE" != -h && "$MODE" != --help && "$MODE" != help ]] || { usage; exit; }; shift
BUILD=false; COMPILER_EVENTS=false; SCOPE=""; VM_EXTRA_OPTS=()

if [[ "$MODE" == dacapo ]]; then
  [[ $# -gt 0 ]] || die 'benchmark name required'; BENCHMARK="$1"; shift
  WARMUP=20; FORKS=10; DACAPO_JAR="$DACAPO_JAR_DEFAULT"
  while [[ $# -gt 0 ]]; do case "$1" in
    --warmup) WARMUP="$2"; shift 2;; --forks) FORKS="$2"; shift 2;; --scope) SCOPE="$2"; shift 2;;
    --jar) DACAPO_JAR="$2"; shift 2;; --build) BUILD=true; shift;; --compiler-events) COMPILER_EVENTS=true; shift;;
    --vm-option) VM_EXTRA_OPTS+=("$2"); shift 2;;
    *) die "unknown DaCapo option: $1";; esac; done
  [[ "$WARMUP" =~ ^[0-9]+$ ]] || die '--warmup must be nonnegative'; [[ "$FORKS" =~ ^[1-9][0-9]*$ ]] || die '--forks must be positive'
  [[ -n "$SCOPE" ]] || SCOPE="$(default_scope "$BENCHMARK")" || die 'unknown benchmark scope; pass --scope'
  [[ -f "$DACAPO_JAR" ]] || die "DaCapo JAR missing: $DACAPO_JAR"
  DIST="${DACAPO_JAR%.jar}"; [[ -d "$DIST/jar" ]] || die "expanded DaCapo libraries missing: $DIST/jar"
  prepare
  CAMPAIGN="$ROOT/dacapo-tests/results/$(sanitize "$BENCHMARK")-$(date +%Y%m%d-%H%M%S)"; mkdir -p "$CAMPAIGN"
  inventory "$CAMPAIGN/tool-classes" "$DIST/jar" "$SCOPE" "$CAMPAIGN/allocation-inventory.csv"
  metadata "$CAMPAIGN/metadata.txt" "mode=dacapo" "benchmark=$BENCHMARK" "scope=$SCOPE" "warmup=$WARMUP" "forks=$FORKS"
  printf 'Campaign: %s\n' "$CAMPAIGN"
  for ((i=1;i<=FORKS;i++)); do
    D="$CAMPAIGN/fork-$(printf '%02d' "$i")"; mkdir -p "$D"; printf '\n=== Fork %d/%d ===\n' "$i" "$FORKS"
    vm_options "$D" "$SCOPE" ' starting ====' ' PASSED in'
    VM_OPTS+=(-server -Xms8g -Xmx8g -XX:+UseSerialGC -XX:-UseCompressedOops -Djava.net.preferIPv4Stack=true)
    VM_OPTS+=("${VM_EXTRA_OPTS[@]}")
    metadata "$D/metadata.txt" "fork=$i" "warmup=$WARMUP" 'measured=1'
    write_vm_options "$D/vm-options.txt" "${VM_OPTS[@]}"
    (cd "$COMPILER" && mx vm "${VM_OPTS[@]}" -jar "$DACAPO_JAR" -n "$((WARMUP+1))" --preserve --scratch-directory "$D/scratch" "$BENCHMARK") 2>&1 | tee "$D/console.log" || { printf 'dacapo exited non-zero (validation?); see console.log\n' | tee "$D/dacapo-failed.txt" >&2; }
    check_output "$D"; print_one_summary "$CAMPAIGN/allocation-inventory.csv" "$D/pea-effectiveness.csv" "$D/pea-runtime.csv" "$D/pea-materialization-reasons.csv" | tee "$D/summary.txt"
  done
  aggregate "$CAMPAIGN" "$BENCHMARK" "$WARMUP" "$FORKS" | tee "$CAMPAIGN/aggregate-console-summary.txt"
  printf '\nAggregate summary: %s\n' "$CAMPAIGN/aggregate-summary.txt"

elif [[ "$MODE" == self ]]; then
  [[ $# -gt 0 ]] || die 'self-test case required'; CASE="$1"; shift; DIR="$ROOT/self-tests/cases/$CASE"
  MAIN=""; CP=""; START='PEA-MEASUREMENT-START'; END='PEA-MEASUREMENT-END'; ARGS=()

  self_log() { printf '[self][%s] %s\n' "$(date '+%H:%M:%S')" "$*" >&2; }

  self_log "Parsing options for case=$CASE"
  while [[ $# -gt 0 ]]; do case "$1" in
    --main) MAIN="$2"; shift 2;; --scope) SCOPE="$2"; shift 2;; --classpath) CP="$2"; shift 2;;
    --markers) START="$2"; END="$3"; shift 3;; --whole-process) START=''; END=''; shift;;
    --build) BUILD=true; shift;; --compiler-events) COMPILER_EVENTS=true; shift;; --vm-option) VM_EXTRA_OPTS+=("$2"); shift 2;;
    --) shift; ARGS=("$@"); break;;
    *) die "unknown self-test option: $1";; esac; done

  self_log "Checking test source at $DIR/Test.java"
  [[ -f "$DIR/Test.java" ]] || die "missing $DIR/Test.java"

  PACKAGE="$(sed -nE 's/^[[:space:]]*package[[:space:]]+([[:alnum:]_.]+)[[:space:]]*;.*/\1/p' "$DIR/Test.java" | head -1)"
  [[ -n "$MAIN" ]] || MAIN="${PACKAGE:+$PACKAGE.}Test"

  if [[ -z "$SCOPE" ]]; then
    if [[ -n "$PACKAGE" ]]; then SCOPE="$PACKAGE."; else
      mapfile -t NAMES < <(find "$DIR" -name '*.java' -printf '%f\n' | sed 's/\.java$//' | sort -u); SCOPE="$(IFS=,;printf '%s' "${NAMES[*]}")"
    fi
  fi

  self_log "Preparing environment (mx/JDK/build)"
  prepare

  OUT="$ROOT/self-tests/results/$(sanitize "$CASE")-$(date +%Y%m%d-%H%M%S)"
  self_log "Output directory: $OUT"
  mkdir -p "$OUT/app-classes"
  mkdir -p "$OUT/tool-classes"

  self_log "Compiling AllocationInventory tool"
  "$JAVAC" -d "$OUT/tool-classes" "$INVENTORY_SOURCE"

  self_log "Collecting and compiling self-test Java sources"
  mapfile -d '' SOURCES < <(find "$DIR" -name '*.java' -print0 | sort -z)
  JARGS=(-d "$OUT/app-classes"); [[ -z "$CP" ]] || JARGS+=(-cp "$CP")
  "$JAVAC" "${JARGS[@]}" "${SOURCES[@]}"

  self_log "Running allocation inventory"
  "$JAVA" -cp "$OUT/tool-classes" AllocationInventory --input "$OUT/app-classes" --include "$SCOPE" --output "$OUT/allocation-inventory.csv"

  self_log "Writing metadata"
  metadata "$OUT/metadata.txt" 'mode=self' "case=$CASE" "main=$MAIN" "scope=$SCOPE"

  self_log "Preparing VM options"
  vm_options "$OUT" "$SCOPE" "$START" "$END"
  VM_OPTS+=("${VM_EXTRA_OPTS[@]}")
  write_vm_options "$OUT/vm-options.txt" "${VM_OPTS[@]}"
  RCP="$OUT/app-classes${CP:+:$CP}"

  self_log "Launching mx vm (main=$MAIN)"
  self_log "Live log: $OUT/console.log"
  (cd "$COMPILER" && mx vm "${VM_OPTS[@]}" -cp "$RCP" "$MAIN" "${ARGS[@]}") 2>&1 | tee "$OUT/console.log"

  self_log "Validating generated reports"
  check_output "$OUT"

  self_log "Printing summary"
  print_one_summary "$OUT/allocation-inventory.csv" "$OUT/pea-effectiveness.csv" "$OUT/pea-runtime.csv" "$OUT/pea-materialization-reasons.csv" | tee "$OUT/summary.txt"
  printf '\nSelf-test summary: %s\n' "$OUT/summary.txt"

else die "unknown mode: $MODE"; fi
