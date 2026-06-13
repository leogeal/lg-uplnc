/* FP-array fix: 4-byte float array element load/store (cvtss2sd / cvtsd2ss). */
func main()
{
  var [4]float:a;
  var int:i;
  var double:s;
  i=0;
  while(i<4){a[i]=10.5;i=i+1;}
  s=0.0;
  i=0;
  while(i<4){s=s+a[i];i=i+1;}
  return s;
}
