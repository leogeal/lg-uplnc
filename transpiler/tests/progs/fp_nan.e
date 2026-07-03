/* NaN is unordered: == false, != true, ordered comparisons false, truthy as
   non-zero. This must be consistent across all FP backends. -> 42 */
func main()
{
  var double:z;var double:n;var int:r;
  z=0.0;n=z/z;r=0;
  if(n!=n)r=r+8;
  if(!(n==n))r=r+8;
  if(!(n<1.0))r=r+4;
  if(!(n<=1.0))r=r+4;
  if(!(n>1.0))r=r+4;
  if(!(n>=1.0))r=r+4;
  if(n)r=r+10;
  return r;
}
