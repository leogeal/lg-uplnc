/* unsigned long long -> double, including values >= 2^63 (top bit set). On i386
   a signed fildll would read those as negative, so ull2f/ull2f1 add 2^64 back
   when the top bit is set; the 64-bit backends convert via u2f. -> 42 */
func main()
{
  var unsigned long long:u;var double:d;var long long:back;var long long:expect;var int:r;
  r=0;
  u=1;u=u<<63;                 /* 2^63, top bit set */
  d=u;                         /* ull -> double (accumulator path) */
  if(d>0)r=r+8;                /* positive, not -9.2e18 */
  d=d/2;                       /* 2^62 as double */
  back=d;expect=1;expect=expect<<62;
  if(back==expect)r=r+8;       /* magnitude correct (2^62) */
  u=0;u=u-1;d=u;               /* 2^64-1, all ones */
  if(d>0)r=r+8;                /* whole-range value stays positive */
  u=1;u=u<<63;d=1;
  if(u>d)r=r+9;                /* ull on the left of an FP compare (ull2f1) */
  if(u+d>0)r=r+9;              /* ull on the left of FP arithmetic (ull2f1) */
  return r;                    /* 42 */
}
