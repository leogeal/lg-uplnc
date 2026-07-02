/* char* arithmetic steps by 1 byte (element size 1). Returns 42. */
func main()
{
  var [6]char:buf; var *char:p; var int:s;
  buf[0]=10;buf[1]=20;buf[2]=30;buf[3]=40;buf[4]=50;buf[5]=60;
  p = &buf[0];
  s = *p;                    /* 10 */
  s = s + *(p + 3);          /* buf[3]=40 -> 50 */
  p = p + 5;                 /* &buf[5] */
  s = s + *p;                /* 60 -> 110 */
  s = s + (p - &buf[0]);     /* char* diff = 5 -> 115 */
  return s - 73;             /* 42 */
}
