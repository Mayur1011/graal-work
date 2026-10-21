# Format: class;method;descriptor;callBci[;allocationBci]
# Only the call that survives to the inliner is listed: wrap() is tiny, so Graal inlines run -> wrap while
# parsing the bytecode and the inliner never sees a run@18 call. consume inside wrap (bci 1) is what must be inlined.
smi.nested.Test;wrap;(Lsmi/nested/Test$Holder;)I;1;10
