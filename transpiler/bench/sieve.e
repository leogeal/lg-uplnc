/* Sieve of Eratosthenes: array stores/loads and tight nested loops (the
   promote-locals + peephole sweet spot). Self-checking: 9592 primes < 100000.
   Prints "sieve <primes> <reps>" and returns 0 on the expected checksum. */
#define LIMIT 100000
#define REPS 300
var flags:[LIMIT]char;
func sieve()
{
  var int:i,j,count;
  for(i=0;i<LIMIT;i=i+1)flags[i]=1;
  flags[0]=0;
  flags[1]=0;
  for(i=2;i*i<LIMIT;i=i+1)
  {
    if(flags[i])
    {
      for(j=i*i;j<LIMIT;j=j+i)flags[j]=0;
    }
  }
  count=0;
  for(i=0;i<LIMIT;i=i+1)if(flags[i])count=count+1;
  return count;
}
func main()
{
  var int:r,n,total;
  total=0;
  for(n=0;n<REPS;n=n+1)total=total+sieve();
  r=total/REPS;
  printf("sieve %d %d\n",r,REPS);
  if((r==9592)&&(total==REPS*9592))return 0;
  return 1;
}
