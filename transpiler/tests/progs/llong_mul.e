func main()
{
  var long long:a;var long long:b;var long long:c;var long long:d;var int:r;
  r=0;
  a=2000000000;        /* 2e9 < 2^31 */
  c=a*3;               /* 6e9, needs 64-bit multiply */
  d=a+a+a;             /* 6e9 via addition (trusted from 2a) */
  if(c==d)r=r+14;      /* multiply == repeated add */
  a=1000000;
  c=a*a;               /* 10^12 */
  b=a+a;               /* 2e6 */
  d=c-b;               /* 10^12 - 2e6 */
  if(d+b==c)r=r+14;    /* 64-bit roundtrip holds */
  a=0-1000000000;      /* -1e9 */
  c=a*3;               /* -3e9, signed 64-bit */
  d=a+a+a;             /* -3e9 via add */
  if(c==d)r=r+14;      /* signed multiply == add */
  return r;            /* 42 */
}
