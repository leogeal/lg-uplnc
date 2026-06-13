/* slice 4a: pass a double to a variadic libc call (sprintf), %al=1, xmm0.
   Round-trip the formatted value back through atoi -> exit code 42. */
func main()
{
  var [64]char:buf;
  var double:x;
  x=42.0;
  sprintf(buf,"%.0f",x);
  return atoi(buf);
}
