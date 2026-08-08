/* buftest.e: the text buffer's cross-target proof. Exercises every editing
   primitive plus a save/load round trip through a real file, and checks the
   resulting text byte for byte. Pure logic and file I/O -- no terminal -- so
   it runs on every backend.

   Usage: buftest <scratch-file>   (exit 42 on success, else the failing step)
   Build: perl src/langdrv.pl -march=ARCH -o buftest ide/buftest.e ide/buf.e */

#include "buf.he"

var b:sbuf;

func streq0(a:*char,c:*char)
{
  var i:int;
  i=0;
  while(a[i]&&c[i])
  {
    if(a[i]!=c[i])return 0;
    i++;
  }
  return a[i]==c[i];
}

/* line i of the buffer equals want? */
func lineis(i:int,want:*char)
{
  var p:*char;
  p=b.line(i);
  if(!streq0(p,want))return 0;
  if(b.llen(i)!=strlen1(want))return 0;
  return 1;
}

func strlen1(s:*char)
{
  var i:int;
  i=0;
  while(s[i])i++;
  return i;
}

/* type the bytes of s into line i starting at column col */
func typein(i:int,col:int,s:*char)
{
  var j:int;
  j=0;
  while(s[j])
  {
    b.insch(i,col+j,s[j]);
    j++;
  }
  return 0;
}

func main(argc:int,argv:**char)
{
  var path:*char;
  var i:int;      /* plain braces are not a name scope in v0, so one `i` */
  if(argc<2)return 1;
  path=argv[1];
  b.init();

  /* a fresh buffer is one empty line */
  if(b.n!=1)return 2;
  if(!lineis(0,""))return 3;

  /* insert characters */
  typein(0,0,"hello");
  if(!lineis(0,"hello"))return 4;
  b.insch(0,0,'>');
  if(!lineis(0,">hello"))return 5;

  /* out-of-range edits are no-ops, not corruption */
  b.insch(0,99,'x');
  b.insch(9,0,'x');
  b.delch(0,99);
  b.delch(9,0);
  if(!lineis(0,">hello"))return 6;
  if(b.n!=1)return 7;

  /* delete characters */
  b.delch(0,0);
  if(!lineis(0,"hello"))return 8;

  /* split (Enter) in the middle, then at both edges */
  b.split(0,2);
  if(b.n!=2)return 9;
  if(!lineis(0,"he"))return 10;
  if(!lineis(1,"llo"))return 11;
  b.split(1,0);
  if((b.n!=3)||!lineis(1,"")||!lineis(2,"llo"))return 12;
  b.join(1);
  if((b.n!=2)||!lineis(1,"llo"))return 13;

  /* join (Backspace at column 0) */
  b.join(0);
  if(b.n!=1)return 14;
  if(!lineis(0,"hello"))return 15;

  /* insert and delete whole lines */
  b.insline(0);
  typein(0,0,"first");
  b.insline(2);
  typein(2,0,"third");
  if(b.n!=3)return 16;
  if(!lineis(0,"first")||!lineis(1,"hello")||!lineis(2,"third"))return 17;
  b.delline(1);
  if((b.n!=2)||!lineis(0,"first")||!lineis(1,"third"))return 18;

  /* the last line is emptied, never removed */
  b.delline(0);
  b.delline(0);
  if((b.n!=1)||!lineis(0,""))return 19;

  /* a line that outgrows its initial capacity many times over */
  typein(0,0,"0123456789");
  for(i=0;i<40;i++)typein(0,b.llen(0),"0123456789");
  if(b.llen(0)!=410)return 20;
  if(b.line(0)[409]!='9')return 21;

  /* enough lines to outgrow the initial slot count */
  for(i=0;i<200;i++)b.insline(b.n);
  if(b.n!=201)return 22;

  /* save and reload: the text must survive exactly */
  b.done();
  b.init();
  typein(0,0,"alpha");
  b.insline(1);
  typein(1,0,"beta");
  b.insline(2);          /* an empty line in the middle must survive */
  b.insline(3);
  typein(3,0,"gamma");
  if(b.dirty!=1)return 23;
  if(!b.save(path))return 24;
  if(b.dirty!=0)return 25;

  b.done();
  b.init();
  typein(0,0,"scratch");
  if(!b.load(path))return 26;
  if(b.dirty!=0)return 27;
  if(b.n!=4)return 28;
  if(!lineis(0,"alpha"))return 29;
  if(!lineis(1,"beta"))return 30;
  if(!lineis(2,""))return 31;
  if(!lineis(3,"gamma"))return 32;

  /* loading a missing file fails and leaves the buffer usable */
  if(b.load("/nonexistent/uplnc/buftest"))return 33;
  if(!lineis(0,"alpha"))return 34;

  b.done();
  return 42;
}
