/* Stable bottom-up mergesort and ASCII byte comparators. Comparator addresses
   cross the unit boundary and are called indirectly by sort_merge(). */
#include "sort_order.he"

func malloc(n:int);
func free(p:int);

func sort_fold(c:int)
{
  if((c>='A')&&(c<='Z'))return c+('a'-'A');
  return c;
}

func sort_compare(a:*char,b:*char)
{
  var unsigned char:ca;
  var unsigned char:cb;
  while(*a&&*b)
  {
    ca=*a++;
    cb=*b++;
    if(ca<cb)return 0-1;
    if(ca>cb)return 1;
  }
  if(*a)return 1;
  if(*b)return 0-1;
  return 0;
}

func sort_foldcmp(a:*char,b:*char)
{
  var unsigned char:ca;
  var unsigned char:cb;
  while(*a&&*b)
  {
    ca=sort_fold(*a++);
    cb=sort_fold(*b++);
    if(ca<cb)return 0-1;
    if(ca>cb)return 1;
  }
  if(*a)return 1;
  if(*b)return 0-1;
  return 0;
}

func sort_merge(line:**char,tmp:**char,left:int,mid:int,right:int,cmp:int,reverse:int)
{
  var int:i = left;
  var int:j = mid;
  var int:k = left;
  var int:c;
  while((i<mid)&&(j<right))
  {
    c=cmp(line[i],line[j]);
    if(reverse)c=0-c;
    if(c<=0)tmp[k++]=line[i++];
    else tmp[k++]=line[j++];
  }
  while(i<mid)tmp[k++]=line[i++];
  while(j<right)tmp[k++]=line[j++];
  for(k=left;k<right;k++)line[k]=tmp[k];
  return 0;
}

func sort_order(line:**char,n:int,cmp:int,reverse:int)
{
  var **char:tmp;
  var int:width = 1;
  var int:left;
  var int:mid;
  var int:right;
  if(n<2)return 0;
  tmp=malloc(n*sizeof(int));
  if(!tmp)return 0-1;
  while(width<n)
  {
    left=0;
    while(left<n)
    {
      mid=left+width;
      if(mid>n)mid=n;
      right=mid+width;
      if(right>n)right=n;
      if(mid<right)sort_merge(line,tmp,left,mid,right,cmp,reverse);
      left=right;
    }
    if(width>n/2)width=n;
    else width=width*2;
  }
  free(tmp);
  return 0;
}
