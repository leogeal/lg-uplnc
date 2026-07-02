/* floating-point truthiness and logical operators: a double used directly in a
   condition, and in ! / && / ||, must test the FP value (!= 0.0), not the stale
   integer accumulator. -> 42 */
func main()
{
  var double:z;var double:nz;var int:r;
  z=0.0;nz=3.0;r=0;
  if(nz)r=r+10;       /* nonzero double is true      -> 10 */
  if(!z)r=r+20;       /* !0.0 is true                -> 30 */
  if(nz&&1)r=r+8;     /* nonzero double && 1 is true -> 38 */
  if(z||4)r=r+4;      /* 0.0 || 4 is true            -> 42 */
  return r;
}
