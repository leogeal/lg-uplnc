func main()
{
  var unsigned long long:u;var int:r;
  u=0;u=u-1;             /* 2^64-1 : huge unsigned */
  r=0;
  if(u>1000)r=r+21;      /* unsigned >: huge > 1000 (signed would be -1<1000) */
  if(u>=u)r=r+21;        /* unsigned >= equal */
  return r;              /* 42 */
}
