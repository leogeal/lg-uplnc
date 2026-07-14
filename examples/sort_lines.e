/* Dynamic line reader/storage for sort.e. The final newline is not stored;
   sort.e writes one newline for every logical input line. */
#include "sort_lines.he"

func malloc(n:int);
func realloc(p:int,n:int);
func free(p:int);
func ferror(fp:*int);

func sortset_init(s:*sortset)
{
  s->line=0;
  s->count=0;
  s->cap=0;
  return 0;
}

func sortset_append(s:*sortset,buf:*char,n:int)
{
  var **char:np;
  var *char:copy;
  var int:newcap;
  var int:i;
  if(s->count>=SORT_COUNTMAX)return SORT_TOOMANY;
  if(s->count>=s->cap)
  {
    if(!s->cap)newcap=32;
    else newcap=s->cap*2;
    if(newcap>SORT_COUNTMAX)newcap=SORT_COUNTMAX;
    np=realloc(s->line,newcap*sizeof(int));
    if(!np)return SORT_NOMEM;
    s->line=np;
    s->cap=newcap;
  }
  copy=malloc(n+1);
  if(!copy)return SORT_NOMEM;
  for(i=0;i<n;i++)copy[i]=buf[i];
  copy[n]=0;
  s->line[s->count++]=copy;
  return SORT_OK;
}

func sortset_read(s:*sortset,fp:*int,badline:*int)
{
  var *char:buf;
  var *char:np;
  var int:cap = 128;
  var int:n = 0;
  var int:lineno = 1;
  var int:c;
  var int:newcap;
  var int:rc;
  *badline=lineno;
  buf=malloc(cap);
  if(!buf)return SORT_NOMEM;
  while((c=fgetc(fp))>=0)
  {
    if(c==0)
    {
      *badline=lineno;
      free(buf);
      return SORT_NULBYTE;
    }
    if(c==10)
    {
      rc=sortset_append(s,buf,n);
      if(rc)
      {
        *badline=lineno;
        free(buf);
        return rc;
      }
      n=0;
      lineno++;
      continue;
    }
    if(n>=SORT_LINEMAX)
    {
      *badline=lineno;
      free(buf);
      return SORT_TOOLONG;
    }
    if(n+1>=cap)
    {
      newcap=cap*2;
      if(newcap>SORT_LINEMAX+1)newcap=SORT_LINEMAX+1;
      np=realloc(buf,newcap);
      if(!np)
      {
        *badline=lineno;
        free(buf);
        return SORT_NOMEM;
      }
      buf=np;
      cap=newcap;
    }
    buf[n++]=c;
  }
  if(ferror(fp))
  {
    *badline=lineno;
    free(buf);
    return SORT_READERR;
  }
  if(n)
  {
    rc=sortset_append(s,buf,n);
    if(rc)
    {
      *badline=lineno;
      free(buf);
      return rc;
    }
  }
  free(buf);
  return SORT_OK;
}

func sortset_done(s:*sortset)
{
  var int:i;
  for(i=0;i<s->count;i++)free(s->line[i]);
  free(s->line);
  s->line=0;
  s->count=0;
  s->cap=0;
  return 0;
}
