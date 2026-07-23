/* uplncfmt: the canonical UPLNC source formatter (tooling + M7 dogfood).
   Reindents every line to two spaces per brace depth, strips trailing
   whitespace, keeps preprocessor (#) and %%-directive lines at column zero,
   and leaves the interior lines of a multi-line comment verbatim (their
   alignment is the author's). Nothing inside a token is ever changed: braces
   are only counted outside strings, character literals, and comments, so the
   output is semantics-preserving by construction -- lpp1 discards exactly the
   whitespace this tool rearranges. The formatter is idempotent. When
   canonical indentation would push a line past lpp1's 158-byte limit, the
   line keeps its original indentation instead of being pushed further over;
   if it still exceeds the limit, that is reported and the exit status is 1
   (the build would otherwise break). Reads stdin or named files to stdout;
   -w atomically rewrites each named file.

     uplncfmt < in.e > out.e
     uplncfmt file.e            (formatted text on stdout)
     uplncfmt -w a.e b.he       (rewrite in place)

   Exit status: 0 clean, 1 with warnings, 2 on usage or I/O errors. */

func malloc(n:int);
func realloc(p:int,n:int);
func free(p:int);
func fopen(n:*char,m:*char):*int;
func fgetc(fp:*int);
func fputc(c:int,fp:*int);
func fclose(fp:*int);
func fflush(fp:*int);
func ferror(fp:*int);
func mkstemp(n:*char);
func fdopen(fd:int,m:*char):*int;
func close(fd:int);
func fchmod(fd:int,mode:int);
func unlink(n:*char);
func rename(old:*char,new:*char);
func realpath(n:*char,resolved:*char):*char;
func statx(dirfd:int,n:*char,flags:int,mask:int,buf:*char);
var extern stderr,stdin,stdout:*int;

#define MAXLINE 158
#define STATX_MODE 2
#define AT_FDCWD -100

var src:*char;             /* the whole input, slurped */
var srclen:int;
var srcpos:int;
var lineb:*char;           /* current line, pointing into src */
var linelen:int;
var lname:*char;           /* current input name for diagnostics */
var lno:int;
var depth:int;             /* brace depth outside strings/comments */
var incmt:int;             /* inside a multi-line comment */
var warned:int;

/* slurp an open stream into the growing src buffer; 0 on read error */
func slurp(fp:*int)
{
  var cap,c:int;
  cap=4096;
  srclen=0;
  src=malloc(cap);
  if(!src){fprintf(stderr,"uplncfmt: out of memory\n");exit(2);}
  while((c=fgetc(fp))>=0)
  {
    if(srclen+1>=cap)
    {
      cap=cap*2;
      src=realloc(src,cap);
      if(!src){fprintf(stderr,"uplncfmt: out of memory\n");exit(2);}
    }
    src[srclen++]=c;
  }
  src[srclen]=0;
  if(ferror(fp))return 0;
  return 1;
}

/* Point lineb at the next line in src and replace its newline with NUL.
   linelen, not the terminator, remains authoritative for embedded NUL bytes. */
func nextline()
{
  var c:int;
  if(srcpos>=srclen)return 0;
  lineb=src+srcpos;
  linelen=0;
  while(srcpos<srclen)
  {
    c=src[srcpos++];
    if(c==10)break;
    linelen++;
  }
  lineb[linelen]=0;
  return 1;
}

/* scan the line once, updating brace depth and the open-comment state; the
   printer never looks inside strings, character literals, or comments.
   Directives still update comment state, but their replacement-text braces
   do not belong to the surrounding source and therefore are not counted. */
func scanline(countbraces:int)
{
  var i,c:int;
  i=0;
  while(i<linelen)
  {
    c=lineb[i];
    if(incmt)
    {
      if((c=='*')&&(lineb[i+1]=='/')){incmt=0;i=i+2;continue;}
      i++;
      continue;
    }
    if((c=='/')&&(lineb[i+1]=='*')){incmt=1;i=i+2;continue;}
    if((c=='"')||(c==39))            /* 39 = a single quote */
    {
      var q:int;
      q=c;
      i++;
      while(i<linelen)
      {
        if(lineb[i]==92){i=i+2;continue;}   /* any backslash escape */
        if(lineb[i]==q){i++;break;}
        i++;
      }
      continue;
    }
    if(countbraces&&(c=='{'))depth++;
    if(countbraces&&(c=='}')){if(depth)depth--;}
    i++;
  }
  return 0;
}

