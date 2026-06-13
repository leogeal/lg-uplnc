/* slice 5: a float local is narrowed on store (cvtsd2ss/movss) and widened on
   load (cvtss2sd), then truncated to int.  42.5 -> 42. */
func main()
{
  var float:x;
  var int:i;
  x=42.5;
  i=x;
  return i;
}
