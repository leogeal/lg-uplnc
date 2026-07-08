/* function-pointer nesting: indirect results as direct args and vice versa,
   and f(g(x)) composition with both callees arriving as parameters. -> 42 */
func add1(x:int){return x+1;}
func dbl(x:int){return x+x;}
func compose(f:int,g:int,x:int){return f(g(x));}  /* indirect inside indirect */
func main()
{
  var p:int = 0;
  var r:int = 0;
  p=add1;
  if(dbl(p(3))==8)r=r+14;             /* indirect result into a direct call */
  if(p(dbl(3))==7)r=r+14;             /* direct result as an indirect arg */
  if(compose(dbl,add1,20)==42)r=r+14; /* f(g(x)) both through parameters */
  return r;                           /* 42 */
}