func emitspaces(n:int,out:*int)
{
  while(n>0){fputc(' ',out);n--;}
  return 0;
}

/* print lineb[from..] with trailing whitespace stripped */
func emitrest(from:int,ind:int,out:*int)
{
  var end,i:int;
  end=linelen;
  while((end>from)&&((lineb[end-1]==' ')||(lineb[end-1]==9)))end--;
  if(end>from)emitspaces(ind,out);
  for(i=from;i<end;i++)fputc(lineb[i],out);
  fputc(10,out);
  if(ind+(end-from)>MAXLINE)
  {
    fprintf(stderr,"uplncfmt:%s:%d: line exceeds %d bytes after formatting\n",
      lname,lno,MAXLINE);
    warned=1;
  }
  return 0;
}

/* leading-whitespace width of the original line */
func leadwidth()
{
  var i:int;
  i=0;
  while((lineb[i]==' ')||(lineb[i]==9))i++;
  return i;
}

func fmtstream(out:*int)
{
  var lead,ind,wascmt,isdir:int;
  depth=0;incmt=0;lno=0;srcpos=0;
  while(nextline())
  {
    lno++;
    wascmt=incmt;
    lead=leadwidth();
    isdir=(!wascmt)&&(lead<linelen)&&
      ((lineb[lead]=='#')||(lineb[lead]=='%'));
    scanline(!isdir);
    if(wascmt)
    {
      /* a line that begins inside a comment keeps its own alignment */
      emitrest(0,0,out);
      continue;
    }
    if(lead>=linelen)
    {
      fputc(10,out);               /* blank (or whitespace-only) line */
      continue;
    }
    if(isdir)
    {
      emitrest(lead,0,out);        /* directives stay at column zero */
      continue;
    }
    ind=indentfor(lead);
    if(ind*2+(linelen-lead)>MAXLINE)
    {
      /* deeper indentation would break lpp1's line limit: keep the line as
         it was and say so */
      emitrest(lead,lead,out);
      continue;
    }
    emitrest(lead,ind*2,out);
  }
  return 0;
}

/* the indentation depth for the line whose code starts at lineb[from]:
   the depth BEFORE the line, minus one if the line closes or continues a
   brace it did not open ('}' first), where scanline has already applied
   every brace on the line to the global depth. */
func indentfor(from:int)
{
  var d,i,c,opens,closes,instr,q:int;
  opens=0;closes=0;instr=0;q=0;
  i=from;
  while(i<linelen)
  {
    c=lineb[i];
    if(instr)
    {
      if(c==92){i=i+2;continue;}
      if(c==q)instr=0;
      i++;
      continue;
    }
    if((c=='/')&&(lineb[i+1]=='*'))
    {
      /* skip a comment that both starts and ends on this line; one that
         runs on leaves the rest of the line to the comment rule */
      var j:int;
      j=i+2;
      while((j<linelen)&&!((lineb[j]=='*')&&(lineb[j+1]=='/')))j++;
      if(j>=linelen)break;
      i=j+2;
      continue;
    }
    if((c=='"')||(c==39)){instr=1;q=c;i++;continue;}
    if(c=='{')opens++;
    if(c=='}')closes++;
    i++;
  }
  /* depth is already AFTER this line; reconstruct the depth before it */
  d=depth-opens+closes;
  if(lineb[from]=='}')d=d-1;       /* the closing line sits one level out */
  if(d<0)d=0;
  return d;
}

/* read all of fp (then closed by the caller); write the formatted text to
   the stream out. -w readers slurp first, so rewriting the same file is safe. */
func fmtinput(fp:*int,out:*int)
{
  if(!slurp(fp))
  {
    fprintf(stderr,"uplncfmt: %s: read error\n",lname);
    free(src);src=0;
    return 0;
  }
  fmtstream(out);
  free(src);
  src=0;
  return 1;
}

func usage()
{
  fprintf(stderr,"usage: uplncfmt [-w] [file ...]\n");
  return 2;
}

/* struct statx has a fixed 256-byte cross-architecture ABI. stx_mode is the
   16-bit field at byte 28; decode it using the target's byte order. */
