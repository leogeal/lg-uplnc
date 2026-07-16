/* calc: a tiny expression interpreter -- the M7 dogfood for structs-as-trees.
   Reads one expression (or assignment) per line from stdin and prints its
   value. A fitting program for a compiler project: it is langc in miniature
   (scanner, recursive-descent parser, heap AST, evaluator), and it exercises
   the newest ground: a tree of heap-allocated struct nodes walked by METHODS
   (including the double-returning eval(), typed-method parity), mutually
   recursive parse functions with declared pointer returns, and %f
   (including IEEE inf/nan from division by zero).

     line  := VAR '=' expr | expr          VAR is one letter a-z
     expr  := term  (('+'|'-') term)*
     term  := unary (('*'|'/') unary)*
     unary := '-' unary | primary
     primary := NUMBER | VAR | '(' expr ')'

   Numbers are decimal with an optional fraction (no exponent). Values print
   as integers when exact and within every target's word (under 2^31), in
   fixed %.6f up to that bound, and in e-notation above it, so the output is
   byte-identical on all five backends. Using a variable before assigning it
   is an error. With -n each result is followed by the node count of its
   syntax tree (the method-dispatch dogfood). Errors go to stderr with a
   1-based column; overlong lines, embedded NULs, and input read failures are
   diagnosed. The exit status is 1 if any input failed, else 0. */
#include "../lib/fmt.he"

func malloc(n:int);
func free(p:int);
func ferror(fp:*int);
var extern stderr,stdin,stdout:*int;

struct node{
  int op;      /* 'n' number, 'v' variable, '~' negate, or '+','-','*','/' */
  double val;
  int vn;      /* variable index for 'v' */
  *node l;
  *node r;
  func done;         /* free the children below this node */
  func count;        /* nodes in this subtree */
  func eval:double;  /* the subtree's value -- a typed method return */
};
method node.done()
{
  if(l){l->done();free(l);l=0;}
  if(r){r->done();free(r);r=0;}
  return 0;
}
method node.count()
{
  var k:int = 1;
  if(l)k=k+l->count();
  if(r)k=k+r->count();
  return k;
}

#define LINEMAX 256
var line:[LINEMAX]char;
var pos:int;
var perr:int;              /* first error column (1-based), 0 = none */
var everr:int;             /* unset-variable name during eval, 0 = none */
var vars:[26]double;
var vset:[26]int;
var lineno:int;
var nflag:int;

func pexpr():*node;        /* the grammar is mutually recursive */

func mknode(op:int):*node
{
  var n:*node;
  n=malloc(sizeof(node));
  if(!n){fprintf(stderr,"calc: out of memory\n");exit(3);}
  n->op=op;n->val=0.0;n->vn=0;n->l=0;n->r=0;
  return n;
}

func skipws()
{
  while((line[pos]==' ')||(line[pos]==9))pos++;
  return 0;
}

func fail()
{
  if(!perr)perr=pos+1;
  return 0;
}

func pprimary():*node
{
  var n:*node;
  var d:double;
  var scale:double;
  var c:int;
  skipws();
  c=line[pos];
  if(c=='(')
  {
    pos++;
    n=pexpr();
    skipws();
    if(line[pos]==')')pos++;
    else fail();
    return n;
  }
  if((c>='a')&&(c<='z'))
  {
    pos++;
    n=mknode('v');
    n->vn=c-'a';
    return n;
  }
  if((c>='0')&&(c<='9'))
  {
    d=0.0;
    while((line[pos]>='0')&&(line[pos]<='9'))
    {
      d=d*10.0+(line[pos]-'0');
      pos++;
    }
    if(line[pos]=='.')
    {
      pos++;
      if((line[pos]<'0')||(line[pos]>'9'))fail();
      scale=0.1;
      while((line[pos]>='0')&&(line[pos]<='9'))
      {
        d=d+(line[pos]-'0')*scale;
        scale=scale/10.0;
        pos++;
      }
    }
    n=mknode('n');
    n->val=d;
    return n;
  }
  fail();
  return mknode('n');   /* a harmless 0 keeps the tree shape valid */
}

func punary():*node
{
  var n:*node;
  skipws();
  if(line[pos]=='-')
  {
    pos++;
    n=mknode('~');
    n->l=punary();
    return n;
  }
  return pprimary();
}

func pterm():*node
{
  var n,rhs:*node;
  var c:int;
  n=punary();
  while(1)
  {
    skipws();
    c=line[pos];
    if((c!='*')&&(c!='/'))return n;
    pos++;
    rhs=n;
    n=mknode(c);
    n->l=rhs;
    n->r=punary();
  }
}

