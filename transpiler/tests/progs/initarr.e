/* Array and string initializers (M6): globals lay elements down statically
   (.data, .rodata when const) with a zero-filled tail; a char array copies a
   string literal's bytes including the NUL; a *char array element holds a
   string literal's address. Locals store listed elements at declaration
   (any expression) and leave unlisted elements uninitialized. */
enum{BASE=40};
var [5]int:gtab = {10,20,30};
var const [3]*char:names = {"zero","one","two"};
var [8]char:gstr = "hey";
var [2]double:gd = {1.5,-2.5};
var [2]long long:gll = {123456789012345,-7};
var [3]unsigned:gu = {2000000000,1,2};
var gnf:[2]int = {BASE,BASE+2};
func strlen0(s:*char)
{
  var int:n;
  n=0;
  while(s[n])n=n+1;
  return n;
}
func main()
{
  var [4]int:loc = {BASE,41,6*7};
  var [6]char:ls = "ab";
  var int:r;
  r=0;
  if((gtab[0]==10)&&(gtab[2]==30)&&(gtab[3]==0)&&(gtab[4]==0))r=r+1;
  if((names[1][0]=='o')&&(strlen0(names[2])==3))r=r+1;
  if((gstr[0]=='h')&&(gstr[3]==0)&&(gstr[7]==0))r=r+1;
  gstr[0]='y';
  if(gstr[0]=='y')r=r+1;
  if((gd[0]==1.5)&&(gd[1]==-2.5))r=r+1;
  if((gll[0]==123456789012345)&&(gll[1]==-7))r=r+1;
  if((gu[0]==2000000000)&&(gu[2]==2))r=r+1;
  if((gnf[0]==40)&&(gnf[1]==42))r=r+1;
  if((loc[0]==40)&&(loc[1]==41)&&(loc[2]==42))r=r+1;
  if((ls[0]=='a')&&(ls[1]=='b')&&(ls[2]==0))r=r+1;
  if(r==10)return 42;
  return r;
}
