/* pointer/char return types are type-correct at the call site (M6): *f(),
   f()[i], f()+n, and f()->field all work on a call result; char return too.
   Returns 42. */
struct Pt { int x; int y; };
var [3]int:arr;
var Pt:gp;
func first():*int  { return &arr[0]; }
func getpt():*Pt   { gp.x=40; gp.y=2; return &gp; }
func nextp(p:*int):*int { return p+1; }
func getch():char  { return 'Z'; }          /* 90 */
func main()
{
  var int:r;
  arr[0]=10; arr[1]=20; arr[2]=30;
  r=0;
  if(*first()!=10)r=r+1;
  if(first()[2]!=30)r=r+1;
  if(*(first()+1)!=20)r=r+1;
  if(getpt()->x!=40)r=r+1;
  if(getpt()->y!=2)r=r+1;
  if(*nextp(first())!=20)r=r+1;
  if(getch()!=90)r=r+1;
  if(r==0)return 42;
  return 50+r;
}
