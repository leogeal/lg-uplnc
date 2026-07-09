/* regspill across an indirect call: the left operand of x + (p()-2) is spilled
   over the call's span, and the callee-address PUSH has no matching POP -- both
   must stay in memory (CD_ICALL is a call boundary like CD_ZCALL). Pre-fix this
   mispaired the pushes and the indirect call jumped through garbage (SIGSEGV on
   every register target). -> 42 */
func g()
{
  var a:int;
  a=1;
  return (a+a)+(a+a);   /* a register-held spill inside the callee */
}
func main()
{
  var p:int = 0;
  var x:int = 40;
  p=g;
  return x + (p()-2);
}
