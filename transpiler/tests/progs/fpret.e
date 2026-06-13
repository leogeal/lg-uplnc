/* slice 4b: a `: double` function returns its result in %xmm0; the caller routes
   it through the FP path into a double local.  41.0+1.0 -> 42. */
func add1(x:double):double
{
  return x+1.0;
}
func main()
{
  var double:a;
  a=add1(41.0);
  return a;
}
