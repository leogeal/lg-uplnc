/* tui.e: raw terminal control, the key decoder, and the diff-rendering cell
   compositor -- the platform + screen/input slice of the UPLNC IDE plan
   (IDE.md section 7 step 1). All terminal state changes go through
   ide/tshim.c; tuidone() restores the terminal exactly as tuiinit found it
   (alternate screen + cursor + termios), which the PTY tests pin.

   The screen is a grid of cells, one int each: the byte in bits 0-7 and the
   attribute above it (fg 0-15, bg 0-7, A_ACS selects the DEC line-drawing
   charset for single-byte box glyphs). Draw calls touch only the back grid;
   tuiflush() emits the difference against the front grid as one write --
   cursor moves, SGR changes, and charset shifts are coalesced, so the byte
   stream is deterministic and cheap. */

#include "tui.he"

func malloc(n:int);
func free(p:int);
func exit(c:int);
func tsh_rawon();
func tsh_rawoff();
func tsh_winsz();
func tsh_sigwinch();
func tsh_tookwinch();
func tsh_poll(fd:int,ms:int);
func tsh_read(fd:int,buf:*char,n:int);
func tsh_write(fd:int,buf:*char,n:int);
var extern stderr:*int;

var tui_w,tui_h:int;       /* current grid size */
var tui_front:*int;        /* what the terminal shows */
var tui_back:*int;         /* what the next flush should show */
var tui_ob:*char;          /* the flush batch buffer */
var tui_obn,tui_obcap:int;
var tui_up:int;            /* tuiinit ran and tuidone has not */

func obgrow(need:int)
{
  var nb:*char;
  var i:int;
  if(tui_obn+need<=tui_obcap)return 0;
  while(tui_obcap<tui_obn+need)tui_obcap=tui_obcap*2;
  nb=malloc(tui_obcap);
  if(!nb){fprintf(stderr,"tui: out of memory\n");exit(2);}
  for(i=0;i<tui_obn;i++)nb[i]=tui_ob[i];
  free(tui_ob);
  tui_ob=nb;
  return 0;
}

func obput(c:int)
{
  obgrow(1);
  tui_ob[tui_obn++]=c;
  return 0;
}

func obtext(s:*char)
{
  while(*s)obput(*s++);
  return 0;
}

/* ESC + the given tail: UPLNC string literals have no hex escapes, so the
   escape byte is emitted as the number 27 */
func obesc(s:*char)
{
  obput(27);
  obtext(s);
  return 0;
}

func obdec(n:int)
{
  if(n>=10)obdec(n/10);
  obput('0'+n%10);
  return 0;
}

func obflush()
{
  if(tui_obn)tsh_write(1,tui_ob,tui_obn);
  tui_obn=0;
  return 0;
}

/* allocate (or reallocate after a resize) both grids, all cells blank */
func gridalloc()
{
  var n,i,blank:int;
  if(tui_front)free(tui_front);
  if(tui_back)free(tui_back);
  n=tui_w*tui_h;
  tui_front=malloc(n*sizeof(int));
  tui_back=malloc(n*sizeof(int));
  if((!tui_front)||(!tui_back)){fprintf(stderr,"tui: out of memory\n");exit(2);}
  blank=' '+256*(C_WHITE+C_BLACK*16);
  for(i=0;i<n;i++)
  {
    tui_front[i]=0-1;   /* unknown: the first flush repaints everything */
    tui_back[i]=blank;
  }
  return 0;
}

func tuirows(){return tui_h;}
func tuicols(){return tui_w;}

/* query the terminal size into tui_w/tui_h (80x24 when not a tty) */
func sizequery()
{
  var wz:int;
  wz=tsh_winsz();
  if(wz<0){tui_h=24;tui_w=80;return 0;}
  tui_h=(wz>>16)&65535;
  tui_w=wz&65535;
  if(tui_h<1)tui_h=24;
  if(tui_w<1)tui_w=80;
  return 0;
}

func tuiinit()
{
  if(tui_up)return 0;
  tui_obcap=4096;tui_obn=0;
  tui_ob=malloc(tui_obcap);
  if(!tui_ob){fprintf(stderr,"tui: out of memory\n");exit(2);}
  tsh_sigwinch();
  if(tsh_rawon()<0)
  {
    fprintf(stderr,"tui: stdin is not a terminal\n");
    return 0-1;
  }
  sizequery();
  gridalloc();
  obesc("[?1049h");   /* alternate screen: the shell's scrollback survives */
  obesc("[?25l");     /* hide the cursor while composing */
  obesc("[2J");
  obflush();
  tui_up=1;
  return 0;
}

func tuidone()
{
  if(!tui_up)return 0;
  obesc("(B");        /* leave the line-drawing charset if it was active */
  obesc("[0m");
  obesc("[?25h");
  obesc("[?1049l");   /* back to the primary screen, exactly as it was */
  obflush();
  tsh_rawoff();
  tui_up=0;
  return 0;
}

/* after K_RESIZE: re-query the size and force a full repaint */
func tuiresize()
{
  sizequery();
  gridalloc();
  obesc("[2J");
  obflush();
  return 0;
}

func tuiput(x:int,y:int,c:int,attr:int)
{
  if((x<0)||(y<0)||(x>=tui_w)||(y>=tui_h))return 0;
  tui_back[y*tui_w+x]=(c&255)+256*attr;
  return 0;
}

func tuitext(x:int,y:int,s:*char,attr:int)
{
  while(*s)
  {
    tuiput(x,y,*s++,attr);
    x++;
  }
  return 0;
}

