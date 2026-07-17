/* ---------------------------------------------------------------------------
   UPLNC standard library v0: formatted output.                     lib/fmt.e
   Grown from the M7 dogfooding needs. Programs include "fmt.he" (using a
   path relative to their source) and link this implementation once.

   putf(fmt, ...) -- a mini printf:
     %d  signed word decimal          %u  unsigned word decimal
     %x  unsigned word hex            %c  one character
     %s  NUL-terminated string        %f  fixed-point double
     %e  scientific double            %g  shortest-form double
     %%  a literal percent
   An optional width pads with spaces, or with zeros after a leading 0:
     %6d, %04x. A negative %d zero-pads after the sign (-0042) and
     space-pads before it (  -42), like printf. %s ignores the width (v0).
   %f, %e and %g take an optional precision: %.2f, %8.3e, %010.3g. For %f/%e
   it is the fraction-digit count (default six; .0 prints no point); for %g
   it is the significant-digit count (default six, 0 counts as 1); larger
   values are capped at 18. %e prints at least two exponent digits; %g picks
   the %e form when the exponent is below -4 or at least the precision, and
   strips trailing fraction zeros like printf. Rounding is half-up at the
   last printed digit (printf rounds to nearest-even; this differs on exact
   halves). Signed zero keeps its sign; nan and inf print as text.

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

/* Exact binary64-to-decimal conversion for %e/%g. The decoded value is
     mantissa * 2^k.
   For k < 0 this is mantissa * 5^-k * 10^k; for k >= 0 it is an integer.
   Base 10^8 keeps multiply-by-5 plus carry within unsigned 32-bit range on
   i386. Binary64 needs at most 96 limbs / 767 decimal digits, so the fixed
   bounds below cover every finite value without allocation. */
func fbigmul(a:*unsigned,n:int,m:unsigned)
{
  var i:int;
  var v,carry:unsigned;
  carry=0;
  for(i=0;i<n;i=i+1)
  {
    v=a[i]*m+carry;
    a[i]=v%100000000;
    carry=v/100000000;
  }
  if(carry)a[n++]=carry;
  return n;
}

/* Divide a little-endian base-10^8 integer by ten and return the remainder. */
func fbigdiv10(a:*unsigned,pn:*int)
{
  var i,n:int;
  var v,carry:unsigned;
  n=*pn;
  carry=0;
  i=n;
  while(i)
  {
    i--;
    v=carry*100000000+a[i];
    a[i]=v/10;
    carry=v%10;
  }
  while((n>1)&&(!a[n-1]))n--;
  *pn=n;
  return carry;
}

/* Consume a positive big integer into a most-significant-first digit string. */
func fbigtext(a:*unsigned,n:int,out:*char)
{
  var i,j:int;
  var c:char;
  i=0;
  while((n>1)||a[0])out[i++]='0'+fbigdiv10(a,&n);
  for(j=0;j<i/2;j=j+1)
  {
    c=out[j];out[j]=out[i-j-1];out[i-j-1]=c;
  }
  out[i]=0;
  return i;
}

/* Produce the exact finite positive value's decimal integer and exponent.
   If out has len digits, x = out * 10^(exp-len+1). */
func fexact(x:double,out:*char,pexp:*int)
{
  var limbs:[100]unsigned;
  var bits,mant,hidden:unsigned long long;
  var *unsigned long long:pbits;
  var ef,k,q,n,i,len:int;
  pbits=&x;
  bits=*pbits;
  hidden=1;hidden=hidden<<52;
  ef=(bits>>52)&2047;
  mant=bits&(hidden-1);
  if(ef)
  {
    mant=mant|hidden;
    k=ef-1075;
  }
  else k=0-1074;
  n=0;
  while(mant)
  {
    limbs[n++]=mant%100000000;
    mant=mant/100000000;
  }
  q=0;
  if(k>=0)for(i=0;i<k;i=i+1)n=fbigmul(limbs,n,2);
  else
  {
    q=0-k;
    for(i=0;i<q;i=i+1)n=fbigmul(limbs,n,5);
  }
  len=fbigtext(limbs,n,out);
  *pexp=len-q-1;
  return len;
}

/* Round a finite nonnegative binary64 value to p significant decimal digits.
   The source digits are exact, so testing the first discarded digit implements
   the documented half-up rule without a floating-point normalization error. */
func fround(x:double,p:int,out:*char,pexp:*int)
{
  var exact:[800]char;
  var len,e,i:int;
  if(x==0.0)
  {
    for(i=0;i<p;i=i+1)out[i]='0';
    out[p]=0;*pexp=0;return 0;
  }
  len=fexact(x,exact,&e);
  for(i=0;i<p;i=i+1)
  if(i<len)out[i]=exact[i];else out[i]='0';
  if((p<len)&&(exact[p]>='5'))
  {
    i=p;
    while(i&&(out[i-1]=='9')){out[i-1]='0';i--;}
    if(i)out[i-1]++;
    else{out[0]='1';e++;}
  }
  out[p]=0;
  *pexp=e;
  return 0;
}

