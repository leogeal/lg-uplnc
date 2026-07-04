func one():long long
{
  return 1;
}
func negi():long long
{
  var int:i;
  i=0-1;
  return i;
}
func bigd():long long
{
  var double:d;
  d=1000000;d=d*d;
  return d;
}
func main()
{
  var long long:x;var int:r;
  r=0;
  x=one();if(x==1)r=r+14;          /* int literal -> long long return */
  x=negi();if(x<0)r=r+14;          /* signed int -> long long return */
  x=bigd();if(x>1000000000)r=r+14; /* double -> long long return */
  return r;                        /* 42 */
}
