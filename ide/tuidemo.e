/* tuidemo.e: the platform-slice demonstrator. Draws a Turbo-blue frame,
   reports the terminal size, and echoes every decoded key by name at a fixed
   cell -- which is exactly what the PTY tests pin: the byte transcript at
   80x24, the exact termios/screen restore on quit, resize redelivery, and
   the decoder's name for each fed escape sequence. q or F10 quits.

   Build: perl src/langdrv.pl -o tuidemo ide/tuidemo.e ide/tui.e ide/tshim.c */

#include "tui.he"

func tuiinit();
func tuidone();
func tuiresize();
func tuirows();
func tuicols();
func tuiput(x:int,y:int,c:int,attr:int);
func tuitext(x:int,y:int,s:*char,attr:int);
func tuifill(x:int,y:int,w:int,h:int,c:int,attr:int);
func tuibox(x:int,y:int,w:int,h:int,attr:int);
func tuiflush();
func tuikey(ms:int);

var const [23]*char:knames = {"UP","DOWN","RIGHT","LEFT","HOME","END",
  "PGUP","PGDN","INS","DEL","F1","F2","F3","F4","F5","F6","F7","F8","F9",
  "F10","F11","F12","RESIZE"};

var frame,text,hot:int;

func numtext(x:int,y:int,n:int,attr:int)
{
  if(n>=10)x=numtext(x,y,n/10,attr);
  tuiput(x,y,'0'+n%10,attr);
  return x+1;
}

func drawall()
{
  var w,h,x:int;
  w=tuicols();
  h=tuirows();
  tuifill(0,0,w,h,' ',text);
  tuibox(0,0,w,h,frame);
  tuitext(3,0," UPLNC TUI DEMO ",hot);
  tuitext(2,2,"size ",text);
  x=numtext(7,2,w,text);
  tuiput(x,2,'x',text);
  numtext(x+1,2,h,text);
  tuitext(2,3,"keys echo below; q or F10 quits",text);
  tuitext(2,5,"key -",text);
  tuiflush();
  return 0;
}

func showkey(k:int)
{
  var w:int;
  w=tuicols();
  /* clear and flush first, so the name that follows re-emits every cell --
     the diff renderer would otherwise skip bytes shared with the previous
     name, and the PTY transcript greps want each name contiguous */
  tuifill(6,5,w-8,1,' ',text);
  tuiflush();
  if(k>=256)tuitext(6,5,knames[k-256],hot);
  else if((k>32)&&(k<127))
  {
    tuiput(6,5,39,text);
    tuiput(7,5,k,hot);
    tuiput(8,5,39,text);
  }
  else
  {
    tuiput(6,5,'C',hot);   /* one attr for the whole token: the transcript
                              greps want its bytes contiguous, and an SGR
                              would land mid-token on an attr change */
    numtext(7,5,k,hot);
  }
  tuiflush();
  return 0;
}

func main()
{
  var k:int;
  frame=C_BWHITE+C_BLUE*16;
  text=C_WHITE+C_BLUE*16;
  hot=C_BWHITE+C_BLUE*16;
  if(tuiinit())return 2;
  drawall();
  while(1)
  {
    k=tuikey(0-1);
    if(k==K_NONE)continue;
    if((k=='q')||(k==K_F10))break;
    if(k==K_RESIZE)
    {
      tuiresize();
      drawall();
      showkey(k);
      continue;
    }
    showkey(k);
  }
  tuidone();
  return 0;
}
