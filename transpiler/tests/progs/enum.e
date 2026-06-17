/* enum constants: sequential (0..3), explicit value + continue (40,41),
   constant-expression values (1<<n), a prior-enum reference (Y=X+5), and an
   enum constant used as an array dimension. Returns 42. */
enum { ZERO, ONE, TWO, THREE };
enum { BASE=40, NEXT };
enum { FA=1<<0, FB=1<<1, FC=1<<2 };
enum { X=10, Y=X+5 };
enum { SZ=4 };
func main()
{
  var [SZ]int:a;
  var int:r;
  a[0]=BASE;a[1]=TWO;a[2]=0;a[3]=0;
  r=a[0]+a[1];
  if(THREE!=3)r=100;
  if(NEXT!=41)r=101;
  if((FA|FB|FC)!=7)r=102;
  if(Y!=15)r=103;
  return r;
}
