/* Byte churning: build, reverse, and scan a 32 KiB buffer repeatedly. All
   traffic is char loads/stores through arrays and pointers (LDB/STB paths and
   byte narrowing). Checksum is width-independent by construction. */
#define BUFSZ 32768
#define REPS 900
var buf:[BUFSZ]char;
func fill()
{
  var int:i;
  for(i=0;i<BUFSZ;i=i+1)buf[i]=(i*7+13)&127;
}
func reverse()
{
  var int:i,j;
  var char:t;
  i=0;j=BUFSZ-1;
  while(i<j)
  {
    t=buf[i];buf[i]=buf[j];buf[j]=t;
    i=i+1;j=j-1;
  }
}
func scan()
{
  var *char:p;
  var int:s,n;
  p=buf;s=0;n=BUFSZ;
  while(n)
  {
    s=(s+*p)&1048575;
    p=p+1;n=n-1;
  }
  return s;
}
func main()
{
  var int:r,k,total;
  fill();
  total=0;
  for(k=0;k<REPS;k=k+1)
  {
    reverse();
    total=(total+scan())&1048575;
  }
  r=total;
  printf("strops %d %d\n",r,REPS);
  if(r==983040)return 0;
  return 1;
}
