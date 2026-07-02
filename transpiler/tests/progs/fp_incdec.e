/* floating-point ++/-- (pre and post) must add/subtract 1.0 in the FP unit, not
   the integer accumulator, on every backend (i386 x87 duplicates st0 so the
   popping store keeps the value). -> 42 */
func main()
{
  var double:d;var double:o;var int:r;
  r=0;
  d=5.0;++d;             /* d = 6.0 */
  if(d==6.0)r=r+10;      /* pre-increment      -> 10 */
  --d;--d;               /* d = 4.0 */
  if(d==4.0)r=r+10;      /* pre-decrement      -> 20 */
  d=5.0;o=d++;           /* o = 5.0, d = 6.0 */
  if(o==5.0)r=r+11;      /* post-inc yields old-> 31 */
  if(d==6.0)r=r+11;      /* and updates the var-> 42 */
  return r;
}
