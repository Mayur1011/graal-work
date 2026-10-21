# Format: class;method;descriptor;callBci[;allocationBci]
# run() calls make(i) at bci 10; make() allocates and returns the Holder (alloc bci 1310 inside make).
smi.ret.Test;run;(I)J;10;1310