/* scientific notation with prec fraction digits: [-]d.dddddde+XX, at least
   two exponent digits like printf. Rounds half-up; a mantissa that rounds
   past 9.999... renormalizes to 1.000...e+(X+1) instead of printing 10.x. */
func putepad(x:double,w:int,pc:int,prec:int)
{
  var sig:[20]char;
  var neg:int = 0;
  var e,ee,n,k:int;
  if(prec<0)prec=0;
  if(prec>18)prec=18;
  if(x!=x)
  {
    while(w>3){putchar(' ');w--;}
    return putstr("nan");
  }
  if((x<0.0)||((x==0.0)&&((1.0/x)<0.0))){neg=1;x=0.0-x;}
  if((x!=0.0)&&(x==x/2.0))
  {
    n=3+neg;
    while(w>n){putchar(' ');w--;}
    if(neg)putchar('-');
    return putstr("inf");
  }
  fround(x,prec+1,sig,&e);
  ee=e;if(ee<0)ee=0-ee;
  k=1;n=ee;while(n>9){k++;n=n/10;}     /* exponent digits, printed >= 2 */
  if(k<2)k=2;
  n=1+neg+2+k;                         /* d, sign, 'e' and exp sign, digits */
  if(prec)n=n+1+prec;
  if(pc==' ')while(w>n){putchar(' ');w--;}
  if(neg)putchar('-');
  if(pc=='0')while(w>n){putchar('0');w--;}
  putchar(sig[0]);
  if(prec)
  {
    putchar('.');
    for(k=1;k<=prec;k=k+1)putchar(sig[k]);
  }
  putchar('e');
  if(e<0)putchar('-');else putchar('+');
  if(ee<10)putchar('0');
  putupad(ee,0,' ');
  return 0;
}

/* %g: prec SIGNIFICANT digits (default 6, 0 counts as 1). Uses the %e form
   when the exponent is < -4 or >= prec, the %f form otherwise, and strips
   trailing fraction zeros (and a bare point) like printf. */
func putgpad(x:double,w:int,pc:int,prec:int)
{
  var buf:[48]char;
  var sig:[20]char;
  var neg:int = 0;
  var e,ee,i,k,pt:int;
  if(prec<1)prec=1;
  if(prec>18)prec=18;
  if(x!=x)
  {
    while(w>3){putchar(' ');w--;}
    return putstr("nan");
  }
  if((x<0.0)||((x==0.0)&&((1.0/x)<0.0))){neg=1;x=0.0-x;}
  if((x!=0.0)&&(x==x/2.0))
  {
    k=3+neg;
    while(w>k){putchar(' ');w--;}
    if(neg)putchar('-');
    return putstr("inf");
  }
  fround(x,prec,sig,&e);
  i=0;
  if((e<(0-4))||(e>=prec))
  {
    /* scientific form: d[.ddd]e+XX with the zeros stripped */
    k=prec;
    while((k>1)&&(sig[k-1]=='0'))k--;
    buf[i++]=sig[0];
    if(k>1)
    {
      buf[i++]='.';
      for(pt=1;pt<k;pt=pt+1)buf[i++]=sig[pt];
    }
    buf[i++]='e';
    if(e<0)buf[i++]='-';else buf[i++]='+';
    ee=e;if(ee<0)ee=0-ee;
    if(ee>99){buf[i++]='0'+ee/100;ee=ee%100;buf[i++]='0'+ee/10;buf[i++]='0'+ee%10;}
    else{buf[i++]='0'+ee/10;buf[i++]='0'+ee%10;}
  }
  else
  {
    /* fixed form: the point sits after position e; strip fraction zeros */
    k=prec;
    while((k>e+1)&&(sig[k-1]=='0'))k--;   /* never strip integer digits */
    if(e>=0)
    {
      for(pt=0;pt<=e;pt=pt+1)buf[i++]=sig[pt];
      if(k>e+1)
      {
        buf[i++]='.';
        for(pt=e+1;pt<k;pt=pt+1)buf[i++]=sig[pt];
      }
    }
    else
    {
      buf[i++]='0';
      buf[i++]='.';
      for(pt=0;pt<(0-e)-1;pt=pt+1)buf[i++]='0';
      for(pt=0;pt<k;pt=pt+1)buf[i++]=sig[pt];
    }
  }
  buf[i]=0;
  k=i+neg;
  if(pc==' ')while(w>k){putchar(' ');w--;}
  if(neg)putchar('-');
  if(pc=='0')while(w>k){putchar('0');w--;}
  return putstr(buf);
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
    else if((c=='f')||(c=='e')||(c=='g'))
    {
      /* the double's raw bits travel in integer varargs slots: one word slot
         on the 64-bit targets, two 4-byte slots on i386 */
      dp=p+i;
      i=i+8/sizeof(int);
      if(c=='f')putfpad(*dp,w,pc,prec);
      else if(c=='e')putepad(*dp,w,pc,prec);
      else putgpad(*dp,w,pc,prec);
    }
    else if(c=='%')putchar('%');
    else putchar('%');   /* unknown or truncated spec: emit the % and move on */
  }
  return 0;
}
