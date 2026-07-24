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
/* Switch dispatch jumps backward to case bodies, but it is not a loop.
   A parameter used only in those bodies must not pay an entry promotion load. */
func switchp(x:int)
{
  switch(x)
  {
    case 1:return x+1;
    case 2:return x+2;
    default:return x+3;
  }
}
func forp(n:int)
{
  for(n=n;n>0;n=n-1)
  {
  }
  return n;
}
func dop(n:int)
{
  do
  {
    n=n-1;
  }while(n>0);
  return n;
}
func main()
{
  var int:r;
  r=0;
  if(sgcd(1071,462)==21)r=r+1;
  if(mix6(1,2,3,4,5,6)==165)r=r+1;
  if(addrp(5)==40)r=r+1;
  if(switchp(1)==2)r=r+1;
  if(forp(2)==0)r=r+1;
  if(dop(2)==0)r=r+1;
  if(r==6)return 42;
  return 1;
}
