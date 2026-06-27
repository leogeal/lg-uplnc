func main()
{
  var unsigned:a; var unsigned:b; var int:s; var int:e;
  e=0;
  a = 0; a = a - 1;              /* max unsigned (all ones) */
  if(!(a > 100))e=e+1;          /* unsigned: huge > 100 */
  if(a < 100)e=e+1;             /* unsigned: false */
  b = a >> 1;                    /* unsigned: LOGICAL shift -> top bit cleared */
  if(b == a)e=e+1;              /* if equal it used arithmetic shift (BUG) */
  if(!(b < a))e=e+1;            /* unsigned: b < a */
  s = 0 - 1;                     /* signed -1 */
  if((s >> 1) != (0 - 1))e=e+1; /* signed >> stays arithmetic: -1>>1 == -1 */
  a = 10; b = 20;
  if(!((a + b) > 5))e=e+1;      /* (a+b) stays unsigned, compare ok */
  if(e==0)return 42;
  return 60+e;
}
