/* FP-array fix: load and store a float through a pointer (narrowed on store). */
func main()
{
  var float:x;
  var *float:p;
  x=21.0;
  p= &x;
  *p=*p+21.0;
  return x;
}
