/* unsigned long long: a high-bit value is a huge positive, not signed -1.
   Distinguishes the unsigned 64-bit type from the signed one. -> 42 */
func main()
{
  var unsigned long long:u;var long long:s;var int:r;
  u=0;u=u-1;          /* 0xFFFF...F : huge unsigned */
  s=0;s=s-1;          /* signed -1 */
  r=0;
  if(u>1000)r=r+21;   /* unsigned compare: huge > 1000 */
  if(s<0)r=r+21;      /* signed compare: -1 < 0 */
  return r;           /* 42 */
}
