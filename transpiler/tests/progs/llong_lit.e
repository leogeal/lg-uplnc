/* wide (64-bit) integer literals. The lexer keeps a value that does not fit a
   signed 32-bit int as text (like float literals) and the assembler computes it,
   so this works whatever the compiler's own host width: movabsq/li/dli/ldr= on
   the 64-bit backends, a .quad pool pair-load on i386 (typed long long). -> 42 */
func main()
{
  var long long:x;var long long:y;var int:r;
  r=0;
  x=10000000000;                  /* decimal wide (10^10) */
  if(x/100000==100000)r=r+8;
  y=-5000000000;                  /* negative wide */
  if(y<0)r=r+8;
  if(x+y==5000000000)r=r+8;       /* wide op wide; wide as compare operand */
  x=0x1ffffffff;                  /* hex wide: 2^33-1 */
  if(x>>33==0)r=r+5;
  if((x>>1)==0xffffffff)r=r+5;    /* 8-digit high-bit hex: positive 2^32-1 */
  y=1;y=y<<40;
  if(y==1099511627776)r=r+8;      /* literal == computed 2^40 */
  return r;                       /* 42 */
}
