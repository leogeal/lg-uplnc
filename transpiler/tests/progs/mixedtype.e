/* mixed char / int / unsigned arithmetic. Returns 42. */
func main()
{
  var char:c; var int:i; var unsigned:u; var int:s;
  c = 5; i = 100; u = 7;
  s = 0;
  s = s + (c + i);           /* char+int = 105 */
  s = s - (i - c);           /* -(95) -> 10 */
  s = s + (c * c);           /* 25 -> 35 */
  s = s + (u + i);           /* unsigned+int = 107 -> 142 */
  s = s - u * (i / u);       /* 7*(100/7 unsigned=14)=98 -> 44 */
  return s - 2;              /* 42 */
}
