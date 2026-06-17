/* switch/case: dispatch, stacked cases, fall-through, default, break, switch in
   a loop, continue (targets the enclosing loop), enum case labels, and a nested
   switch (inner break exits only the inner switch). Returns 42. */
enum { RED, GREEN, BLUE };
func classify(c:int)
{
  switch(c)
  {
    case 1:
    case 2:  return 10;       /* stacked */
    case 3:  return 20;
    default: return 30;
  }
  return 99;
}
func sumloop()
{
  var int:i;var int:s;
  s=0;
  for(i=0;i<5;i=i+1)
    switch(i)
    {
      case 0: s=s+1; break;
      case 1: s=s+2; break;
      case 2: s=s+4;          /* fall through */
      case 3: s=s+8; break;
      default: s=s+100;
    }
  return s;                   /* 1+2+(4+8)+8+100 = 123 */
}
func contsw()
{
  var int:i;var int:s;
  s=0;
  for(i=0;i<6;i=i+1)
  {
    switch(i){ case 2: continue; case 4: continue; }
    s=s+i;
  }
  return s;                   /* 0+1+3+5 = 9 */
}
func enumsw(c:int)
{
  switch(c){ case RED: return 100; case GREEN: return 200; case BLUE: return 300; }
  return 0;
}
func nested(a:int,b:int)
{
  var int:r;
  r=0;
  switch(a)
  {
    case 1: switch(b){ case 1: r=11; break; case 2: r=12; break; } break;
    case 2: r=20; break;
  }
  return r;
}
func main()
{
  var int:e;
  e=0;
  if(classify(1)!=10)e=e+1;
  if(classify(2)!=10)e=e+1;
  if(classify(3)!=20)e=e+1;
  if(classify(9)!=30)e=e+1;
  if(sumloop()!=123)e=e+1;
  if(contsw()!=9)e=e+1;
  if(enumsw(0)!=100)e=e+1;
  if(enumsw(2)!=300)e=e+1;
  if(enumsw(7)!=0)e=e+1;
  if(nested(1,2)!=12)e=e+1;
  if(nested(2,9)!=20)e=e+1;
  if(e==0)return 42;
  return 60+e;
}
