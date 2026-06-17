/* leaf function: b,c are non-address-taken int locals -> promoted to registers;
   a is address-taken (&a) -> excluded (must stay in the frame). returns 42. */
func main()
{
  var int:a;var int:b;var int:c;
  var *int:p;
  a=40;
  b=2;
  c=a+b;
  p=&a;
  *p=*p;
  return c;
}
