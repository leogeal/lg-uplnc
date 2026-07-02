/* 9 arguments: on riscv64/mips64 (nargreg=8) the 9th is the first stack param,
   on x86_64/arm64 (nargreg=6) args 7-9 are stack params.  The callee's
   stack-parameter offset must use target.nargreg, not a hardcoded 6, or the
   9th argument reads the wrong slot (pre-fix: riscv64 188, mips64 0). */
func f(a:int,b:int,c:int,d:int,e:int,g:int,h:int,i:int,j:int)
{
  return j;
}
func main()
{
  return f(1,2,3,4,5,6,7,8,42);
}
