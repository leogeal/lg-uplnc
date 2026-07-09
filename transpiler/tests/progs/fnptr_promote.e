/* Indirect calls are call boundaries for local-register promotion. x must not
   live in a caller-saved promoted register across f(), because the callback may
   clobber it. Pre-fix: x86_64/arm64/riscv64 returned 100. -> 42 */
func clobber()
{
  var int:a;
  a=99;
  return 0;
}
func callit(f:int)
{
  var int:x;
  x=41;
  f();
  return x+1;
}
func main()
{
  return callit(clobber);
}
