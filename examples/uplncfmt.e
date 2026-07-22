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
   -w rewrites each named file in place.

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
var extern stderr,stdin,stdout:*int;

#define LINECAP 4096
#define MAXLINE 158

var src:*char;             /* the whole input, slurped */
var srclen:int;
var srcpos:int;
var lineb:[LINECAP]char;   /* one input line (overlong input tolerated) */
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

/* next line of src into lineb (without the newline); 0 at end of input */
func nextline()
{
  var c:int;
  if(srcpos>=srclen)return 0;
  linelen=0;
  while(srcpos<srclen)
  {
    c=src[srcpos++];
    if(c==10)break;
    if(linelen<LINECAP-1)lineb[linelen++]=c;
  }
  lineb[linelen]=0;
  return 1;
}

/* scan the line once, updating brace depth and the open-comment state; the
   printer never looks inside strings, character literals, or comments */
func scanline()
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
    if(c=='{')depth++;
    if(c=='}'){if(depth)depth--;}
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
  var lead,ind,wascmt:int;
  depth=0;incmt=0;lno=0;srcpos=0;
  while(nextline())
  {
    lno++;
    wascmt=incmt;
    lead=leadwidth();
    scanline();
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
    if((lineb[lead]=='#')||(lineb[lead]=='%'))
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

func main(argc:int,argv:**char)
{
  var wflag,k,first:int;
  var fp,out:*int;
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
      return 2;
    }
    fclose(fp);
    out=stdout;
    if(wflag)
    {
      out=fopen(argv[k],"w");
      if(!out)
      {
        fprintf(stderr,"uplncfmt: cannot write %s\n",argv[k]);
        return 2;
      }
    }
    fmtstream(out);
    if(wflag)fclose(out);
    free(src);
    src=0;
  }
  if(warned)return 1;
  return 0;
}
