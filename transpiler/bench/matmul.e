/* Integer matrix multiply: triple loop, array indexing arithmetic (the scaled
   pointer adds), accumulation in a register-promotable local. Deterministic
   pseudo-random input; checksum verified against a precomputed value. */
#define N 120
var a:[14400]int;
var b:[14400]int;
var c:[14400]int;
func mkinput()
{
  /* Lehmer LCG mod 65537: every intermediate stays below 2^23, so the same
     sequence appears on 32-bit and 64-bit ints alike (no overflow anywhere). */
  var int:i,s;
  s=1;
  for(i=0;i<N*N;i=i+1)
  {
    s=(s*75+74)%65537;
    a[i]=s&255;
    s=(s*75+74)%65537;
    b[i]=s&255;
  }
}
func matmul()
{
  var int:i,j,k,acc;
  for(i=0;i<N;i=i+1)
  {
    for(j=0;j<N;j=j+1)
    {
      acc=0;
      for(k=0;k<N;k=k+1)acc=acc+a[i*N+k]*b[k*N+j];
      c[i*N+j]=acc;
    }
  }
}
func main()
{
  var int:i,rep,sum;
  mkinput();
  for(rep=0;rep<30;rep=rep+1)matmul();
  sum=0;
  for(i=0;i<N*N;i=i+1)sum=(sum+c[i])&1073741823;
  printf("matmul %d 30\n",sum);
  if(sum==212720775)return 0;
  return 1;
}
