/* Byte-sized conversions: function returns and assignment expressions must
   produce the converted byte value in the accumulator, not only after storage. */
func retu():unsigned char
{
  return 300;             /* unsigned char return: 300 -> 44 */
}
func retu2(x:int):unsigned char
{
  return x;               /* parameter value narrows on return */
}
func rets():char
{
  return 200;             /* signed char return: 200 -> -56 */
}
func rets2(x:int):char
{
  return x;               /* 255 -> -1 */
}
func main()
{
  var r:int = 0;
  var u:unsigned char = 0;
  var c:char = 0;
  if(retu()==44)r=r+7;
  if(retu2(511)==255)r=r+7;
  if(rets()==(0-56))r=r+7;
  if(rets()!=200)r=r+5;
  if(rets2(255)==(0-1))r=r+7;
  if((u=300)==44)r=r+5;
  if((c=200)==(0-56))r=r+4;
  return r;               /* 42 */
}
