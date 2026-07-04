/* 64-bit long long function arguments and return values. On i386 a long long
   arg is 8 bytes on the cdecl stack and the return is in %edx:%eax; on the 64-bit
   backends it is the word int. Exercises large values, so the high word must
   survive the call boundary. -> 42 */
func addll(a:long long,b:long long):long long
{
  return a+b;
}
func shiftr(a:long long,n:int):long long
{
  return a>>n;
}
func main()
{
  var long long:x;var long long:r;var int:res;
  res=0;
  x=1;
  x=x<<40;                       /* 2^40 */
  r=addll(x,x);                  /* 2^41, two ll args + ll return */
  if(r>>41==1)res=res+14;        /* full 64 bits survived */
  if(shiftr(r,41)==1)res=res+14; /* mixed ll,int args */
  x=1000000;
  x=x*x;                         /* 10^12 */
  if(addll(x,x)==x+x)res=res+14; /* large ll args preserved */
  return res;                    /* 42 */
}