func tuifill(x:int,y:int,w:int,h:int,c:int,attr:int)
{
  var i,j:int;
  for(j=0;j<h;j++)
  for(i=0;i<w;i++)
  tuiput(x+i,y+j,c,attr);
  return 0;
}

/* a single-line box in the DEC line-drawing charset */
func tuibox(x:int,y:int,w:int,h:int,attr:int)
{
  var i:int;
  if((w<2)||(h<2))return 0;
  tuiput(x,y,ACS_TL,attr+A_ACS);
  tuiput(x+w-1,y,ACS_TR,attr+A_ACS);
  tuiput(x,y+h-1,ACS_BL,attr+A_ACS);
  tuiput(x+w-1,y+h-1,ACS_BR,attr+A_ACS);
  for(i=1;i<w-1;i++)
  {
    tuiput(x+i,y,ACS_HLINE,attr+A_ACS);
    tuiput(x+i,y+h-1,ACS_HLINE,attr+A_ACS);
  }
  for(i=1;i<h-1;i++)
  {
    tuiput(x,y+i,ACS_VLINE,attr+A_ACS);
    tuiput(x+w-1,y+i,ACS_VLINE,attr+A_ACS);
  }
  return 0;
}

/* emit the SGR for attr (fg 0-15 with 8-15 bold, bg 0-7) */
func sgrfor(attr:int)
{
  var fg,bg:int;
  fg=attr%16;
  bg=(attr/16)%16;
  obesc("[0;");
  if(fg>=8){obtext("1;");fg=fg-8;}
  obput('3');obput('0'+fg);
  obput(';');
  obput('4');obput('0'+bg%8);
  obput('m');
  return 0;
}

/* write the back grid's difference to the terminal as one batched write */
func tuiflush()
{
  var x,y,i,cell,attr,acs:int;
  var curattr,curacs,curx,cury:int;
  curattr=0-1;curacs=0;curx=0-1;cury=0-1;
  for(y=0;y<tui_h;y++)
  for(x=0;x<tui_w;x++)
  {
    i=y*tui_w+x;
    cell=tui_back[i];
    if(cell==tui_front[i])continue;
    if((y!=cury)||(x!=curx))
    {
      obesc("[");obdec(y+1);obput(';');obdec(x+1);obput('H');
      cury=y;curx=x;
    }
    attr=cell/256;
    acs=0;
    if(attr>=A_ACS){acs=1;attr=attr-A_ACS;}
    if(attr!=curattr){sgrfor(attr);curattr=attr;}
    if(acs!=curacs)
    {
      if(acs)obesc("(0");
      else obesc("(B");
      curacs=acs;
    }
    obput(cell&255);
    curx++;
    tui_front[i]=cell;
  }
  if(curacs)obesc("(B");
  obflush();
  return 0;
}

/* one byte from stdin, or -1 on timeout/EOF within ms */
func kbyte(ms:int)
{
  var [4]char:b;
  if(tsh_poll(0,ms)!=1)return 0-1;
  if(tsh_read(0,b,1)!=1)return 0-1;
  if(b[0]<0)return b[0]+256;
  return b[0];
}

/* decode a CSI sequence after ESC [ was read: arrows, nav keys, Fn via ~ */
func kcsi()
{
  var c,n:int;
  n=0;
  while(1)
  {
    c=kbyte(25);
    if(c<0)return K_NONE;
    if((c>='0')&&(c<='9')){n=n*10+c-'0';continue;}
    if(c==';'){n=0;continue;}   /* modifiers are ignored in this slice */
    break;
  }
  if(c=='A')return K_UP;
  if(c=='B')return K_DOWN;
  if(c=='C')return K_RIGHT;
  if(c=='D')return K_LEFT;
  if(c=='H')return K_HOME;
  if(c=='F')return K_END;
  if(c=='~')
  {
    if(n==1)return K_HOME;
    if(n==2)return K_INS;
    if(n==3)return K_DEL;
    if(n==4)return K_END;
    if(n==5)return K_PGUP;
    if(n==6)return K_PGDN;
    if(n==11)return K_F1;
    if(n==12)return K_F2;
    if(n==13)return K_F3;
    if(n==14)return K_F4;
    if(n==15)return K_F5;
    if(n==17)return K_F6;
    if(n==18)return K_F7;
    if(n==19)return K_F8;
    if(n==20)return K_F9;
    if(n==21)return K_F10;
    if(n==23)return K_F11;
    if(n==24)return K_F12;
  }
  return K_NONE;
}

/* wait up to ms for one key event; K_NONE on timeout, K_RESIZE after a
   SIGWINCH (the caller runs tuiresize and repaints) */
func tuikey(ms:int)
{
  var c:int;
  if(tsh_tookwinch())return K_RESIZE;
  c=kbyte(ms);
  if(tsh_tookwinch())return K_RESIZE;
  if(c<0)return K_NONE;
  if(c==127)return K_BS;
  if(c!=27)return c;
  c=kbyte(25);          /* a lone ESC has no follow-up byte */
  if(c<0)return K_ESC;
  if(c=='[')return kcsi();
  if(c=='O')
  {
    c=kbyte(25);
    if(c=='P')return K_F1;
    if(c=='Q')return K_F2;
    if(c=='R')return K_F3;
    if(c=='S')return K_F4;
    if(c=='H')return K_HOME;
    if(c=='F')return K_END;
    return K_NONE;
  }
  return K_ESC;
}
