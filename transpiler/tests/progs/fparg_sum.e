/* slice 4a: pass a computed double (x+y) as a variadic FP argument. */
func main()
{
  var [64]char:buf;
  var double:x;
  var double:y;
  x=19.5;
  y=22.5;
  sprintf(buf,"%.0f",x+y);
  return atoi(buf);
}
