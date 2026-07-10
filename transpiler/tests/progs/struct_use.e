/* struct-return follow-ups: an UNCAPTURED struct-returning call materializes
   into a hidden statement-level temp (prestemps/mkstemp), so f().m, nested
   f().sub.m, return f() chaining, struct args (decay to pointer-to-temp, like
   arrays) and discarded calls all work; s = f() keeps the direct sret path. -> 42 */
struct pair{int a;int b;};
struct wrap{pair p;int tag;};
func mk(x:int,y:int):pair
{
  var q:pair;
  q.a=x;q.b=y;
  return q;
}
func mkw(t:int):wrap
{
  var w:wrap;
  w.p=mk(t,t+1);          /* capture path: s = f() (sub-field via struct assign) */
  w.tag=t;
  return w;               /* return of a named struct (existing) */
}
func chain():pair
{
  return mk(30,12);       /* NEW: return f() -- chained struct return */
}
func psum(pp:*pair)
{
  return pp->a+pp->b;
}
func main()
{
  var s:pair;
  var r:int = 0;
  if(mk(20,22).a==20)r=r+9;        /* NEW: f().m */
  if(mk(1,41).b==41)r=r+9;
  s=chain();
  if(s.a+s.b==42)r=r+8;            /* chained return roundtrip */
  if(mkw(5).p.b==6)r=r+8;          /* nested: f().sub.m */
  if(psum(mk(21,21))==42)r=r+8;    /* NEW: struct arg decays to pointer-to-temp */
  mk(1,2);                         /* NEW: discarded call compiles + runs */
  return r;                        /* 42 */
}
