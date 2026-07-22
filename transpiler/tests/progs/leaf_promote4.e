/* Eight parameters exercise entry spills for every argument register. The
   four non-address-taken locals must then occupy all leaf-promotion slots. */
func leaf4(a:int,b:int,c:int,d:int,e:int,f:int,g:int,h:int)
{
  var int:w;var int:x;var int:y;var int:z;
  w=a+e;
  x=b+f;
  y=c+g;
  z=d+h;
  return w+x+y+z;
}
func main()
{
  return leaf4(1,2,3,4,5,6,7,14);
}
