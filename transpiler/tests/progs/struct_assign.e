/* whole-struct assignment (M6 2a): local & global struct copy, field
   independence, nested structs, sub-struct field copy, char/mixed fields.
   Returns 42. */
struct Pt { int x; int y; int z; };
struct Box { Pt lo; Pt hi; int tag; };
struct Mix { char c; int n; char d; };
var Mix:g1; var Mix:g2;
func main()
{
  var Pt:a; var Pt:b;
  var Box:x; var Box:y;
  a.x=1; a.y=2; a.z=3;
  b.x=9; b.y=9; b.z=9;
  b = a;
  a.x=100;
  if(b.x!=1)return 50;
  if(b.y!=2)return 51;
  if(b.z!=3)return 52;
  if(a.x!=100)return 53;
  x.lo.x=10; x.lo.y=11; x.lo.z=12;
  x.hi.x=20; x.hi.y=21; x.hi.z=22;
  x.tag=7;
  y = x;
  if(y.lo.x!=10)return 54;
  if(y.hi.z!=22)return 55;
  if(y.tag!=7)return 56;
  y.lo = x.hi;
  if(y.lo.x!=20)return 57;
  if(y.lo.z!=22)return 58;
  if(y.hi.x!=20)return 59;
  g1.c='A'; g1.n=1000; g1.d='B';
  g2 = g1;
  if(g2.c!=65)return 60;
  if(g2.n!=1000)return 61;
  if(g2.d!=66)return 62;
  return 42;
}
