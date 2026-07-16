/* Mixed params use independent integer/FP register sequences on x86_64/arm64.
   sum7 pins FP registers beyond the sixth positional parameter. */
func mix(i:int,x:double,j:int)
{
  var int:r;
  r=i+x+j;
  return r;
}
func sum7(a:double,b:double,c:double,d:double,e:double,f:double,g:double):double
{
  return a+b+c+d+e+f+g;
}
func main()
{
  if(mix(10,22.0,10)!=42)return 1;
  if(sum7(1.0,2.0,3.0,4.0,5.0,6.0,7.0)==28.0)return 42;
  return 2;
}
