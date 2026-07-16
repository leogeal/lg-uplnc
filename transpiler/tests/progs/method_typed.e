/* typed method returns + FP args, all forms */
struct circle{
  double r;
  func area:double;          /* trailing form */
  func double scaled;        /* type-first form (original grammar) */
  func sum6:double;          /* receiver + six FP-register parameters */
  func grow;                 /* untyped: int, unchanged */
  func name:*char;           /* pointer return */
};
method circle.area()
{
  return 3.14159*r*r;        /* no annotation: inherits the slot type */
}
method circle.scaled(f:double):double
{
  return r*f;                /* annotation repeated: must match */
}
method circle.sum6(a:double,b:double,c:double,d:double,e:double,f:double)
{
  return a+b+c+d+e+f;
}
method circle.grow(d:int)
{
  r=r+d;
  return 0;
}
method circle.name()
{
  return "circle";
}
func main()
{
  var c:circle;
  var a:double;
  var s:*char;
  c.r=2.0;
  a=c.area();                       /* double return */
  if((a<12.56)||(a>12.57))return 1;
  a=c.scaled(2.5);                  /* double ARG + double return */
  if(a!=5.0)return 2;
  a=c.sum6(1.0,2.0,3.0,4.0,5.0,6.0);
  if(a!=21.0)return 7;
  c.grow(1);
  if(c.r!=3.0)return 3;
  a=1.0+c.area();                   /* enclosing expr: cttype must say double */
  if((a<29.2)||(a>29.3))return 4;
  s=c.name();                       /* pointer return */
  if(s[0]!='c')return 5;
  if(s[5]!='e')return 6;
  return 42;
}