func filemode(n:*char)
{
  var [256]char:b;
  var int:one,mode;
  var *char:p;
  if(statx(AT_FDCWD,n,0,STATX_MODE,b))return -1;
  one=1;p=&one;
  if(p[0])mode=(b[28]&255)|((b[29]&255)<<8);
  else mode=((b[28]&255)<<8)|(b[29]&255);
  return mode&4095;
}

func tempname(n:*char):*char
{
  var *char:p;var *char:s;
  var int:i,j;
  s=".uplncfmt.XXXXXX";
  i=0;while(n[i])i++;
  p=malloc(i+17);
  if(!p)return 0;
  for(j=0;j<i;j++)p[j]=n[j];
  j=0;while(s[j]){p[i+j]=s[j];j++;}
  p[i+j]=0;
  return p;
}

/* Atomically replace n only after a complete, flushed temporary file exists.
   realpath keeps -w on a symlink operating on its target, as fopen did. */
func fmtwrite(n:*char)
{
  var *char:real;var *char:tmp;var *int:out;
  var int:fd,mode,bad;
  real=realpath(n,0);
  if(!real)
  {
    fprintf(stderr,"uplncfmt: cannot resolve %s\n",n);
    return 0;
  }
  mode=filemode(real);
  if(mode<0)
  {
    fprintf(stderr,"uplncfmt: cannot stat %s\n",n);
    free(real);
    return 0;
  }
  tmp=tempname(real);
  if(!tmp)
  {
    fprintf(stderr,"uplncfmt: out of memory\n");
    free(real);
    return 0;
  }
  fd=mkstemp(tmp);
  if(fd<0)
  {
    fprintf(stderr,"uplncfmt: cannot create temporary file for %s\n",n);
    free(tmp);free(real);
    return 0;
  }
  if(fchmod(fd,mode))
  {
    fprintf(stderr,"uplncfmt: cannot preserve permissions on %s\n",n);
    close(fd);unlink(tmp);free(tmp);free(real);
    return 0;
  }
  out=fdopen(fd,"w");
  if(!out)
  {
    fprintf(stderr,"uplncfmt: cannot open temporary stream for %s\n",n);
    close(fd);unlink(tmp);free(tmp);free(real);
    return 0;
  }
  fmtstream(out);
  bad=0;
  if(fflush(out))bad=1;
  if(ferror(out))bad=1;
  if(fclose(out))bad=1;
  if(bad)
  {
    fprintf(stderr,"uplncfmt: write error on %s\n",n);
    unlink(tmp);free(tmp);free(real);
    return 0;
  }
  if(rename(tmp,real))
  {
    fprintf(stderr,"uplncfmt: cannot replace %s\n",n);
    unlink(tmp);free(tmp);free(real);
    return 0;
  }
  free(tmp);free(real);
  return 1;
}

func flushstdout()
{
  if(fflush(stdout)||ferror(stdout))
  {
    fprintf(stderr,"uplncfmt: write error\n");
    return 0;
  }
  return 1;
}

func main(argc:int,argv:**char)
{
  var wflag,k,first:int;
  var fp:*int;
  wflag=0;first=1;warned=0;
  if((argc>1)&&(argv[1][0]=='-')&&(argv[1][1]=='w')&&(!argv[1][2]))
  {wflag=1;first=2;}
  else if((argc>1)&&(argv[1][0]=='-')&&argv[1][1])
  return usage();
  if(wflag&&(first>=argc))return usage();
  if(first>=argc)
  {
    lname="<stdin>";
    if(!fmtinput(stdin,stdout))return 2;
    if(!flushstdout())return 2;
    if(warned)return 1;
    return 0;
  }
  for(k=first;k<argc;k++)
  {
    fp=fopen(argv[k],"r");
    if(!fp)
    {
      fprintf(stderr,"uplncfmt: cannot open %s\n",argv[k]);
      return 2;
    }
    lname=argv[k];
    if(!slurp(fp))
    {
      fprintf(stderr,"uplncfmt: %s: read error\n",lname);
      fclose(fp);
      free(src);src=0;
      return 2;
    }
    if(fclose(fp))
    {
      fprintf(stderr,"uplncfmt: %s: close error\n",lname);
      free(src);src=0;
      return 2;
    }
    if(wflag){if(!fmtwrite(argv[k])){free(src);src=0;return 2;}}
    else fmtstream(stdout);
    free(src);
    src=0;
  }
  if(!wflag&&!flushstdout())return 2;
  if(warned)return 1;
  return 0;
}
