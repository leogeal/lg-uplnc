/* slice 4b: a double return feeds straight into another double parameter
   (xmm0 -> call -> xmm0), then truncates.  dtoi(half(84.0)) -> dtoi(42.0) -> 42. */
func half(x:double):double
{
  return x/2.0;
}
func dtoi(x:double)
{
  var int:i;
  i=x;
  return i;
}
func main(){return dtoi(half(84.0));}
