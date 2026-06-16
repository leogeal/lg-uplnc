/* regression: same shape but the inner-right is a shift (needs %cl on x86). */
func main()
{
  var int:w;var int:x;var int:y;var int:z;
  w=30;x=2;y=80;z=3;
  return w+(x+(y>>z));
}
