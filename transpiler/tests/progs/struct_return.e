struct Pt { int x; int y; int z; };
struct Box { Pt lo; Pt hi; };
var Pt:gp;
func make(a:int,b:int,c:int):Pt
{
  var Pt:p;
  p.x=a; p.y=b; p.z=c;
  return p;
}
func mkbox(v:int):Box
{
  var Box:b;
  b.lo.x=v; b.lo.y=v+1; b.lo.z=v+2;
  b.hi.x=v+10; b.hi.y=v+11; b.hi.z=v+12;
  return b;
}
func main()
{
  var Pt:r; var Box:bx;
  var int:e;
  e=0;
  r = make(10, 20, 30);
  if(r.x!=10)e=e+1;
  if(r.y!=20)e=e+1;
  if(r.z!=30)e=e+1;
  gp = make(1, 2, 3);
  if(gp.x!=1)e=e+1;
  if(gp.z!=3)e=e+1;
  bx = mkbox(100);
  if(bx.lo.x!=100)e=e+1;
  if(bx.lo.z!=102)e=e+1;
  if(bx.hi.x!=110)e=e+1;
  if(bx.hi.z!=112)e=e+1;
  r = make(5, 6, 7);
  if(r.x!=5)e=e+1;
  if(r.z!=7)e=e+1;
  if(e==0)return 42;
  return 60+e;
}
