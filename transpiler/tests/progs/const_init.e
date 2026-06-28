/* M6: local variable initializers + const enforcement. Returns 42. */
func main()
{
  var int:a = 5;
  var int:b = a + 10;        /* init from another variable -> 15 */
  var const int:c = b * 2;   /* const, initialized from an expression -> 30 */
  var int:r;
  r = a + b + c;             /* 50 */
  if(c != 30)return 60;
  return r - 8;              /* 42 */
}
