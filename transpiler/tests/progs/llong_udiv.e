func main()
{
  var unsigned long long:u;var int:r;
  r=0;
  u=0;u=u-1;                    /* 2^64-1 */
  if(u/2>1000000000)r=r+21;     /* unsigned div: huge (signed -1/2 would be 0) */
  if(u%2==1)r=r+21;             /* 2^64-1 is odd -> unsigned remainder 1 */
  return r;                     /* 42 */
}
