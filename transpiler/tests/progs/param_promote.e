/* Loop-used parameters promote in leaf functions (M5 parameter promotion).
   sgcd: both params are reassigned every iteration -- the flagship case.
   mix6: no promotable locals, so params a..d take all four leaf registers;
   on mips64 those are $8..$11 while e/f ARRIVE in $8/$9 (N64 a4/a5) -- the
   entry loads must run after every argument spill or e/f would be corrupted.
   addrp: an address-taken parameter must stay in memory even with loop uses. */
func sgcd(a:int,b:int)
{
  while(a!=b)
  {
    if(a>b)a=a-b;
    else b=b-a;
  }
  return a;
}
func mix6(a:int,b:int,c:int,d:int,e:int,f:int)
{
  while(a<50)
  {
    a=a+b+c;
    d=d+e+f;
  }
  return a+d;
}
func addrp(n:int)
{
  var *int:p;
  var int:i,s;
  p=&n;
  s=0;
  i=0;
  while(i<4)
  {
    s=s+*p+n;
    i=i+1;
  }
  return s;
}
func main()
{
  var int:r;
  r=0;
  if(sgcd(1071,462)==21)r=r+1;
  if(mix6(1,2,3,4,5,6)==165)r=r+1;
  if(addrp(5)==40)r=r+1;
  if(r==3)return 42;
  return 1;
}
