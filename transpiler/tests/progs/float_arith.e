/* slice 5: float operands widen to double, compute in double, result truncated.
   20.5 + 21.5 -> 42. */
func main()
{
  var float:x;
  var float:y;
  var int:i;
  x=20.5;
  y=21.5;
  i=x+y;
  return i;
}
