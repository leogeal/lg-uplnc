/* hexdump: offset + 16 hex bytes + ASCII column ("od"-lite), reading stdin.
   A real utility dogfooding lib/fmt.e (putf %08x/%02x padding), byte handling
   (getchar values 0..255) and array-decay argument passing. */
#include "../lib/fmt.e"

func dumpline(b:*int,n:int,off:int)
{
  var i:int = 0;
  putf("%08x ",off);
  while(i<16)
  {
    if(i<n)putf(" %02x",b[i]);
    else putstr("   ");
    i++;
  }
  putstr("  |");
  i=0;
  while(i<n)
  {
    if((b[i]>=32)&&(b[i]<127))putchar(b[i]);
    else putchar('.');
    i++;
  }
  putstr("|\n");
  return 0;
}

func main()
{
  var [16]int:buf;
  var n:int = 0;
  var off:int = 0;
  var c:int;
  while((c=getchar())>=0)
  {
    buf[n++]=c;
    if(n==16)
    {
      dumpline(buf,n,off);
      off=off+16;
      n=0;
    }
  }
  if(n)dumpline(buf,n,off);
  return 0;
}
