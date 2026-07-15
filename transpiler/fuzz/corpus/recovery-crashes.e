/* Minimised inputs that once faulted the instrumented compiler (found by this
   fuzzing pass). Each must now yield a clean diagnostic, never a memory fault or
   undefined-behaviour report. Kept in the corpus so every run re-exercises them
   verbatim, and so mutation keeps exploring the error-recovery paths near them.
   shift_exponent: foldtree folded an out-of-range shift count.
   lor/land/plus_missing: a binary operator with a missing right operand walked
   or read a null / uninitialised subtree in codegen.
   the nameless global: doginit wrote through an unset symbol pointer.
   wide: number() overflowed a host int while scanning a 64-bit literal. */
func shift_exponent(){return 1<<48;}
func lor_missing(){return 1||;}
func land_missing(){return 1&&;}
func plus_missing(){return 1+;}
var :int = 5;
func wide(){var long long:w;w=10000000000;return 0;}
func main(){return 0;}
