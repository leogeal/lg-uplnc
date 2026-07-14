/* Cold locals are declared first, but only hot has enough frame accesses to
   repay its entry save and return restore. Profitability ranking must choose
   hot alone rather than assigning registers in declaration order. Returns 42. */
func ident(x:int)
{
  return x;
}

func profit(x:int)
{
  var int:cold1;var int:cold2;var int:hot;
  cold1=0;
  cold2=0;
  hot=x;
  ident(0);
  hot=ident(hot);
  hot=hot+1;
  return hot+cold1+cold2;
}

func main()
{
  return profit(41);
}
