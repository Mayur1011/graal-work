#!/usr/bin/env bash
set -euo pipefail

INVENTORY="$1"
EFFECTIVENESS="$2"
RUNTIME="$3"

summary_value() {
  awk -F';' -v name="$2" '$1 == "summary" && $2 == name { print $3; exit }' "$1"
}

runtime_value() {
  [[ -f "$RUNTIME" ]] || return 0
  awk -F';' -v name="$1" '$2 == "PEA outcomes" && $3 == name { print $4; exit }' "$RUNTIME"
}

total_sites="$(summary_value "$INVENTORY" total_explicit_allocation_sites)"
supported_sites="$(summary_value "$INVENTORY" pea_supported_allocation_sites)"
candidates="$(summary_value "$EFFECTIVENESS" total_candidates)"
not_virtualized="$(summary_value "$EFFECTIVENESS" always_not_virtualized)"
scalar="$(summary_value "$EFFECTIVENESS" always_scalar_replaced)"
materialized="$(summary_value "$EFFECTIVENESS" always_materialized)"
mixed="$(summary_value "$EFFECTIVENESS" mixed)"
total_sites="${total_sites:-0}"
supported_sites="${supported_sites:-0}"
candidates="${candidates:-0}"
not_virtualized="${not_virtualized:-0}"
scalar="${scalar:-0}"
materialized="${materialized:-0}"
mixed="${mixed:-0}"

candidate_exec="$(runtime_value 'candidate executions')"
virtual_exec="$(runtime_value 'initially virtualized')"
materialized_exec="$(runtime_value 'final materialized')"
candidate_exec="${candidate_exec:-0}"
virtual_exec="${virtual_exec:-0}"
materialized_exec="${materialized_exec:-0}"

printf '\n=== Concrete answers: source allocation sites ===\n'
printf '1. Total explicit allocation sites in selected code: %s\n' "$total_sites"
printf '2. Fully scalar-replaced by PEA: %s\n' "$scalar"
printf '3. Virtualized but finally materialized by PEA: %s\n' "$materialized"
printf 'Additional: mixed outcomes across compilation contexts: %s\n' "$mixed"
printf 'Additional: reached PEA but never virtualized: %s\n' "$not_virtualized"
printf 'Additional: PEA-supported but not observed by PEA: %s\n' "$((supported_sites - candidates))"
printf 'Coverage: %s/%s PEA-supported sites were observed by PEA.\n' "$candidates" "$supported_sites"

printf '\n=== Concrete answers: runtime allocation executions ===\n'
printf '1. Logical allocation executions reaching PEA: %s\n' "$candidate_exec"
printf '2. Scalar-replaced executions: %s\n' "$((virtual_exec - materialized_exec))"
printf '3. Virtualized but materialized executions: %s\n' "$materialized_exec"
printf 'Additional: never virtualized executions: %s\n' "$((candidate_exec - virtual_exec))"
printf 'Final heap allocations among PEA candidates: %s\n' "$((candidate_exec - virtual_exec + materialized_exec))"
