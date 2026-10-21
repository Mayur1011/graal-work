#!/usr/bin/env bash
# SMI self-test runner: for each case, runs a baseline (no hint) and every hinted .res variant
# listed in the case's smi-expect.txt, then compares the measured scalar-replacement rate with the
# expected one and checks that each fact in the .res was matched and actually inlined by Graal.
#
# Usage: ./pea-testing/smi-test.sh [--build] [--force] [--tgs N[,N...]] [--amp X] [--tol PCT] [case ...]
#   --force inline hinted calls unconditionally (OfflineEscapeForceInline). Without it a hint only
#          raises the call's priority by --amp, which a tight shared budget can still outvote.
#   --tgs  inliner budget (TypicalGraphSize). Negative = tighter budget, so the baseline refuses
#          the big callee; the hint must overcome it. Default -2500.
#   --amp  OfflineEscapeBenefitAmplifier (default 3.0).   --tol  allowed rate error in points (2).
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CASES="$ROOT/self-tests/cases"
BUILD=(); FORCE=false; TGS=-2500; AMP=3.0; TOL=2; SELECTED=()
while [[ $# -gt 0 ]]; do case "$1" in
  --build) BUILD=(--build); shift;; --force) FORCE=true; shift;; --tgs) TGS="$2"; shift 2;; --amp) AMP="$2"; shift 2;; --tol) TOL="$2"; shift 2;;
  *) SELECTED+=("$1"); shift;; esac; done
[[ ${#SELECTED[@]} -gt 0 ]] || SELECTED=(PEASMITest PEASMI_virtual PEASMI_return PEASMI_nested PEASMI_selective PEASMI_poly)

FAILURES=0
printf 'mode: %s, amplifier %s, TypicalGraphSize %s\n' "$([[ $FORCE == true ]] && echo 'force-inline' || echo 'priority boost only')" "$AMP" "$TGS"

# run_one CASE RES_OR_EMPTY TGS -> sets RESULT_DIR (the self-test result directory)
run_one() {
  local opts=(--vm-option -XX:-UseOnStackReplacement --vm-option "-Djdk.graal.TypicalGraphSize=$3") log
  [[ -z "$2" ]] || opts+=(--vm-option "-Djdk.graal.OfflineEscapeSummaryFile=$2" --vm-option "-Djdk.graal.OfflineEscapeBenefitAmplifier=$AMP" --vm-option "-Djdk.graal.OfflineEscapeForceInline=$FORCE")
  log="$(mktemp)"
  if ! "$ROOT/pea-test.sh" self "$1" "${BUILD[@]}" "${opts[@]}" > "$log" 2>&1 < /dev/null; then
    tail -25 "$log" >&2; rm -f "$log"; return 1
  fi
  BUILD=()  # build only once
  RESULT_DIR="$(dirname "$(sed -n 's/^Self-test summary: //p' "$log" | tail -1)")"
  rm -f "$log"
}

# facts RES -> one "class.method(desc)@bci" key per fact (the format Graal logs). Like the Java
# parser, peel the numeric callBci[;allocationBci] off the end: the descriptor may contain ';'.
facts() {
  awk -F';' '!/^[[:space:]]*(#|$)/ {
    e = NF
    if (NF >= 5 && $NF ~ /^[0-9]+$/ && $(NF - 1) ~ /^[0-9]+$/) e = NF - 1
    d = $3; for (i = 4; i < e; i++) d = d ";" $i
    printf "%s.%s%s@%s\n", $1, $2, d, $e }' "$1"
}

for name in "${SELECTED[@]}"; do
  dir="$CASES/$name"; expect="$dir/smi-expect.txt"
  [[ -f "$expect" ]] || { echo "skip $name: no smi-expect.txt"; continue; }
  printf '\n=== %s ===\n' "$name"
  IFS=, read -ra TGS_LIST <<< "$TGS"
  for tgs in "${TGS_LIST[@]}"; do
    while read -r variant expected _; do
      [[ -n "$variant" && "$variant" != \#* ]] || continue
      res=""; [[ "$variant" == baseline ]] || res="$dir/$variant"
      if ! run_one "$name" "$res" "$tgs"; then
        printf '%-20s TGS=%-6s RUN FAILED\n' "$variant" "$tgs"; FAILURES=$((FAILURES + 1)); continue
      fi
      summary="$RESULT_DIR/summary.txt"; console="$RESULT_DIR/console.log"
      rate="$(sed -n 's/^Scalar-replacement rate: \([0-9.]*\)%.*/\1/p' "$summary")"
      reasons="$(awk '/runtime=/ && $NF+0 > 0 {printf "%s=%s ", $1, $NF}' "$summary")"
      matched=0; inlined=0; total=0; missing=""
      if [[ -n "$res" ]]; then
        while read -r key; do
          total=$((total + 1))
          if grep -Fxq "[OfflineEscapeHints] matched $key" "$console"; then matched=$((matched + 1)); else missing+=" $key(unmatched)"; fi
          if grep -Fq "[OfflineEscapeHints] inlined $key -> " "$console"; then inlined=$((inlined + 1)); fi
        done < <(facts "$res")
      fi
      if [[ -n "$rate" ]] && awk -v a="$rate" -v e="$expected" -v t="$TOL" 'BEGIN {d = a - e; exit !(d <= t && d >= -t)}'; then verdict=PASS; else verdict=FAIL; FAILURES=$((FAILURES + 1)); fi
      printf '%-20s TGS=%-6s rate=%7s%% (expected %s%%)  facts matched=%d inlined=%d of %d  materialized: %s %s -> %s\n' \
        "$variant" "$tgs" "${rate:-n/a}" "$expected" "$matched" "$inlined" "$total" "${reasons:-none}" "$missing" "$verdict"
    done < "$expect"
  done
done

printf '\n%s\n' "$([[ $FAILURES -eq 0 ]] && echo 'ALL SMI CHECKS PASSED' || echo "$FAILURES SMI CHECK(S) FAILED")"
[[ $FAILURES -eq 0 ]]
