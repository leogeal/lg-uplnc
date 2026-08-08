/* `[]` dimension inference (M6): the initializer fixes the dimension, for
   globals (laid down statically) and locals (the frame slot is sized only
   after the elements are counted) alike, in both declaration forms.
   Every array here is written through to its last element with a neighbour
   object standing guard: a wrong inferred dimension corrupts the guard. */
enum{BASE=40};
var []int:gt = {10,20,30};
var int:guard1 = 111;
var const []*char:names = {"zero","one","two"};
var []char:gs = "hey";
var int:guard2 = 222;
var []double:gd = {1.5,-2.5};
var []long long:gll = {123456789012345,-7};
var gnf:[]int = {BASE,BASE+2};
var [1]int:shadow = {100};   /* a local of this name must win inside its own
                                initializer; see the block scope in main */
func strlen0(s:*char)
{
  var int:n;
  n=0;
  while(s[n])n=n+1;
  return n;
}
func main()
{
  var []int:lt = {BASE,41,6*7};
  var int:lguard;
  var []char:ls = "ab";
  var int:r,i;
  lguard=333;
  r=0;
  for(i=0;i<3;i++)gt[i]=gt[i]+1;
  if((gt[0]==11)&&(gt[2]==31)&&(guard1==111))r=r+1;
  if((names[1][0]=='o')&&(strlen0(names[2])==3))r=r+1;
  for(i=0;i<4;i++)gs[i]=gs[i];
  if((gs[0]=='h')&&(gs[3]==0)&&(guard2==222))r=r+1;
  if((gd[0]==1.5)&&(gd[1]==-2.5))r=r+1;
  if((gll[0]==123456789012345)&&(gll[1]==-7))r=r+1;
  if((gnf[0]==40)&&(gnf[1]==42))r=r+1;
  for(i=0;i<3;i++)lt[i]=lt[i]+1;
  if((lt[0]==41)&&(lt[1]==42)&&(lt[2]==43)&&(lguard==333))r=r+1;
  if((ls[0]=='a')&&(ls[1]=='b')&&(ls[2]==0))r=r+1;
  /* a block scope: the deferred allocation must not disturb its neighbours,
     and a trailing comma is allowed */
  if(1)
  {
    var []int:inner = {5,6,};
    var int:iguard;
    iguard=9;
    inner[1]=inner[0]+inner[1];
    if((inner[1]==11)&&(iguard==9))r=r+1;
  }
  /* An inferred local is in scope inside its own initializer, so the
     self-reference below reads the element just stored (7+1), not the global
     of the same name (which would give 101). */
  if(1)
  {
    var []int:shadow = {7,shadow[0]+1};
    if((shadow[0]==7)&&(shadow[1]==8))r=r+1;
  }
  if(r==10)return 42;
  return r;
}
