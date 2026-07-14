/* sort -- a dynamic, multi-unit UPLNC text sorting utility.

   Supports -f (ASCII case-fold), -r (reverse), -u (unique under the selected
   comparator), combined short options, --, stdin, and multiple files. Input
   lines and the line-pointer array grow dynamically up to the safety limits in
   sort_lines.he. Embedded NUL is rejected rather than silently truncating.

   Exit status: 0 success, 2 usage/input/output/resource error.
   Build: perl src/langdrv.pl -march=x86_64 examples/sort.e \
          examples/sort_lines.e examples/sort_order.e -o sort */

#include "sort_lines.he"
#include "sort_order.he"

var extern stderr,stdin,stdout:*int;
func fopen(name:*char,mode:*char):*int;
func fclose(fp:*int);
func ferror(fp:*int);

func sort_streq(a:*char,b:*char)
{
  while(*a&&(*a==*b)){a++;b++;}
  return *a==*b;
}

func sort_isdash(s:*char)
{
  return (s[0]=='-')&&!s[1];
}

func sort_report(name:*char,rc:int,lineno:int)
{
  if(rc==SORT_NOMEM)fprintf(stderr,"sort: out of memory\n");
  else if(rc==SORT_TOOLONG)
    fprintf(stderr,"sort: %s:%d: line too long\n",name,lineno);
  else if(rc==SORT_TOOMANY)
    fprintf(stderr,"sort: too many input lines\n");
  else if(rc==SORT_READERR)
    fprintf(stderr,"sort: %s: read error\n",name);
  else if(rc==SORT_NULBYTE)
    fprintf(stderr,"sort: %s:%d: embedded NUL is not supported\n",name,lineno);
  return 0;
}

func sort_usage()
{
  fprintf(stderr,"usage: sort [-fru] [file ...]\n");
  return 2;
}

func main(argc:int,argv:**char)
{
  var sortset:set;
  var *int:fp;
  var int:i = 1;
  var int:k;
  var int:fold = 0;
  var int:reverse = 0;
  var int:unique = 0;
  var int:haderror = 0;
  var int:fatal = 0;
  var int:rc;
  var int:lineno;
  var int:cmp;
  sortset_init(&set);

  while((i<argc)&&(argv[i][0]=='-')&&argv[i][1])
  {
    if(sort_streq(argv[i],"--")){i++;break;}
    k=1;
    while(argv[i][k])
    {
      if(argv[i][k]=='f')fold=1;
      else if(argv[i][k]=='r')reverse=1;
      else if(argv[i][k]=='u')unique=1;
      else
      {
        fprintf(stderr,"sort: unknown option -%c\n",argv[i][k]);
        sortset_done(&set);
        return sort_usage();
      }
      k++;
    }
    i++;
  }

  if(i>=argc)
  {
    rc=sortset_read(&set,stdin,&lineno);
    if(rc)
    {
      sort_report("(standard input)",rc,lineno);
      if(rc==SORT_READERR)haderror=1;
      else fatal=1;
    }
  }
  else while((i<argc)&&!fatal)
  {
    if(sort_isdash(argv[i]))
    {
      rc=sortset_read(&set,stdin,&lineno);
      if(rc)
      {
        sort_report("(standard input)",rc,lineno);
        if(rc==SORT_READERR)haderror=1;
        else fatal=1;
      }
    }
    else
    {
      fp=fopen(argv[i],"r");
      if(!fp)
      {
        fprintf(stderr,"sort: %s: cannot open\n",argv[i]);
        haderror=1;
      }
      else
      {
        rc=sortset_read(&set,fp,&lineno);
        if(rc)
        {
          sort_report(argv[i],rc,lineno);
          if(rc==SORT_READERR)haderror=1;
          else fatal=1;
        }
        if(fclose(fp))
        {
          fprintf(stderr,"sort: %s: close error\n",argv[i]);
          haderror=1;
        }
      }
    }
    i++;
  }

  if(fatal)
  {
    sortset_done(&set);
    return 2;
  }
  if(fold)cmp=sort_foldcmp;
  else cmp=sort_compare;
  if(sort_order(set.line,set.count,cmp,reverse))
  {
    fprintf(stderr,"sort: out of memory\n");
    sortset_done(&set);
    return 2;
  }
  for(i=0;i<set.count;i++)
  {
    if(unique&&i&&(cmp(set.line[i-1],set.line[i])==0))continue;
    puts(set.line[i]);
  }
  if(ferror(stdout))
  {
    fprintf(stderr,"sort: write error\n");
    haderror=1;
  }
  sortset_done(&set);
  if(haderror)return 2;
  return 0;
}
