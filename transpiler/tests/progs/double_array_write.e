/* FP-array fix: variable-indexed double array element *stores* (movsd ->(%rdx)). */
func main()
{
  var [4]double:a;
  var int:i;
  var double:s;
  i=0;
  while(i<4){a[i]=10.5;i=i+1;}
  s=0.0;
  i=0;
  while(i<4){s=s+a[i];i=i+1;}
  return s;
}
