/* slice 5: global doubles (.comm name,8,4) store/load and arithmetic.  20.0+22.0 -> 42. */
var double:g;
func main()
{
  var int:i;
  g=20.0;
  g=g+22.0;
  i=g;
  return i;
}
