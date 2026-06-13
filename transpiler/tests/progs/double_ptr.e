/* FP-array fix: load and store a double through a pointer (*p). */
func main()
{
  var double:x;
  var *double:p;
  x=21.0;
  p= &x;
  *p=*p*2.0;
  return x;
}
