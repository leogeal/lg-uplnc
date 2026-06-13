/* slice 4a: mixed int + double args in one call -- int to %rsi (integer
   sequence), double to %xmm0 (vector sequence), %al=1.  "4" then "2" -> 42. */
func main()
{
  var [64]char:buf;
  var double:x;
  var int:i;
  x=2.0;
  i=4;
  sprintf(buf,"%d%.0f",i,x);
  return atoi(buf);
}
