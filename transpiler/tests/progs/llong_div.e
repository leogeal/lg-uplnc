func main()
{
  var long long:a;var long long:b;var int:r;
  r=0;
  a=1000000;a=a*a;         /* 10^12 */
  b=1000000;
  if(a/b==1000000)r=r+10;  /* 10^12 / 10^6 == 10^6 */
  if(a%b==0)r=r+8;         /* exact */
  a=a+7;                   /* 10^12 + 7 */
  if(a%b==7)r=r+8;         /* remainder 7 */
  a=0-1000000;a=a*1000000; /* -10^12 */
  if(a/b==0-1000000)r=r+8; /* signed divide */
  if(a<0)r=r+8;            /* still negative */
  return r;                /* 42 */
}
