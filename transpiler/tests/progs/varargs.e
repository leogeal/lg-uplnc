/* variadic functions: `func f(a:int,...)` + vastart(), a *int to the first
   variadic arg (word-size values, p[0], p[1], ...). The caller needs no special
   convention (position-based marshal); the callee spills the remaining arg
   registers below the named params so the tail is contiguous and walks upward
   (i386: the cdecl stack already is the va area). -> 42 */
func sum(n:int,...)
{
  var p:*int;
  var s:int = 0;
  var i:int = 0;
  p=vastart();
  while(i<n){s=s+p[i];i++;}
  return s;
}
func maxi(a:int,b:int)
{
  if(a>b)return a;
  return b;
}
func vmax(n:int,...)      /* non-leaf variadic: calls another function */
{
  var p:*int;
  var m:int;
  var i:int = 1;
  p=vastart();
  m=p[0];
  while(i<n){m=maxi(m,p[i]);i++;}
  return m;
}
func first(...)           /* zero named parameters */
{
  var p:*int;
  p=vastart();
  return p[0];
}
func main()
{
  var s:*char = "*";
  var r:int = 0;
  if(sum(4,10,11,10,8)==39)r=r+11;
  if(vmax(3,7,40,9)==40)r=r+11;
  if(first(29)==29)r=r+10;
  if(sum(1,s)!=0)r=r+10;   /* a pointer as a vararg */
  return r;                /* 42 */
}
