func main()
{
  var unsigned:a; var unsigned:b; var int:e;
  e=0;
  a = 0; a = a - 1;          /* max unsigned (all ones, odd) */
  b = a / 2;                 /* unsigned: huge; signed -1/2 would be 0 */
  if(b < 1000000)e=e+1;
  if((a - b*2) != 1)e=e+1;   /* a odd: a - 2*(a/2) = 1 */
  a = 100; b = 7;
  if((a / b) != 14)e=e+1;    /* 100/7 = 14 */
  if((a % b) != 2)e=e+1;     /* 100%7 = 2 */
  a = 0; a = a - 1;          /* max unsigned */
  if((a % 10) != 5)e=e+1;    /* unsigned: ...5; signed -1%10 = -1 */
  if(e==0)return 42;
  return 60+e;
}
