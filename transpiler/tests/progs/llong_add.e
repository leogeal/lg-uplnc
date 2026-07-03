func main()
{
  var long long:a;var long long:b;var long long:c;var int:r;
  a=2000000000;b=2000000000;
  c=a+b;                 /* 4e9, needs 64 bits */
  r=0;
  if(c-a==b)r=r+10;      /* 64-bit add held */
  if(c>a)r=r+8;          /* signed > */
  if(a<c)r=r+4;          /* signed < */
  if(c>=c)r=r+4;         /* >= equal */
  b=-a;                  /* neg */
  if(b<0)r=r+4;          /* neg negative */
  if(a+b==0)r=r+4;       /* a + (-a) == 0 */
  if(a!=c)r=r+4;         /* != */
  a=5;b=7;
  if(b-a==2)r=r+4;       /* small sub */
  return r;              /* 42 */
}
