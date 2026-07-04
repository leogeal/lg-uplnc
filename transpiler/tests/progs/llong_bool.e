func main()
{
  var long long:x;var int:r;var int:i;
  r=0;
  x=1;x=x<<40;
  if(x)r=r+7;              /* high-word-only value is true */
  if(!x)r=r+100;           /* must not fire */
  if(x&&1)r=r+7;
  if(0||x)r=r+7;
  while(x){r=r+7;x=0;}
  if(!x)r=r+7;
  x=1;x=x<<40;i=0;
  do{i=i+1;if(i==2)x=0;}while(x);
  if(i==2)r=r+7;
  return r;                /* 42 */
}
