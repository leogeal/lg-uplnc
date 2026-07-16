/* Naive recursive Fibonacci: pure call/return + frame setup/teardown traffic
   (prologue/epilogue, argument marshaling, MODSTK after calls). fib(30) makes
   about 2.7 million calls. Self-checking: fib(30) = 832040. */
func fib(n:int)
{
  if(n<2)return n;
  return fib(n-1)+fib(n-2);
}
func main()
{
  var int:r,k,total;
  total=0;
  for(k=0;k<15;k=k+1)total=total+fib(30);
  r=total/15;
  printf("fib %d 15\n",r);
  if((r==832040)&&(total==15*832040))return 0;
  return 1;
}
