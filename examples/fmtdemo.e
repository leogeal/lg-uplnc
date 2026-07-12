/* fmtdemo: exercises every lib/fmt.e format feature and prints a FIXED text
   that the test harness diffs byte-for-byte -- the library's output contract.
   The values are chosen to print identically on every backend (word-size
   independent). */
#include "../lib/fmt.e"

func main()
{
  putf("int: %d %d %d\n",42,0-7,0);
  putf("pad: [%6d] [%06d] [%6d]\n",42,42,0-42);
  putf("unsigned: %u\n",4294967295);
  putf("hex: %x [%08x] [%8x]\n",255,48879,48879);
  putf("str: %s, char: %c%c%c, pct: 100%%\n","abc",'x','y','z');
  putf("mix: %s=%d (%04x)\n","val",1000,1000);
  return 0;
}
