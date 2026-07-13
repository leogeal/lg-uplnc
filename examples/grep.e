/* grep -- a small, multi-file UPLNC utility.

   Supports -n (line numbers), -v (invert), -i (ASCII case-insensitive),
   combined short options, --, stdin, and multiple files. The pattern syntax
   is documented in grep_match.he. Text lines are limited to 1023 bytes; an
   overlong line is discarded and reported instead of being split silently.

   Exit status: 0 selected at least one line, 1 selected none, 2 error.
   Build: perl src/langdrv.pl -march=x86_64 examples/grep.e \
          examples/grep_match.e lib/fmt.e -o grep */

#include "grep_match.he"
#include "../lib/fmt.he"

#define GREP_LINEMAX 1024

var extern stderr,stdin:*int;
func fgets(s:*char,n:int,fp:*int):*char;
func fopen(name:*char,mode:*char):*int;
func fclose(fp:*int);
func ferror(fp:*int);

var grep_pattern:*char;
var grep_showline:int;
var grep_invert:int;
var grep_icase:int;
var grep_selected:int;
var grep_haderror:int;

func grep_streq(a:*char,b:*char)
{
  while(*a&&(*a==*b)){a++;b++;}
  return *a==*b;
}

func grep_isdash(s:*char)
{
  return (s[0]=='-')&&!s[1];
}

func grep_linelen(s:*char)
{
  var int:n = 0;
  while(s[n])n++;
  return n;
}

func grep_discard(fp:*int,c:int)
{
  while((c>=0)&&(c!=10))c=fgetc(fp);
  return 0;
}

func grep_putline(line:*char,n:int,name:*char,showname:int,lineno:int)
{
  if(showname){putstr(name);putchar(':');}
  if(grep_showline){putd(lineno);putchar(':');}
  putstr(line);
  if(!n||(line[n-1]!=10))putchar(10);
  return 0;
}

func grep_stream(fp:*int,name:*char,showname:int)
{
  var [GREP_LINEMAX]char:line;
  var int:n;
  var int:c;
  var int:lineno = 0;
  var int:selected;
  while(fgets(line,GREP_LINEMAX,fp))
  {
    lineno++;
    n=grep_linelen(line);
    if((n==GREP_LINEMAX-1)&&(line[n-1]!=10))
    {
      c=fgetc(fp);
      if(c>=0)
      {
        grep_discard(fp,c);
        fprintf(stderr,"grep: %s:%d: line too long\n",name,lineno);
        grep_haderror=1;
        continue;
      }
    }
    selected=grep_match(grep_pattern,line,grep_icase);
    if(selected<0)
    {
      fprintf(stderr,"grep: %s:%d: pattern match limit exceeded\n",name,lineno);
      grep_haderror=1;
      continue;
    }
    if(grep_invert)selected=!selected;
    if(selected)
    {
      grep_selected=1;
      grep_putline(line,n,name,showname,lineno);
    }
  }
  if(ferror(fp))
  {
    fprintf(stderr,"grep: %s: read error\n",name);
    grep_haderror=1;
  }
  return 0;
}

func grep_usage()
{
  fprintf(stderr,"usage: grep [-niv] pattern [file ...]\n");
  return 2;
}

func main(argc:int,argv:**char)
{
  var int:i = 1;
  var int:k;
  var int:nfiles;
  var int:showname;
  var *int:fp;
  grep_showline=0;
  grep_invert=0;
  grep_icase=0;
  grep_selected=0;
  grep_haderror=0;

  while((i<argc)&&(argv[i][0]=='-')&&argv[i][1])
  {
    if(grep_streq(argv[i],"--")){i++;break;}
    k=1;
    while(argv[i][k])
    {
      if(argv[i][k]=='n')grep_showline=1;
      else if(argv[i][k]=='v')grep_invert=1;
      else if(argv[i][k]=='i')grep_icase=1;
      else
      {
        fprintf(stderr,"grep: unknown option -%c\n",argv[i][k]);
        return grep_usage();
      }
      k++;
    }
    i++;
  }
  if(i>=argc)return grep_usage();
  grep_pattern=argv[i++];
  if(!grep_patvalid(grep_pattern))
  {
    fprintf(stderr,"grep: invalid or too long pattern\n");
    return 2;
  }

  nfiles=argc-i;
  showname=nfiles>1;
  if(!nfiles)grep_stream(stdin,"(standard input)",0);
  else while(i<argc)
  {
    if(grep_isdash(argv[i]))grep_stream(stdin,"(standard input)",showname);
    else
    {
      fp=fopen(argv[i],"r");
      if(!fp)
      {
        fprintf(stderr,"grep: %s: cannot open\n",argv[i]);
        grep_haderror=1;
      }
      else
      {
        grep_stream(fp,argv[i],showname);
        if(fclose(fp))
        {
          fprintf(stderr,"grep: %s: close error\n",argv[i]);
          grep_haderror=1;
        }
      }
    }
    i++;
  }
  if(grep_haderror)return 2;
  if(grep_selected)return 0;
  return 1;
}
