/* floating-point comparisons: all six relational/equality operators must compile
   to real FP compares (not an integer compare of stale registers). -> 42 */
func main()
{
  var double:a;var double:b;var int:r;
  a=2.5;b=1.5;r=0;
  if(a>b)r=r+1;       /* 1  */
  if(b<a)r=r+2;       /* 3  */
  if(a>=2.5)r=r+4;    /* 7  */
  if(b<=1.5)r=r+8;    /* 15 */
  if(a!=b)r=r+16;     /* 31 */
  if(a==2.5)r=r+11;   /* 42 */
  return r;
}
