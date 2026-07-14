/* Non-leaf promotion keeps a and b in callee-saved registers across calls.
   c is address-taken, so it must remain in the frame. Recursion verifies that
   each invocation preserves its promoted local independently. Returns 42. */
func ident(x:int)
{
  return x;
}

func pair(x:int)
{
  var int:a;var int:b;var int:c;
  var *int:p;
  a=x;
  b=1;
  c=0;
  p=&c;
  *p=*p;
  a=ident(a);
  b=ident(b);
  return a+b+c;
}

func rec(n:int)
{
  var int:keep;
  if(n<=0)return 0;
  keep=n;
  return rec(keep-1)+keep+(keep-keep);
}

func main()
{
  return pair(20)+rec(6);
}
