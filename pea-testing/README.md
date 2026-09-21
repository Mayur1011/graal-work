# Graal PEA testing

All PEA experiments are orchestrated by one command, `pea-test.sh`, but DaCapo
campaigns and controlled self-tests have separate inputs and result trees.

```text
pea-testing/
├── pea-test.sh
├── tools/
│   └── AllocationInventory.java
├── dacapo-tests/
│   └── results/
└── self-tests/
    ├── cases/
    │   ├── PEAAllocationTest/
    │   │   └── Test.java
    │   ├── PEAMaterializationReasonsTest/
    │   │   ├── Test.java
    │   │   └── PEACompilationBarrier.java
    │   ├── Test1/
    │   │   ├── Test.java
    │   │   └── Helper.java
    │   └── Test2/
    │       └── Test.java
    └── results/
```

Generated files never go into a case directory.

## Prerequisites

- `mx` must be on `PATH`.
- JDK 24+ is required by the standard Class-File API used for inventory.
- Select that JDK using `PEA_TEST_JAVA_HOME` or `JAVA_HOME` if it is not the
  default JDK.
- Rebuild after changing Graal instrumentation by passing `--build` once.

## DaCapo campaigns

```bash
./pea-testing/pea-test.sh dacapo h2 --warmup 20 --forks 10 --build
```

Each fork is a new JVM and runs `warmup + 1` DaCapo iterations. DaCapo labels
the first iterations as warmups. The runner's runtime counter markers match
only the final `starting ====` through `PASSED in` interval, giving exactly one
measured runtime sample per fork. Compile-time PEA reporting remains enabled
through warmup because warmup compilation produces the measured machine code.
The runner explicitly enables background compilation because the current
development JVM does not complete JVMCI startup with
`-XX:-BackgroundCompilation`. Use enough warmups for application compilations
to settle before the measured iteration; compare multiple warmup counts when
establishing convergence. Warmup time is a convergence diagnostic in this
experiment, not a benchmark-throughput result.

The top-level DaCapo JAR contains the harness. Keep its expanded distribution
beside it; allocation inventory scans application libraries below its `jar/`
directory.

```text
benchmarks/
├── dacapo-23.11-MR2-chopin.jar
└── dacapo-23.11-MR2-chopin/
    └── jar/
```

Campaign output:

```text
dacapo-tests/results/h2-<timestamp>/
├── allocation-inventory.csv
├── metadata.txt
├── fork-01/
│   ├── pea-effectiveness.csv
│   ├── pea-materialization-reasons.csv
│   ├── pea-runtime.csv
│   ├── vm-options.txt
│   ├── summary.txt
│   └── console.log
├── ...
├── fork-10/
├── aggregate-static.csv
├── aggregate-runtime.csv
├── aggregate-materialization-reasons-static.csv
├── aggregate-materialization-reasons-runtime.csv
├── site-stability.csv
└── aggregate-summary.txt
```

`aggregate-summary.txt` reports mean, sample standard deviation, minimum, and
maximum. Runtime rates are calculated per fork before their statistics are
computed. `site-stability.csv` identifies stable outcomes, outcomes that vary
between compilation contexts/forks, and sites not seen in every fork.

Known DaCapo benchmarks receive an automatic application package scope. Use
`--scope` to override it. Diagnostic compiler-event counters are optional:

```bash
./pea-testing/pea-test.sh dacapo fop --warmup 10 --forks 5 --compiler-events
```

## Self-tests

Each case is a directory beneath `self-tests/cases/` and must contain
`Test.java` with `public static void main`. All Java files below the selected
case are compiled together.

```bash
./pea-testing/pea-test.sh self PEAAllocationTest -- 200000
```

By default, controlled tests must print:

```text
PEA-MEASUREMENT-START
PEA-MEASUREMENT-END
```

around the measured loop. Override markers with `--markers START END`, or use
`--whole-process` when the program cannot emit them. Packaged tests have their
main class and scope inferred from the package declaration in `Test.java`.
Default-package tests infer their scope from the Java filenames. Explicit
overrides remain available:

```bash
./pea-testing/pea-test.sh self Test2 \
  --main experiments.test2.Test \
  --scope experiments.test2. \
  -- 500000
```

Self-test output is isolated under:

```text
self-tests/results/Test2-<timestamp>/
├── allocation-inventory.csv
├── pea-effectiveness.csv
├── pea-materialization-reasons.csv
├── pea-runtime.csv
├── vm-options.txt
├── summary.txt
├── console.log
├── metadata.txt
├── app-classes/
└── tool-classes/
```

## Meaning of the two domains

- Static results count allocation sites identified by class, method,
  descriptor, and bytecode index.
- Runtime results count executions of those logical allocation sites in
  Graal-compiled machine code during the measurement interval.

For runtime counters `C` (candidate), `V` (initially virtualized), and `M`
(finally materialized):

```text
scalar replaced = V - M
never virtualized = C - V
final heap allocations = (C - V) + M
```

The optional `PEA_VirtualizedObjects` and `PEA_MaterializedObjects` CounterKey
values count compiler events and are not unique source-site totals.

## Final materialization reasons

`pea-materialization-reasons.csv` records final materialization occurrences that
survive PEA and reach `CommitAllocationNode` lowering. It contains the source
allocation site and compilation/inlining context, the immediate reason, the root
reason, and the node/source position that triggered materialization. Temporary
materializations that are virtualized again by a later PEA iteration are not
reported.

The bounded reasons are:

```text
call_argument                 method_return
exception_unwind              static_field_store
instance_field_store          array_store
unsupported_use               merge_incompatible
phi_incompatible              loop_exit_state
loop_analysis_limit           lock_constraint
virtualizer_requested         object_graph_dependency
lock_order_dependency         other_unknown
```

`object_graph_dependency` means that the object was pulled into the same commit
because another materialized virtual object referenced it. Its `root_reason`
retains the initiating reason. `lock_order_dependency` similarly identifies
transitive materialization required by strict lock ordering.

The runtime reason counters use the `PEA materialization reasons` counter group.
For every completed run, `pea-test.sh` verifies both invariants:

```text
sum(runtime reason counters) = final materialized executions (M)
sum(compile-time reason occurrences) = final materialization occurrences
```

A source allocation site can have different reasons on different control-flow
paths or inlining contexts. Consequently, the `materialization_reasons` column
in `pea-effectiveness.csv` is a set, and `reason_classification` is
`multiple_reasons` when the set has more than one member.

The controlled category exercise warms both branches of its test graph and then
waits for the compact PEA snapshot before opening the runtime measurement
interval. Its barrier helper is in the excluded `pea.testing` package, so helper
allocations do not enter the `pea.reasons` inventory or counters:

```bash
./pea-testing/pea-test.sh self PEAMaterializationReasonsTest -- 100000
```

These labels identify the IR operation or PEA constraint that triggered
materialization. They are not a separate whole-program proof of thread escape.

Run without `-Djdk.graal.Inline=false`: the default result intentionally
captures the reasons produced after normal Graal inlining. Use `--vm-option`
only for a separately labelled compiler-policy experiment. Every result
directory records the runner-supplied JVM options in `vm-options.txt`.

The test is an end-to-end exercise rather than an assertion that every listed
reason must occur: some compiler-policy categories, especially loop cutoffs and
lock-order constraints, depend on the selected VM configuration and graph shape.
