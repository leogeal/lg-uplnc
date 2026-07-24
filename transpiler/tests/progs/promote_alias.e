/* A promoted scalar's frame offset may be reused by a later aggregate.
   Promotion must not rewrite the aggregate's field access as the old local. */
struct pair{
  int x;
  int y;
};

func pairsum(p:*pair)
{
  return p->x+p->y;
}

func main()
{
  if(1)
  {
    var int:a;
    a=0;
    a=a+1;a=a+1;a=a+1;a=a+1;a=a+1;
    a=a+1;a=a+1;a=a+1;a=a+1;a=a+1;
    if(a!=10)return 1;
  }
  if(1)
  {
    var p:pair;
    p.x=40;
    p.y=2;
    if(pairsum(&p)==42)return 42;
  }
  return 2;
}
