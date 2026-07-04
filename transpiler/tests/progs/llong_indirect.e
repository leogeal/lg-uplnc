func main()
{
  var [3]long long:a;var long long:x;var *long long:p;var int:r;
  r=0;
  p=&a[0];
  p[0]=1000000;
  p[1]=p[0]*p[0];
  if(p[1]>1000000000)r=r+14; /* array/index load and store */
  x=0;p=&x;
  *p=1;*p=*p<<40;
  if(x>>40==1)r=r+14;         /* pointer load and store */
  p=&a[2];
  *p=a[1];
  if(a[2]==a[1])r=r+14;       /* copy through a pointer */
  return r;                   /* 42 */
}
