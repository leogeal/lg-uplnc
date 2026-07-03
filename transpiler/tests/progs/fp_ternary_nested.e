/* nested ?: expressions must propagate a floating result through cttype().
   This covers both assignment to a double and FP argument classification. -> 42 */
func check(x:double)
{
  if(x==40.0)return 21;
  return 0;
}
func main()
{
  var int:c;var int:c2;var double:r;var int:acc;
  c=0;c2=0;acc=0;
  r=(c?(c2?1:2.5):40);         /* outer else arm is int, inner then arm is int */
  if(r==40.0)acc=acc+21;       /* must store promoted 40.0, not stale FP state */
  acc=acc+check(c?(c2?1:2.5):40); /* must pass the argument in the FP class */
  return acc;
}
