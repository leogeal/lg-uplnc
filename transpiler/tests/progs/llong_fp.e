/* long long <-> double conversions and mixed ll/double arithmetic. On i386 these
   use fildll/fistpll; on the 64-bit backends long long is the word int. -> 42 */
func main()
{
  var long long:x;var long long:z;var double:d;var int:r;
  r=0;
  x=1000000;x=x*x;            /* 10^12 */
  d=x;                        /* ll -> double */
  z=d;                        /* double -> ll */
  if(z==x)r=r+11;             /* roundtrip preserved */
  if(d>5000000000)r=r+11;     /* ll->double kept the magnitude */
  d=1;
  if(x+d>5000000000)r=r+10;   /* ll + double, ll on the left */
  x=0-1000000;x=x*1000000;    /* -10^12 */
  d=x;
  if(d<0)r=r+10;              /* negative ll -> double */
  return r;                   /* 42 */
}
