/* global variable initializers: static values laid down in .data (.rodata when
   const -- a stray pointer write faults instead of corrupting silently). Int,
   char, double, float, wide 64-bit, negative, unsigned; const stays readable
   and assignment to it is rejected at compile time (see run_tests [4]). -> 42 */
var int:gi = 30;
var const int:gc = 2;
var char:gch = 65;
var double:gd = 2.5;
var float:gf = 1.5;
var double:gnd = -2.5;
var const long long:gwc = 10000000000;
var unsigned:gu = 3;
func main()
{
  var int:r;
  r=0;
  gi=gi+10;                      /* non-const global stays writable */
  if(gi==40)r=r+7;
  if(gc==2)r=r+7;
  if(gch==65)r=r+7;
  if(gd*2.0==5.0)r=r+6;
  if(gf+gf==3.0)r=r+5;           /* .float storage widens to double on load */
  if(gnd<-2.0)r=r+5;
  if(gwc/100000==100000)r=r+3;   /* wide 64-bit const from .rodata */
  if(gu==3)r=r+2;
  return r;                      /* 42 */
}
