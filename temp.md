 Yes—we can divide final PEA materializations into meaningful reason categories at both
  compile time and runtime. The key is to attribute a reason at the exact virtual-to-
  materialized transition, but count it only if that materialization survives into the final
  compiled code.

  ## Important semantic distinction

  A materialized object has not necessarily “escaped” in the Java/thread sense.

  Materialization can happen because:

  - The program exposes the object, such as returning it or passing it to a non-inlined call.
  - PEA cannot represent an operation on the virtual object.
  - Control-flow states cannot be merged.
  - Loop-analysis limits force materialization.
  - Locking constraints require a real object.
  - Another virtual object containing this object is materialized.

  Therefore, the report should use “materialization reason” rather than calling every
  category an “escape reason.”

  Also, PEA cannot prove that an object was actually accessed by another thread. A static-
  field store is potential global/thread publication, but it should be reported as
  static_field_store, not definitively as thread_escape.

  ## Proposed categories

   Family              Category                   Meaning
  ━━━━━━━━━━━━━━━━━━  ━━━━━━━━━━━━━━━━━━━━━━━━━  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   Program escape      call_argument              Passed to a call PEA cannot virtualize
                                                  through
  ──────────────────  ─────────────────────────  ────────────────────────────────────────────
   Program escape      method_return              Returned from the compiled method
  ──────────────────  ─────────────────────────  ────────────────────────────────────────────
   Program escape      exception_unwind           Escapes through a thrown exception
  ──────────────────  ─────────────────────────  ────────────────────────────────────────────
   Program escape      static_field_store         Stored into a static field; potential
                                                  global publication
  ──────────────────  ─────────────────────────  ────────────────────────────────────────────
   Program escape      instance_field_store       Stored into a field of an already
                                                  materialized object
  ──────────────────  ─────────────────────────  ────────────────────────────────────────────
   Program escape      array_store                Stored into an already materialized array
  ──────────────────  ─────────────────────────  ────────────────────────────────────────────
   PEA limitation      unsupported_use            A node uses the object in a way its
                                                  virtualizer cannot handle
  ──────────────────  ─────────────────────────  ────────────────────────────────────────────
   Control flow        merge_incompatible         Virtual states cannot be reconciled at a
                                                  control-flow merge
  ──────────────────  ─────────────────────────  ────────────────────────────────────────────
   Control flow        phi_incompatible           Virtual objects cannot be represented
                                                  through a value phi
  ──────────────────  ─────────────────────────  ────────────────────────────────────────────
   Loop handling       loop_exit_state            Required at an exception-handling loop
                                                  exit
  ──────────────────  ─────────────────────────  ────────────────────────────────────────────
   Loop handling       loop_analysis_limit        Loop cutoff, overflow retry, or
                                                  materialize-all mode
  ──────────────────  ─────────────────────────  ────────────────────────────────────────────
   Locking             lock_constraint            Monitor or lock-order requirement
  ──────────────────  ─────────────────────────  ────────────────────────────────────────────
   Internal request    virtualizer_requested      A Virtualizable node explicitly calls
                                                  ensureMaterialized
  ──────────────────  ─────────────────────────  ────────────────────────────────────────────
   Dependency          object_graph_dependency    Materialized because it is referenced by
                                                  another materialized virtual object
  ──────────────────  ─────────────────────────  ────────────────────────────────────────────
   Dependency          lock_order_dependency      Materialized transitively to preserve
                                                  strict lock order
  ──────────────────  ─────────────────────────  ────────────────────────────────────────────
   Fallback            other_unknown              Ensures every final materialization
                                                  remains accounted for

  The fallback category is essential because it gives the runtime invariant:

  final materialized M = sum of all materialization-reason counters

  ## What the current code already provides

  The central transition is correctly identified in graal/compiler/src/jdk.graal.compiler/
  src/jdk/graal/compiler/virtual/phases/ea/PartialEscapeClosure.java:820:

  ensureMaterialized()
      -> PartialEscapeBlockState.materializeBefore()
      -> materializeWithCommit()
      -> ObjectState.escape()
      -> CommitAllocationNode

  There are currently several distinct callers:

  - Non-virtualizable node input
  - Merge processing
  - Phi processing
  - Loop-exit handling
  - Loop overflow/materialize-all mode
  - Lock-order handling
  - Explicit VirtualizerTool.ensureMaterialized()

  The existing reasonOf(CounterKey) and string reason parameter are a useful experiment, but
  they are insufficient because:

  - COUNTER_MATERIALIZATIONS_UNHANDLED combines calls, returns, stores, unsafe operations,
    and other uses.

  - The reason is not attached to the resulting materialized object.
  - It is not connected to the CSV reporter.
  - It does not produce runtime reason counters.
  - Recursive materializations are not differentiated.
  - It counts PEA decisions that might be undone by a later PEA iteration.

  ## Implementation architecture

  ### 1. Introduce a typed materialization cause

  Replace free-form strings with a bounded category and accompanying diagnostic data:

  MaterializationCause
      category
      family
      trigger node class
      trigger source position
      optional detail
      root category
      propagation kind

  Runtime counter names will use only the bounded category. Details such as method name,
  target method, field, trigger node and BCI belong only in the compile-time CSV. This
  prevents creation of thousands of DynamicCounter names.

  ### 2. Classify non-virtualizable inputs by their actual use

  Currently, graal/compiler/src/jdk.graal.compiler/src/jdk/graal/compiler/virtual/phases/ea/
  PartialEscapeClosure.java:584 knows:

  - The node that could not accept the virtual input
  - The particular input being materialized
  - The insertion position

  It should classify using both the node type and input role.

  Examples:

  CallTargetNode argument                    -> call_argument
  ReturnNode result                          -> method_return
  UnwindNode exception                       -> exception_unwind
  StoreFieldNode value, static field         -> static_field_store
  StoreFieldNode value, instance field       -> instance_field_store
  StoreIndexedNode value                     -> array_store
  MonitorEnterNode object                    -> lock_constraint
  Anything not recognized                    -> unsupported_use

  Input role matters. For example, a virtual object used as the receiver of an unsupported
  field access is different from a virtual object stored as the field value.

  ### 3. Pass causes through every materialization route

  Update all ensureMaterialized() callers to pass an explicit MaterializationCause.

  The existing Graal CounterKey values can remain for compiler diagnostics, but they should
  no longer be the source of semantic classification.

  The direct loop-overflow call to PartialEscapeBlockState.materializeBefore() must also
  receive a cause because it bypasses ensureMaterialized().

  ### 4. Handle transitive materialization explicitly

  graal/compiler/src/jdk.graal.compiler/src/jdk/graal/compiler/virtual/phases/ea/
  PartialEscapeBlockState.java:332 recursively materializes:

  - Virtual objects referenced in fields or array elements
  - Other locked virtual objects needed for strict lock ordering

  Those objects should receive:

  object_graph_dependency
  lock_order_dependency

  The original/root reason should also be retained for diagnostics. For example:

  immediate_reason = object_graph_dependency
  root_reason      = call_argument

  This makes the categories mutually exclusive while preserving the causal chain.

  ### 5. Attach the reason to the materialization occurrence

  The reason should not be stored as one global field on VirtualObjectNode, because the same
  virtual allocation can materialize:

  - In different branches
  - At different commits
  - For different reasons

  The suitable occurrence-specific carrier is AllocatedObjectNode, created for each
  materialized object in materializeWithCommit().

  It can retain:

  - Immediate category
  - Root category
  - Trigger node class
  - Trigger source position
  - Optional detail

  This metadata will naturally disappear if a later PEA iteration re-virtualizes the
  allocation. If the node survives until lowering, it represents a final materialization.

  ### 6. Record final compile-time reasons at lowering

  The current final outcome is detected in graal/compiler/src/jdk.graal.compiler/src/jdk/
  graal/compiler/replacements/DefaultJavaLoweringProvider.java:1020.

  At this point, for every tracked object in the surviving CommitAllocationNode:

  - Read its materialization metadata.
  - Call the reporter with allocation source plus materialization cause.
  - Increment the appropriate compile-time reason count.
  - Use other_unknown if metadata is unexpectedly absent.

  This avoids counting temporary materializations generated during iterative PEA and
  subsequently eliminated.

  ### 7. Produce two compile-time views

  I recommend retaining the existing site-based view and adding an occurrence-based reason
  report.

  pea-effectiveness.csv remains the unique allocation-site result, with two new fields:

  materialization_reasons
  reason_classification

  Examples:

  call_argument
  merge_incompatible|call_argument
  single_reason
  multiple_reasons

  A source site may have multiple reasons in different branches or compilation/inlining
  contexts. Therefore, unique sites cannot always be placed into exactly one reason bucket.
  Such sites must be classified as multiple_reasons.

  Add pea-materialization-reasons.csv for final compiled materialization occurrences:

  allocation_class
  allocation_method
  allocation_descriptor
  allocation_bci
  compilation
  inline_context
  reason
  root_reason
  propagation
  trigger_node
  trigger_class
  trigger_method
  trigger_descriptor
  trigger_bci
  detail

  Its compile-time counts will satisfy:

  final materialization occurrences
      = sum of compile-time occurrence counts by reason

  These remain compiler/IR occurrences, not runtime object executions.

  ### 8. Add runtime counters by reason

  During surviving CommitAllocationNode lowering, group tracked materialized objects by
  category and insert counters such as:

  PEA materialization reasons;call_argument
  PEA materialization reasons;method_return
  PEA materialization reasons;merge_incompatible
  PEA materialization reasons;object_graph_dependency
  PEA materialization reasons;other_unknown

  If a commit contains three objects:

  1 call_argument
  2 object_graph_dependency

  every execution of that commit increments the counters by 1 and 2 respectively.

  The required invariant per fork is:

  M = call_argument
    + method_return
    + exception_unwind
    + static_field_store
    + instance_field_store
    + array_store
    + unsupported_use
    + merge_incompatible
    + phi_incompatible
    + loop_exit_state
    + loop_analysis_limit
    + lock_constraint
    + virtualizer_requested
    + object_graph_dependency
    + lock_order_dependency
    + other_unknown

  ### 9. Extend the test framework

  Update pea-testing/pea-test.sh:121 to:

  - Preserve each fork’s pea-materialization-reasons.csv.
  - Extract all bounded runtime reason counters.
  - Verify that their sum equals final materialized.
  - Generate aggregate-materialization-reasons-static.csv.
  - Generate aggregate-materialization-reasons-runtime.csv.
  - Report mean, sample standard deviation, minimum and maximum per reason.
  - Add reason stability to the site-level report.
  - Fail a campaign if the reason-accounting invariant is violated.

  ### 10. Add controlled reason tests

  Create a new self-test with separately identifiable methods for:

  - Return
  - Non-inlined call argument
  - Static-field store
  - Instance-field store
  - Array store
  - Exception escape
  - Unsupported/identity-sensitive use
  - Phi/merge incompatibility
  - Transitive object graph
  - Locking

  Some categories, especially loop overflow and strict lock-order materialization, are
  compiler-policy paths and may be more reliable as Graal unit tests than ordinary Java self-
  tests.

  Validation sequence:

  1. Targeted Graal PEA unit tests.
  2. mx build --build-logs=silent.
  3. Controlled reason self-test.
  4. Check static and runtime sum invariants.
  5. Small H2 smoke campaign.
  6. Full H2 40 warmups × 10 forks.

  ## Scope boundary

  This first implementation should classify only V → M: objects that PEA initially
  virtualized and which finally materialized.

  C − V, the never-virtualized allocations, do not pass through ensureMaterialized().
  Determining why those allocations were never virtualized requires separate instrumentation
  inside individual VirtualizableAllocation.virtualize() implementations. That should be a
  later phase so the two questions are not mixed.

  The recommended first implementation milestone is therefore:

  Capture typed causes at all virtual→materialized transitions
  → preserve them on materialization occurrences
  → count only surviving final materializations
  → emit static reason reports
  → emit runtime reason counters
  → enforce sum(reason counters) == M
