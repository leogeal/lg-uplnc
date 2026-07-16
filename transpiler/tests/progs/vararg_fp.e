/* raw FP-varargs mechanism: doubles travel as bits in integer va slots;
   read back via a *double onto the slot. i386: a double spans two slots. */
func sumva(n:int,...)
{
  var p:*int;
  var dp:*double;
  var s:double;
  var i:int;
  p=vastart();
  s=0.0;
  i=0;
  while(i<n)
  {
    dp=p+i*(8/sizeof(int));
    s=s+*dp;
    i=i+1;
  }
  if((s>3.9)&&(s<4.1))return 42;
  return 1;
}
func mixed(a:int,...)
{
  var p:*int;
  var dp:*double;
  var k:int;
  p=vastart();
  k=p[0];                    /* int: one word slot on every target */
  dp=p+1;                    /* the double follows in the next slot(s) */
  if(k!=7)return 2;
  if((*dp<2.4)||(*dp>2.6))return 3;
  return p[1+8/sizeof(int)]; /* the double used 8/sizeof(int) slots */
}
func main()
{
  var r:int;
  r=sumva(2,1.5,2.5);
  if(r!=42)return r;
  r=mixed(1,7,2.5,40);
  if(r!=40)return 50;
  return 42;
}
