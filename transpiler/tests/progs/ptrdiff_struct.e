/* Pointer subtraction over a non-power-of-two element size.
   The struct lays out to 12 bytes under UPLNC's current struct layout, so the
   x86 backends must use real register division rather than invalid div $imm. */
struct S { char a; char b; char c; };
func main()
{
  var [4]S:arr;
  var *S:p;
  var *S:q;
  p=&arr[3];
  q=&arr[0];
  return p-q;
}
