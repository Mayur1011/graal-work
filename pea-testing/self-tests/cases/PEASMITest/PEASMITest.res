# Format: class;method;descriptor;callBci[;allocationBci]
# Fact: inlining the consume() call at bci 18 inside run(int) lets PEA scalar-replace
# the Holder allocated at bci 10 and passed into it.
smi.test.Test;run;(I)J;18;10
