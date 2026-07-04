func main()
{
  var long long:x;var long long:y;var int:r;
  r=0;
  x=1;x=x<<40;
  y=x|1;
  if(y>>40==1)r=r+8;
  y=y^x;
  if(y==1)r=r+8;
  y=(x|255)&255;
  if(y==255)r=r+8;
  y=0;y=y-1;++y;
  if(y==0)r=r+6;           /* ++ carries out of low word */
  y=0;y--;
  if(y<0)r=r+6;            /* -- borrows into high word */
  y=5;
  if(y++==5)r=r+3;
  if(y==6)r=r+3;
  return r;                /* 42 */
}
