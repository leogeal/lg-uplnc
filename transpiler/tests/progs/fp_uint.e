/* unsigned values with the high bit set must promote to their large positive
   double value, not signed -1. Covers assignment, compare, arithmetic and
   FP argument classification via a mixed expression. -> 42 */
func big(x:double)
{
  if(x>1000.0)return 6;
  return 0;
}
func main()
{
  var unsigned:u;var double:d;var int:r;
  u=0;u=u-1;r=0;
  d=u;if(d>1000.0)r=r+8;
  if(u>1.0)r=r+8;
  if(!(u==(-1.0)))r=r+8;
  d=u+3.0;if(d>1000.0)r=r+6;
  d=3.0+u;if(d>1000.0)r=r+6;
  r=r+big(u+0.0);
  return r;
}
