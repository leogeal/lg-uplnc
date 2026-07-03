/* 64-bit signed integer (long long). On the four 64-bit backends it reuses the
   word codegen; x*x here genuinely needs 64 bits (10^12), so big/x==x fails if
   the value were truncated to 32 bits. Rejected cleanly on i386. -> 42 */
func main()
{
  var long long:x;var long long:big;var int:r;
  x=1000000;          /* 10^6, fits 32 bits */
  big=x*x;            /* 10^12, needs 64 bits */
  r=0;
  if(big/x==x)r=r+20; /* 64-bit multiply/storage held */
  if(big>1000000)r=r+10;  /* 64-bit compare */
  if(x/7==142857)r=r+7;   /* signed divide */
  if(x%7==1)r=r+5;        /* signed remainder */
  return r;               /* 42 */
}
