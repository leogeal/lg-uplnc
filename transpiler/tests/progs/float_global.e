/* slice 5: a global float (.comm name,4,4) stores/loads through the widen/narrow
   path.  21.0*2.0 -> 42. */
var float:g;
func main()
{
  var int:i;
  g=21.0;
  g=g*2.0;
  i=g;
  return i;
}
