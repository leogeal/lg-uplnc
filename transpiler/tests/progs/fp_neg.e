/* floating-point unary minus must negate the FP value (fneg/fchs/neg.d), not the
   integer accumulator, and FP comparisons must drive a while condition. -> 42 */
func main()
{
  var double:x;var double:d;var int:n;var int:r;
  x=5.0;x=-x;           /* x = -5.0 */
  r=47+x;               /* 47 + (-5) = 42 (x truncates to -5) */
  d=3.0;n=0;
  while(d>0.5){d=d-1.0;n=n+1;}   /* loops 3 times: FP relational condition */
  if(n!=3)r=0;
  return r;
}
