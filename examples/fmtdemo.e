/* fmtdemo: exercises every lib/fmt.e format feature and prints a FIXED text
   that the test harness diffs byte-for-byte -- the library's output contract.
   The values are chosen to print identically on every backend (word-size
   independent). */
#include "../lib/fmt.he"

func main()
{
  var unsigned:u = 4294967295;
  var double:z = 0.0;
  putf("int: %d %d %d\n",42,0-7,0);
  putf("pad: [%6d] [%06d] [%6d]\n",42,42,0-42);
  putf("unsigned: %u\n",u);
  putf("hex: %x [%08x] [%8x]\n",255,48879,48879);
  putf("str: %s, char: %c%c%c, pct: 100%%\n","abc",'x','y','z');
  putf("mix: %s=%d (%04x)\n","val",1000,1000);
  putf("flt: %f %.2f %.0f\n",1.5,3.14159,2.5);
  putf("fpad: [%10.3f] [%010.3f] [%.3f]\n",0.0-2.5,2.5,0.0625);
  putf("fedge: [%f] [%.9999999999999999999f]\n",
       (0.0-1.0)/(1.0/z),1.25);
  putstr("fclamp: [");putfpad(1.25,0,' ',0-1);putstr("] [");
  putfpad(1.25,0,' ',99);putstr("]\n");
  putf("sci: %e %.2e [%012.2e] %e\n",1.5,9.996,0.00025,0.0-42.125);
  putf("gen: %g %g %g %g",2.5,100.0,0.0001,0.00001);
  putf(" %.3g %g\n",123.456,1234567.0);
  return 0;
}