func pexpr():*node
{
  var n,rhs:*node;
  var c:int;
  n=pterm();
  while(1)
  {
    skipws();
    c=line[pos];
    if((c!='+')&&(c!='-'))return n;
    pos++;
    rhs=n;
    n=mknode(c);
    n->l=rhs;
    n->r=pterm();
  }
}

method node.eval()
{
  var a,b:double;
  if(op=='n')return val;
  if(op=='v')
  {
    if(!vset[vn]){if(!everr)everr='a'+vn;return 0.0;}
    return vars[vn];
  }
  if(op=='~')return 0.0-l->eval();
  a=l->eval();
  b=r->eval();
  if(op=='+')return a+b;
  if(op=='-')return a-b;
  if(op=='*')return a*b;
  return a/b;    /* '/': division by zero is IEEE inf/nan, printed as such */
}

/* print a value so every backend agrees byte-for-byte: exact integers below
   2^31 (the smallest target word) print as integers, other magnitudes below
   that bound in %.6f, and anything bigger in e-notation -- %f's integer part
   may not exceed the target word, which i386 would break first. */
func putval(x:double)
{
  var k:int;
  var e:int;
  var neg:int = 0;
  if(x!=x){putf("%f",x);return 0;}             /* nan */
  if(x<0.0){neg=1;x=0.0-x;}
  /* For nonzero infinity, halving leaves the value unchanged. A magnitude
     cutoff would misclassify the finite range between 1.7e308 and DBL_MAX. */
  if((x!=0.0)&&(x==x/2.0))                      /* inf */
  {
    if(neg)putstr("-");
    putf("%f",x*2.0);
    return 0;
  }
  if(x<=2147483647.0)
  {
    k=x;
    if(k==x)
    {
      if(neg&&k)putstr("-");
      putf("%d",k);
      return 0;
    }
    if(neg)putstr("-");
    putf("%f",x);
    return 0;
  }
  e=0;
  while(x>=10.0){x=x/10.0;e++;}
  if(neg)putstr("-");
  putf("%.6fe+%d",x,e);
  return 0;
}

func readline()
{
  var c,i,over,nul:int;
  i=0;over=0;nul=0;
  while(1)
  {
    c=getchar();
    if(c<0)
    {
      if(ferror(stdin))
      {
        fprintf(stderr,"calc: input read error\n");
        line[0]=0;
        return 0-2;
      }
      if((!i)&&(!nul))return 0;
      break;
    }
    if(c==10)break;
    if(!c){nul=1;continue;}
    if(i<LINEMAX-1)line[i++]=c;
    else over=1;
  }
  line[i]=0;
  if(nul)
  {
    fprintf(stderr,"calc:%d: embedded NUL is not supported\n",lineno);
    line[0]=0;
    return 0-1;
  }
  if(over)
  {
    fprintf(stderr,"calc:%d: line too long\n",lineno);
    line[0]=0;
    return 0-1;
  }
  return 1;
}

func blankline()
{
  var i:int;
  for(i=0;line[i];i++)if((line[i]!=' ')&&(line[i]!=9))return 0;
  return 1;
}

func doline()
{
  var n:*node;
  var x:double;
  var tgt,i:int;
  pos=0;perr=0;everr=0;
  tgt=0-1;
  /* assignment lookahead: a single letter, then '=' */
  skipws();
  if((line[pos]>='a')&&(line[pos]<='z'))
  {
    i=pos+1;
    while((line[i]==' ')||(line[i]==9))i++;
    if(line[i]=='=')
    {
      tgt=line[pos]-'a';
      pos=i+1;
    }
  }
  n=pexpr();
  skipws();
  if(line[pos])fail();       /* trailing garbage */
  if(perr)
  {
    fprintf(stderr,"calc:%d: parse error at column %d\n",lineno,perr);
    n->done();free(n);
    return 1;
  }
  x=n->eval();
  if(everr)
  {
    fprintf(stderr,"calc:%d: unset variable '%c'\n",lineno,everr);
    n->done();free(n);
    return 1;
  }
  if(tgt>=0){vars[tgt]=x;vset[tgt]=1;}
  putval(x);
  if(nflag)putf("  (%d nodes)",n->count());
  putstr("\n");
  n->done();free(n);
  return 0;
}

func main(argc:int,argv:**char)
{
  var bad,k:int;
  nflag=0;
  for(k=1;k<argc;k++)
  {
    if((argv[k][0]=='-')&&(argv[k][1]=='n')&&(!argv[k][2]))nflag=1;
    else
    {
      fprintf(stderr,"usage: calc [-n] < expressions\n");
      return 2;
    }
  }
  bad=0;
  lineno=0;
  while(1)
  {
    lineno++;
    k=readline();
    if(!k)break;
    if(k<0){bad=1;if(k==(0-2))break;continue;}
    if(blankline())continue;
    if(doline())bad=1;
  }
  return bad;
}
