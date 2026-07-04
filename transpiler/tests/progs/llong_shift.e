func main()
{
  var long long:a;var unsigned long long:u;var long long:s;var int:r;
  r=0;
  a=1;
  if(a<<40>>40==1)r=r+8;      /* left 40, right 40 (count>=32) -> 1 */
  a=1;
  if(a<<32>>32==1)r=r+8;      /* count==32 boundary */
  a=255;
  if(a<<48>>48==255)r=r+7;    /* byte roundtrip through the high word */
  u=0;u=u-1;                  /* 2^64-1 */
  if(u>>63==1)r=r+7;          /* logical right: top bit -> 1 */
  s=0;s=s-1;                  /* -1 */
  if(s>>63==0-1)r=r+6;        /* arithmetic right: sign fills -> -1 */
  s=0-16;
  if(s>>2==0-4)r=r+6;         /* arithmetic small: -16>>2 == -4 */
  return r;                   /* 42 */
}
