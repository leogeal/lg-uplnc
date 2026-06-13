/* FP-array fix: variable-indexed double array element loads (movsd off(%rax)). */
func main()
{
  var [3]double:a;
  var int:i;
  var double:s;
  a[0]=10.0;
  a[1]=12.0;
  a[2]=20.0;
  s=0.0;
  i=0;
  while(i<3){s=s+a[i];i=i+1;}
  return s;
}
