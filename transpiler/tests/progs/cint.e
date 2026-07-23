#include "../../../examples/cint.he"

func main()
{
  var int:e;
  var long long:w;
  e=0;
  if(cint(0)!=0)e++;
  if(cint(2147483647)!=2147483647)e++;
  if(cint(0xffffffff)!=(0-1))e++;
  if(cint(0x80000000)!=(-2147483647-1))e++;
  if(sizeof(int)==8)
  {
    /* Only the low C-int half is meaningful, regardless of upper-word bits. */
    w=0x12345678;w=(w<<32)|0xffffffff;
    if(cint(w)!=(0-1))e++;
    w=0x12345678;w=(w<<32)|0x80000000;
    if(cint(w)!=(-2147483647-1))e++;
    w=0x6dcba987;w=~(w<<32);
    if(cint(w)!=(0-1))e++;
  }
  if(!e)return 42;
  return 60+e;
}
