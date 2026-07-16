/* ---------------------------------------------------------------------------
   UPLNC standard library v0: formatted output.                     lib/fmt.e
   Grown from the M7 dogfooding needs. Programs include "fmt.he" (using a
   path relative to their source) and link this implementation once.

   putf(fmt, ...) -- a mini printf:
     %d  signed word decimal          %u  unsigned word decimal
     %x  unsigned word hex            %c  one character
     %s  NUL-terminated string        %f  fixed-point double
     %%  a literal percent
   An optional width pads with spaces, or with zeros after a leading 0:
     %6d, %04x. A negative %d zero-pads after the sign (-0042) and
     space-pads before it (  -42), like printf. %s ignores the width (v0).
   %f takes an optional precision: %.2f, %8.3f, %010.3f. The default is six
   fraction digits; %.0f prints no point, and larger values are capped at 18.
   Rounding is half-up at the last printed digit (printf rounds to
   nearest-even; this differs on exact halves). Signed zero keeps its sign;
   nan and inf print as text.

   v0 limits, by design:
     - a %f argument's integer part must fit the target's signed word
       (2^63 on the 64-bit targets, 2^31 on i386)
     - the other arguments are word-size values (the compiler rejects
       64-bit integer varargs on i386, where they would occupy two slots;
       a %f double also occupies two i386 slots, which putf accounts for)
     - a call passes at most nargreg args on the register targets
       (fmt + 5 varargs on x86_64/arm64, fmt + 7 on riscv64/mips64);
       on those targets a double still uses one argument slot
   Only libc putchar is used underneath.
   ------------------------------------------------------------------------- */

#include "fmt.he"

func putstr(s:*char)
{
  while(*s)putchar(*s++);
  return 0;
}

/* unsigned decimal, padded to width w with pad character pc */
func putupad(u:unsigned,w:int,pc:int)
{
  var [24]char:buf;
  var i:int = 0;
  if(!u)buf[i++]='0';
  while(u)
  {
    buf[i++]='0'+u%10;
    u=u/10;
  }
  while(w>i){putchar(pc);w--;}
  while(i)putchar(buf[--i]);
  return 0;
}

/* unsigned hex, padded */
func putxpad(u:unsigned,w:int,pc:int)
{
  var [20]char:buf;
  var i:int = 0;
  var d:int;
  if(!u)buf[i++]='0';
  while(u)
  {
    d=u%16;
    if(d<10)buf[i++]='0'+d;
    else buf[i++]='a'+d-10;
    u=u/16;
  }
  while(w>i){putchar(pc);w--;}
  while(i)putchar(buf[--i]);
  return 0;
}

/* signed decimal, padded; zero-padding goes after the sign, like printf */
func putdpad(n:int,w:int,pc:int)
{
  var u:unsigned;
  var d:unsigned;
  var k:int = 0;
  if(n<0)u=0-n;   /* unsigned negation: exact even for the minimum int */
  else u=n;
  d=u;
  while(d){k++;d=d/10;}
  if(!k)k=1;
  if(n<0)k++;
  if(pc==' ')while(w>k){putchar(' ');w--;}
  if(n<0)putchar('-');
  if(pc=='0')while(w>k){putchar('0');w--;}
  return putupad(u,0,' ');
}

func putd(n:int){return putdpad(n,0,' ');}
func putu(u:unsigned){return putupad(u,0,' ');}
func putx(u:unsigned){return putxpad(u,0,' ');}

/* fixed-point double with prec fraction digits; pads to width w with pc like
   %d (spaces before the sign, zeros after it). Rounds half-up by adding
   0.5*10^-prec first, so 0.9999995 correctly carries into 1.000000. The
   integer part must fit the target's signed word. */
func putfpad(x:double,w:int,pc:int,prec:int)
{
  var neg:int = 0;
  var ip:unsigned;
  var frac:double;
  var half:double;
  var d:unsigned;
  var k:int;
  var n:int;
  /* putf already bounds parsed precision, but putfpad is public too. Keep its
     loop and width arithmetic bounded for direct callers. */
  if(prec<0)prec=0;
  if(prec>18)prec=18;
  if(x!=x)                       /* only NaN compares unequal to itself */
  {
    while(w>3){putchar(' ');w--;}
    return putstr("nan");
  }
  /* IEEE comparisons treat -0.0 as equal to +0.0. Its reciprocal retains the
     sign as -inf, which lets fixed formatting preserve the leading minus. */
  if((x<0.0)||((x==0.0)&&((1.0/x)<0.0))){neg=1;x=0.0-x;}
  if(x>1.7e308)
  {
    n=3+neg;
    while(w>n){putchar(' ');w--;}
    if(neg)putchar('-');
    return putstr("inf");
  }
  half=0.5;
  for(k=0;k<prec;k=k+1)half=half/10.0;
  x=x+half;
  ip=x;                          /* truncate toward zero */
  frac=x-ip;
  n=0;d=ip;                      /* printed length, for the width padding */
  while(d){n++;d=d/10;}
  if(!n)n=1;
  if(neg)n++;
  if(prec)n=n+1+prec;
  if(pc==' ')while(w>n){putchar(' ');w--;}
  if(neg)putchar('-');
  if(pc=='0')while(w>n){putchar('0');w--;}
  putupad(ip,0,' ');
  if(prec)
  {
    putchar('.');
    for(k=0;k<prec;k=k+1)
    {
      frac=frac*10.0;
      d=frac;
      putchar('0'+d);
      frac=frac-d;
    }
  }
  return 0;
}

/* the mini printf (see the header comment for the format language) */
func putf(fmt:*char,...)
{
  var p:*int;
  var dp:*double;
  var i:int = 0;
  var w:int;
  var pc:int;
  var c:int;
  var prec:int;
  p=vastart();
  while(*fmt)
  {
    c=*fmt++;
    if(c!='%')
    {
      putchar(c);
      continue;
    }
    pc=' ';
    w=0;
    prec=6;
    if(*fmt=='0'){pc='0';fmt++;}
    while((*fmt>='0')&&(*fmt<='9'))
    {
      w=w*10+(*fmt-'0');
      fmt++;
    }
    if(*fmt=='.')
    {
      fmt++;
      prec=0;
      while((*fmt>='0')&&(*fmt<='9'))
      {
        /* Saturate while parsing. Clamping only after the loop lets a long
           field overflow negative and poison putfpad's width arithmetic. */
        if(prec<18)
        {
          prec=prec*10+(*fmt-'0');
          if(prec>18)prec=18;
        }
        fmt++;
      }
    }
    c=*fmt;
    if(c)fmt++;
    if(c=='d')putdpad(p[i++],w,pc);
    else if(c=='u')putupad(p[i++],w,pc);
    else if(c=='x')putxpad(p[i++],w,pc);
    else if(c=='c')putchar(p[i++]);
    else if(c=='s')putstr(p[i++]);
    else if(c=='f')
    {
      /* the double's raw bits travel in integer varargs slots: one word slot
         on the 64-bit targets, two 4-byte slots on i386 */
      dp=p+i;
      i=i+8/sizeof(int);
      putfpad(*dp,w,pc,prec);
    }
    else if(c=='%')putchar('%');
    else putchar('%');   /* unknown or truncated spec: emit the % and move on */
  }
  return 0;
}
