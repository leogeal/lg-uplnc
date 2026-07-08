/* function pointers: a bare function name (or &f) is its address; any
   expression can be called -- variables, parameters (callbacks), dispatch-table
   elements. The callee address is pushed below the args and CD_ICALL calls
   through a per-backend scratch register ($t9 on mips, its PIC convention). -> 42 */
func add1(x:int){return x+1;}
func dbl(x:int){return x+x;}
func sub2(a:int,b:int){return a-b;}
func apply(f:int,x:int){return f(x);}      /* callback through a parameter */
func main()
{
  var p:int = 0;
  var [2]int:tab;
  var r:int = 0;
  p=add1;                     /* bare name decays to the address */
  if(p(4)==5)r=r+9;           /* call through a variable */
  p=&dbl;                     /* &f form */
  if(p(10)==20)r=r+9;
  if(apply(add1,41)==42)r=r+8;   /* function passed as an argument */
  tab[0]=add1;tab[1]=dbl;
  if(tab[0](1)==2)r=r+8;      /* dispatch-table element call */
  if(tab[1](3)==6)r=r+4;
  p=sub2;
  if(p(50,8)==42)r=r+4;       /* two args through a pointer */
  return r;                   /* 42 */
}
