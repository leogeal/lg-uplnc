/* buf.e: the IDE's editable text buffer. See buf.he for the shape.

   Every operation is bounds-checked and does nothing on an out-of-range
   index, so the editor's cursor arithmetic cannot corrupt the buffer -- a
   miscalculated column becomes a no-op rather than a wild store.

   File model: load splits on newline, and a final newline does not create an
   extra empty line; save writes every line followed by a newline. A file that
   did not end with a newline therefore gains one, which is the usual editor
   behaviour and keeps the round trip exact for source files. */

#include "buf.he"

func malloc(n:int);
func realloc(p:int,n:int);
func free(p:int);
func exit(c:int);
func fopen(n:*char,m:*char):*int;
func fgetc(fp:*int);
func fputc(c:int,fp:*int);
func fclose(fp:*int);
func ferror(fp:*int);
var extern stderr:*int;

func bfoom()
{
  fprintf(stderr,"buf: out of memory\n");
  exit(2);
  return 0;
}

method sbuf.init()
{
  a=BF_ROWS0;
  l=malloc(a*sizeof(sbline));
  if(!l)bfoom();
  n=1;
  l[0].cap=BF_CHUNK;
  l[0].s=malloc(BF_CHUNK);
  if(!l[0].s)bfoom();
  l[0].s[0]=0;
  l[0].len=0;
  dirty=0;
  return 0;
}

method sbuf.done()
{
  var i:int;
  if(!l)return 0;
  for(i=0;i<n;i++)if(l[i].s)free(l[i].s);
  free(l);
  l=0;
  n=0;
  a=0;
  return 0;
}

method sbuf.grow(need:int)
{
  if(need<=a)return 0;
  while(a<need)a=a*2;
  l=realloc(l,a*sizeof(sbline));
  if(!l)bfoom();
  return 0;
}

method sbuf.setcap(i:int,c:int)
{
  var nc:int;
  if((i<0)||(i>=n))return 0;
  if(c+1<=l[i].cap)return 0;
  nc=l[i].cap;
  while(nc<c+1)nc=nc*2;
  l[i].s=realloc(l[i].s,nc);
  if(!l[i].s)bfoom();
  l[i].cap=nc;
  return 0;
}

method sbuf.insline(i:int)
{
  var j:int;
  if((i<0)||(i>n))return 0;
  this->grow(n+1);
  for(j=n;j>i;j--)
  {
    l[j].s=l[j-1].s;
    l[j].len=l[j-1].len;
    l[j].cap=l[j-1].cap;
  }
  l[i].cap=BF_CHUNK;
  l[i].s=malloc(BF_CHUNK);
  if(!l[i].s)bfoom();
  l[i].s[0]=0;
  l[i].len=0;
  n=n+1;
  dirty=1;
  return 0;
}

method sbuf.delline(i:int)
{
  var j:int;
  if((i<0)||(i>=n))return 0;
  if(n==1)                 /* the last line is emptied, never removed */
  {
    l[0].s[0]=0;
    l[0].len=0;
    dirty=1;
    return 0;
  }
  free(l[i].s);
  for(j=i;j<n-1;j++)
  {
    l[j].s=l[j+1].s;
    l[j].len=l[j+1].len;
    l[j].cap=l[j+1].cap;
  }
  n=n-1;
  dirty=1;
  return 0;
}

method sbuf.line(i:int)
{
  if((i<0)||(i>=n))return "";
  return l[i].s;
}

method sbuf.llen(i:int)
{
  if((i<0)||(i>=n))return 0;
  return l[i].len;
}

method sbuf.insch(i:int,col:int,c:int)
{
  var j:int;
  if((i<0)||(i>=n))return 0;
  if((col<0)||(col>l[i].len))return 0;
  this->setcap(i,l[i].len+1);
  for(j=l[i].len;j>col;j--)l[i].s[j]=l[i].s[j-1];
  l[i].s[col]=c;
  l[i].len=l[i].len+1;
  l[i].s[l[i].len]=0;
  dirty=1;
  return 0;
}

method sbuf.delch(i:int,col:int)
{
  var j:int;
  if((i<0)||(i>=n))return 0;
  if((col<0)||(col>=l[i].len))return 0;
  for(j=col;j<l[i].len-1;j++)l[i].s[j]=l[i].s[j+1];
  l[i].len=l[i].len-1;
  l[i].s[l[i].len]=0;
  dirty=1;
  return 0;
}

method sbuf.split(i:int,col:int)
{
  var j,tail:int;
  if((i<0)||(i>=n))return 0;
  if((col<0)||(col>l[i].len))return 0;
  tail=l[i].len-col;
  this->insline(i+1);
  this->setcap(i+1,tail);
  for(j=0;j<tail;j++)l[i+1].s[j]=l[i].s[col+j];
  l[i+1].s[tail]=0;
  l[i+1].len=tail;
  l[i].len=col;
  l[i].s[col]=0;
  dirty=1;
  return 0;
}

method sbuf.join(i:int)
{
  var j,at:int;
  if((i<0)||(i+1>=n))return 0;
  at=l[i].len;
  this->setcap(i,at+l[i+1].len);
  for(j=0;j<l[i+1].len;j++)l[i].s[at+j]=l[i+1].s[j];
  l[i].len=at+l[i+1].len;
  l[i].s[l[i].len]=0;
  this->delline(i+1);
  dirty=1;
  return 0;
}

method sbuf.load(nm:*char)
{
  var fp:*int;
  var c,bad:int;
  fp=fopen(nm,"r");
  if(!fp)return 0;
  this->done();
  this->init();
  while((c=fgetc(fp))>=0)
  {
    if(c==10)
    {
      this->insline(n);          /* a newline ends this line */
      continue;
    }
    this->insch(n-1,l[n-1].len,c);
  }
  bad=ferror(fp);
  fclose(fp);
  /* a trailing newline ended the last line: drop the empty line it opened,
     but never below the one line the buffer always keeps */
  if((n>1)&&(l[n-1].len==0))this->delline(n-1);
  dirty=0;
  if(bad)return 0;
  return 1;
}

method sbuf.save(nm:*char)
{
  var fp:*int;
  var i,j:int;
  fp=fopen(nm,"w");
  if(!fp)return 0;
  for(i=0;i<n;i++)
  {
    for(j=0;j<l[i].len;j++)fputc(l[i].s[j],fp);
    fputc(10,fp);
  }
  if(ferror(fp)){fclose(fp);return 0;}
  if(fclose(fp))return 0;
  dirty=0;
  return 1;
}
