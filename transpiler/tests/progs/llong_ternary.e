func main()
{
  var long long:y;var long long:x;var long long:init;var int:c;var int:r;
  r=0;
  init=1;
  if(init==1)r=r+6;
  y=1;y=y<<40;
  c=0;x=c?1:y;             /* else arm is long long */
  if(x>>40==1)r=r+9;
  c=1;x=c?y:1;             /* then arm is long long */
  if(x>>40==1)r=r+9;
  c=1;x=c?1:y;             /* then arm needs int -> long long */
  if(x==1)r=r+9;
  c=0;x=c?y:1;             /* else arm needs int -> long long */
  if(x==1)r=r+9;
  return r;                /* 42 */
}
