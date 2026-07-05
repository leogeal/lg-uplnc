/* name-first initializers: var name:TYPE = expr; for locals and globals
   (the type-first form landed earlier). Init attaches to the last declarator,
   const is enforced, wide/double values work. -> 42 */
var g:int = 30;
var const gc:int = 2;
var gw:long long = 10000000000;
var gd:double = 2.5;
func main()
{
  var r:int = 0;
  var x:int = 5;
  var p:*char = 0;
  var d:double = 1.5;
  var a,b:int = 7;              /* init attaches to the last declarator (b) */
  if(x==5)r=r+8;
  if(!p)r=r+6;
  if(d+d==3.0)r=r+6;
  if(b==7)r=r+6;
  a=1;                          /* a is uninitialized but usable */
  if(a==1)r=r+2;
  if(g==30)r=r+4;
  if(gc==2)r=r+4;
  if(gw/100000==100000)r=r+3;
  if(gd*2.0==5.0)r=r+3;
  return r;                     /* 42 */
}
