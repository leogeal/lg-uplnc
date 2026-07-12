/* ---------------------------------------------------------------------------
   UPLNC standard library v0: formatted output.                     lib/fmt.e
   Grown from the M7 dogfooding needs. Programs include "fmt.he" (using a
   path relative to their source) and link this implementation once.

   putf(fmt, ...) -- a mini printf:
     %d  signed word decimal          %u  unsigned word decimal
     %x  unsigned word hex            %c  one character
     %s  NUL-terminated string        %%  a literal percent
   An optional width pads with spaces, or with zeros after a leading 0:
     %6d, %04x. A negative %d zero-pads after the sign (-0042) and
     space-pads before it (  -42), like printf. %s ignores the width (v0).

   v0 limits, by design:
     - no %f: FP varargs are rejected at compile time on x86_64/arm64
     - arguments are word-size values (the compiler rejects 64-bit varargs on
       i386, where they would occupy two slots)
     - a call passes at most nargreg args on the register targets
       (fmt + 5 varargs on x86_64/arm64, fmt + 7 on riscv64/mips64)
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

/* the mini printf (see the header comment for the format language) */
func putf(fmt:*char,...)
{
  var p:*int;
  var i:int = 0;
  var w:int;
  var pc:int;
  var c:int;
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
    if(*fmt=='0'){pc='0';fmt++;}
    while((*fmt>='0')&&(*fmt<='9'))
    {
      w=w*10+(*fmt-'0');
      fmt++;
    }
    c=*fmt;
    if(c)fmt++;
    if(c=='d')putdpad(p[i++],w,pc);
    else if(c=='u')putupad(p[i++],w,pc);
    else if(c=='x')putxpad(p[i++],w,pc);
    else if(c=='c')putchar(p[i++]);
    else if(c=='s')putstr(p[i++]);
    else if(c=='%')putchar('%');
    else putchar('%');   /* unknown or truncated spec: emit the % and move on */
  }
  return 0;
}
