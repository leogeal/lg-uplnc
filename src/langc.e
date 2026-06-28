/*                    -*- C -*-                                            */
/*            The language compiler by E.V., (C) 2003                        */
/*
  This program is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 2 of the License, or
  (at your option) any later version.
  
  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.
  
  You should have received a copy of the GNU General Public License
  along with this program; if not, write to the Free Software
  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
*/
#include "tlangc.he"
#include "codegen.he"


var starget:target;
var archsel:int;   /* target arch selected by -march (default ARCH_I386=0) */
/* M4 float-literal pool: literals are kept as text and emitted as `.double
   <text>` so the assembler computes the IEEE-754 bits. */
var fpoolbuf:[4000]char;
var fpooloff:[200]int;
var fpoolptr:int;
var fpoolbp:int;
var errcnt:int;
var ncmp:int;
var nfunc:int;
var nvars:int;
var lastst:int;
var argstk:int;
var argtop:int;
var Zsp:int;
var curfunc:*ssym;   /* M4 slice 4b: the function being compiled (for its return type) */
var cursret:*ssym;   /* M6 2b: the hidden sret pointer param of a struct-returning
                        function (0 if the current function returns a scalar) */
var g_sretp:*elval;  /* M6 2b: while a struct-returning call is being emitted for
                        `s = f()`, points at the destination lvalue s so ct_FUNC
                        passes &s as the sret pointer (0 otherwise) */
method snamenode.done()
{
  if(next)
  {
    next->done();
    free(next);
  }
}
method snamenode.init(){next=0;name[0]=0;}
method snamelist.dump()
{
  var *snamenode:p;
  for(p=lst;p;p=p->next)
  {
    fprintf(stderr,"%s\n",p->name);
  }
}
method snamelist.addm(*char:s)/*add(merge)*/
{
  if(!this)return;
  var *snamenode:p;
  if(p=find(s))
  return;
  chkmem(*front=calloc(1,sizeof(snamenode)));
  (*front)->init();
  strncpy((*front)->name,s,NAMESIZE);
  front=&(*front)->next;
}
method snamelist.find(*char:s)
{
  var *snamenode:p;
  for(p=lst;p;p=p->next)
  if(strid(p->name,s))
    return p;
  return 0;
}
method snamelist.init(){lst=0;front=&lst;}
method snamelist.done()
{
  front=&lst;
  if(lst)
  lst->done();
}
var *snamelist :cnmlst;
method ssym.init()
{
  chkmem(nmlst=calloc(1,sizeof(snamelist)));
  nmlst->init();
}
method ssym.done()
{
  if(nmlst)
  {
    nmlst->done();
    free(nmlst);
  }
}
var glbsymtab,locsymtab:ssymtab;
func ssymtabinit(p:*ssymtab)
{
  p->lst=0;
  p->front=&p->lst;
}
func ssymtaballoc(p:*ssymtab)
{
  var *ssym:res;
  (*p->front)=chkmem(calloc(1,sizeof(ssymlist)));
  (*p->front)->next=0;
  res=&(*p->front)->sym;
  p->front=&(*p->front)->next;
  return res;
}
func ssymtabfind(p:*ssymtab,name:*char)
{
  var *ssymlist:q;
  for(q=p->lst;q;q=q->next)
  {
    if(strid(name,q->sym.name))
    return &q->sym;
  }
  return 0;
}
func findglb(name:*char)
{
  return ssymtabfind(&glbsymtab,name);
}
func findloc(name:*char)
{
  return ssymtabfind(&locsymtab,name);
}
func ssymtabadd(p:*ssymtab,sname:*char,sort:int,dfd:int,offset:int,type:int)
{
  var *ssym:sym;
  sym=ssymtaballoc(p);
  sym->init();
  sym->sort=sort;
  sym->dfd=dfd;
  sym->offset=offset;
  sym->type=type;
  strcp(sym->name,sname);
  return sym;
}
func addloc(sname:*char,sort:int,dfd:int,offset:int,type:int)
{
  return ssymtabadd(&locsymtab,sname,sort,dfd,offset,type);
}
var extern cline:int;
func addglb(sname:*char,sort:int,dfd:int,offset:int,type:int)
{
  var *ssym:res;
  res=ssymtabadd(&glbsymtab,sname,sort,dfd,offset,type);
  res->line=cline;
  return res;
}
func ssymtabcut(p:*ssymtab,w:**ssymlist)
{
  var *ssymlist:i,n;
  for(i=*w;i;i=n)
  {
    n=i->next;
    free(i);
  }
  *w=0;
  p->front=w;
}
func ssymtabfree(p:*ssymtab)
{
  var *ssymlist:q;
  var *ssymlist:t;
  for(q=p->lst;q;q=t)
  {
    t=q->next;
    q->sym.done();
    free(q);
  }
  p->lst=0;
  p->front=&p->lst;
}
func ssymtabfindsym(symtab:*ssymtab,sname:*char)
{
  var *ssymlist:p;
  for(p=symtab->lst;p;p=p->next)
  if(strid(sname,p->sym.name))
    return p;
  return 0;
}
var typtab:*styp;
var numtyp:int;
/*var typnames:[TYPNMTBS]char;*/
/*var typsort:[NUMTYP]int;*/
/*var typtype:[NUMTYP]int;*/
/*var typdim:[NUMTYP]int;*/
/*var typsize:[NUMTYP]int;*/
var typptr:int;
var nmstrele:int;
var fieldtab:*sfield;
/*var strnames:[STRNMTBS]char;*/
/*var strtyp:[NMSTRELE]int;*/
/*var stroffse:[NMSTRELE]int;*/
/*var strnext:[NMSTRELE]int;*/
var strptr:int;
var tolitstk:int;
var litstk:[litstksz]char;
var litstk2:[litstksz]char;
var litstkle:[litstknu]int;
var litstkpt:[litstknu]int;
var line:[linesize]char;
var cline:int;
var mline:[linesize]char;
var lptr:int;
var mptr:int;
var nextlab:int;
func getlabel()
{
  return ++nextlab;
}
var stlab:int;
var stptr:int;
var litq:[STSIZE]char;
var wqsym:[WQNUM]int;
var wqsp:[WQNUM]int;
var wqloop:[WQNUM]int;
var wqlab:[WQNUM]int;
var wqptr:int;



func putlitst(c:char)
{
  if(litstkpt[tolitstk]+litstkle[tolitstk]>=litstksz-1){
  error("too large code from function arguments");
  return 0;
  }
  litstk[litstkpt[tolitstk]+litstkle[tolitstk]]=c;
  litstkle[tolitstk]=litstkle[tolitstk]+1;
  return c;
}
func getlitst()
{
  if(tolitstk>=litstknu-1){
  error("too many function arguments");
  return 0;
  }
  ++tolitstk;
  litstkle[tolitstk]=0;
  litstkpt[tolitstk]=litstkpt[tolitstk-1]+litstkle[tolitstk-1];
  return tolitstk;
}
func dumpltst(tl:int)
{
  var int:i;
  var int:p;
  var *char:q;
  var *char:pp;
  q=litstk2;
  while(tolitstk>=tl){
  i=litstkle[tolitstk];
  p=litstkpt[tolitstk];
  while(i--){
    *q++=litstk[p++];
  }
  tolitstk--;
  }
  pp=q;
  q=litstk2;
  while(q<pp){
  outbyte(*q);
  ++q;
  }
}
var iseof:int;
var isinp:int;
var quote:[2]char;
var tlcomp:[NAMESIZE]char;
var trcomp:[NAMESIZE]char;
var tlarg:[NAMESIZE]char;
var trarg:[NAMESIZE]char;
var tlsub:[NAMESIZE]char;
var trsub:[NAMESIZE]char;
var tfunc:[NAMESIZE]char;
func inittoke()
{
  strcp(tlcomp,"{");
  strcp(trcomp,"}");
  strcp(tlarg,"(");
  strcp(trarg,")");
  strcp(tlsub,"[");
  strcp(trsub,"]");
  strcp(tfunc,"func");
}
func dotakeof()
{
  var *char:token;
  var int:k,c;
  if(amatch("lcomp",5))token=tlcomp;
  else if(amatch("rcomp",5))token=trcomp;
  else if(amatch("larg",4))token=tlarg;
  else if(amatch("rarg",4))token=trarg;
  else if(amatch("lsub",4))token=tlsub;
  else if(amatch("rsub",4))token=trsub;
  else if(amatch("tfunc",5))token=tfunc;
  else
  {
    error("token name expected");
    return;
  }
  blanks();
  if(ch()!='"')
  {error("qstr expected");return;}
  gch();
  k=0;
  while(ch()!='"')
  {
    if(!ch())break;
    c=gch();
    if(c==92)
    {
      c=gch();
      if(!c)break;
      if(c=='n')c=10;
      else if(c=='t')c=9;
      else if(c=='b')c=8;
      else if(c=='f')c=12;
    }
    if(k<NAMEMAX)
    token[k++]=c;
  }
  if(ch()=='"')gch();
  token[k]=0;
  comment();outstr("new token:");outstr(token);nl();
  ns();
}
var int:tomap;
var *char:mapname;
var int:tograph;
var *char:graphname;
func parseopt(argc:int,argv:**char)
{
  tomap=0;
  mapname="tlmap.map";
  tograph=0;
  graphname="tlgraph.dat";
  /*fprintf(stderr,"parseopt()\n");*/
  var int:i;
  for(i=1;i<argc;i++)
  {
    if(strid(argv[i],"-march=x86_64"))
    {archsel=ARCH_X86_64;}
    else if(strid(argv[i],"-march=i386"))
    {archsel=ARCH_I386;}
    else if(strid(argv[i],"-march=arm64"))
    {archsel=ARCH_ARM64;}
    else if(strid(argv[i],"-march=riscv64"))
    {archsel=ARCH_RISCV;}
    else if(strid(argv[i],"-march=mips64"))
    {archsel=ARCH_MIPS;}
    else if(*argv[i]=='-')
    {
      fprintf(stderr,"option:\n");
      var k:int;
      for(k=1;argv[i][k];k++)
      if(argv[i][k]=='m')
        {
        tomap=1;
        if(argv[i][k+1]=='-')
          {tomap=0;k++;}
        fprintf(stderr," tomap=%d\n",tomap);
        }
      else if(argv[i][k]=='g')
        {
        tograph=1;
        if(argv[i][k+1]=='-')
          {tograph=0;k++;}
        fprintf(stderr," tograph=%d\n",tograph);
        }
      else if(argv[i][k]=='M')
        {
        if(argv[i][k+1])
          {
          mapname=argv[i]+k+1;
          while(argv[i][k])++k;
          }
        else if(i>=argc-1)
          {
          fprintf(stderr,"needs more arguments\n");
          }
        else
          {
          mapname=argv[++i];
          }
        fprintf(stderr," mapname=%s\n",mapname);
        }
      else if(argv[i][k]=='G')
        {
        if(argv[i][k+1])
          {
          graphname=argv[i]+k+1;
          while(argv[i][k])++k;
          }
        else if(i>=argc-1)
          {
          fprintf(stderr,"needs more arguments\n");
          }
        else
          {
          mapname=argv[++i];
          }
        fprintf(stderr," graphname=%s\n",graphname);
        }
    }
  }
}
var methodcls:int;/*whether we are in a method*/
var methodidx:int;
/*var methodths:*ssym;*/
/*var methodstr:int;*//*it's a type!*/
func main(argc:int,argv:**char)
{
  tolitstk=litstkpt[0]=litstkle[0]=ncmp=lastst=nextlab=
  lptr=iseof=strptr=stptr=errcnt=argstk=wqptr=line[0]=quote[1]=0;
  nfunc=0;nvars=0;cline=0;
  typptr=F_TYPE;
  strptr++;
  isinp=1;
  cnmlst=0;
  /*glbptr++;*/
  *quote='"';
  methodcls=0;methodidx=0;/*methodstr=0;*/
  initdyn();
  var *char:pp,pp2;pp=autodynstr("Hello ");pp2=autodynstr("world\n");
  stlab=getlabel();
  parseopt(argc,argv);
  inittarget();   /* after parseopt so -march has been seen */
  initsyms();
  inittoke();
  inittypes();
  initfields();
  initst();
  icodegen();
  header();
  parse();
  dumplits();
  dumpfloats();
  dumpglbs();
  if(tomap)
  printmap();
  if(tograph)
  printgraph();
  trailer();
  dcodegen();
  errorsum();
  freefields();
  freetypes();
  freesyms();
  /*fprintf(stderr,"(%d)(%d)%s%s",pp,pp2,pp,pp2);*/
  donedyn();
  return 0;
}
func initsyms()
{
  ssymtabinit(&glbsymtab);
  ssymtabinit(&locsymtab);
}
func freesyms()
{
  ssymtabfree(&locsymtab);
  ssymtabfree(&glbsymtab);
}
func chkmem(p:*int)
{
  /*fprintf(stderr,"chkmem(%d)\n",p);*/
  if(!p)
  {
    error("out of memory");
    exit(2);
  }
  else
  return p;
}
func errorsum()
{
  if(ncmp)error("missing '}'");
  comment();
  outstr(" ");
  outdec(errcnt);
  outstr(" error(s)");
  nl();
  comment();
  outstr(" ");
  outdec(nfunc);
  outstr(" function(s), ");
  outdec(nvars);outstr(" global variables");
  nl();
}
func header()
{
  comment();
  outstr("The Test Compiler");
  nl();
}
func parse()
{
  while(!iseof)
  {
    if(match("#define"))addmac();
    else if(amatch("%%takeoff",9))
    {
      comment();
      outstr(">>>>");
      nl();
      dotakeof();
    }
    else if(amatch("var",3))dovar();
    else if(amatch("enum",4))doenum();
    else if(amatch("struct",6))prstrct(dostruct());
    else if(amatch(tfunc/*"func"*/,4))dofunc();
    else if(amatch("method",6))domethod();
    else
    {
      error("wrong declaration- top level");
      reset();
    }
    blanks();
  }
}
/* parse a constant integer expression (an enum value or an array dimension):
   one expression below the comma operator, folded; if it does not collapse to a
   literal, report <what> and return 0. hier1() consumes its tokens, so this also
   makes a bad value fail cleanly instead of looping (unlike a bare number()). */
func constexpr(what:*char)
{
  var *enode:vnode;
  var int:v;
  v=0;
  vnode=hier1();
  foldtree(vnode);
  if(vnode&&(vnode->op==OP_LEAF)&&(vnode->leaf.vid==L_NUM))v=vnode->leaf.val;
  else error(what);
  delenode(vnode);
  return v;
}
/* enum { NAME [= constexpr], NAME, ... };  -- introduce named integer constants.
   Values run sequentially from 0 (or from the last explicit value + 1). An
   explicit value is any constant integer expression, including a prior enum
   constant (registered as we go, so `enum{X=10,Y=X+5}` works). The names become
   global S_CONST symbols; primary() resolves a reference to an L_NUM literal. */
func doenum()
{
  var [NAMESIZE]char:nm;
  var int:val;
  val=0;
  needbrac(tlcomp/*"{"*/);
  while(1)
  {
    blanks();
    if(streq(line+lptr,trcomp))break;   /* allow an empty list / trailing comma */
    if(!symname(nm)){error("enum constant name expected");break;}
    if(match("="))val=constexpr("enum value must be a constant integer");
    addglb(nm,S_CONST,1,val,T_INT);
    val=val+1;
    if(!match(","))break;
  }
  needbrac(trcomp/*"}"*/);
  ns();
}
func findtyp(sname:*char)
{
  var int:res;
  var *char:p;
  res=1;
  while(res<typptr){
  p=typtab[res].name;
  if(astreq(sname,p,NAMEMAX))return res;
  res++;
  }
  return 0;
}
func dostruct()
{
  var [NAMESIZE]char:sname;
  var [NAMESIZE]char:fname;
  var int:t;
  var int:sz;
  /*var *int:top;*/
  var int:ttop;
  var int:offs;
  var int:res;
  if(typptr>=numtyp){
  /*fprintf(stderr,"reallocating types\n");*/
  numtyp=numtyp+NUMTYP;
  chkmem(typtab=realloc(typtab,sizeof(styp)*numtyp));
  }
  res=typptr++;
  if(!symname(sname))error("structure name exected");
  if(findtyp(sname))error("multidef type");
  comment();
  outstr("name of struct:");
  outstr(sname);
  nl();
  comment();
  outstr("1typptr=");
  outdec(typptr);
  nl();
  strcp(typtab[res].name,sname);
  typtab[res].sort=V_STR;
  needbrac(tlcomp/*"{"*/);
  ttop=0;/*top=&typtab[res].type*//*typtype+res*/;
  /* *top=0;*/typtab[res].type=0;
  offs=0;
  while(1){
  blanks();
  if(iseof)break;
  /*if(ch()=='}')break;*/
  if(streq(line+lptr,trcomp))break;
  if(amatch(tfunc/*func*/,4))
    {
    if(cbtype())
      t=gettypen();
    else t=T_INT;
    t=getfnctype(t);
    if(!symname(fname))
      error("method name expected");
    ns();
    if(!ttop)
      {
      comment();outstr("BEGINNING\n");
      typtab[res].type=afield(t,fname,offs);
      ttop=typtab[res].type;
      }
    else
      {
      comment();outstr("assigning");
      fieldtab[ttop].next=afield(t,fname,offs);
      nl();
      ttop=fieldtab[ttop].next;
      }
    /**top=afield(t,fname,offs);*/
    /*top=&fieldtab[*top].next;*/
    /*sz=gettsize(t);
    if(sz&3)sz=sz+4-(sz&3);
    offs=offs+sz;*/
    continue;
    }
  var int:istyp;
  istyp=0;
  if(cbtype())
    {
    t=gettypen();
    istyp=1;
    if(match(":"));
    }
  var *ssymlist:lst,lsptr;
  var **ssymlist:lpom;
  lst=lsptr=0;
  lpom=&lst;
  while(symname(fname))
    {
    chkmem((*lpom)=calloc(1,sizeof(ssymlist)));
    strcp((*lpom)->sym.name,fname);
    lpom=&(*lpom)->next;
    (*lpom)=0;
    blanks();
    if(istyp)
      {if(streq(line+lptr,";"))break;}
    else
      {if(streq(line+lptr,":"))break;}
    if(endst())break;
    if(!match(","))
      {
      error("',' or ':'|';' expected");
      junk();
      break;
      }
    }
  if(!istyp)
    {
    if(!match(":"))
      error("':' expected for Pascal-style declaration");
    t=gettypen();
    istyp=1;
    }
  ns();
  /*if(!symname(fname)){
    error("field name expected");
    reset();
    }*/
  for(lsptr=lst;lsptr;lsptr=lsptr->next)
    {
    comment();outstr("adding ");outstr(lsptr->sym.name);
    outstr(":");outdec(t);nl();
    if(!ttop)
      {
      typtab[res].type=afield(t,lsptr->sym.name,offs);
      ttop=typtab[res].type;
      }
    else
      {
      var int:alpha;
      comment();outstr("ttop=");outdec(ttop);nl();
      alpha=afield(t,lsptr->sym.name,offs);
      fieldtab[ttop].next=gggg();
      comment();outstr("fieldtab[ttop].next=");
      outdec(fieldtab[ttop].next);nl();
      fieldtab[ttop].next=alpha;
      /*fieldtab[ttop].next=afield(t,lsptr->sym.name,offs);*/
      comment();outstr("fieldtab[ttop].next=");
      outdec(fieldtab[ttop].next);
      ttop=fieldtab[ttop].next;
      }
    comment();outstr("ttop=");outdec(ttop);nl();
    prstrct(res);
    /**top=afield(t,lsptr->sym.name,offs);
    comment();outstr("*top=");outdec(*top);nl();
    top=&fieldtab[*top].next;*/
    sz=roundup(gettsize(t));
    offs=offs+sz;
    }
  delsymlist(lst);
  }
  comment();
  outstr("2typptr=");
  outdec(typptr);
  nl();
  typtab[res].size=offs;
  needbrac(trcomp/*"}"*/);
  ns();
  comment();
  outstr("typptr=");
  outdec(typptr);
  nl();
  return res;
}
func freefields()
{
  if(fieldtab)
  free(fieldtab);
}
func initfields()
{
  nmstrele=NMSTRELE;
  chkmem(fieldtab=calloc(nmstrele,sizeof(sfield)));
}
func freetypes()
{
  if(typtab)
  free(typtab);
}
func inittypes()
{
  numtyp=NUMTYP;
  chkmem(typtab=calloc(numtyp,sizeof(styp)));
  strcp(typtab[T_INT].name,"int");
  typtab[T_INT].sort=V_FND;
  typtab[T_INT].size=target.wordsize;
  strcp(typtab[T_CHAR].name,"char");
  typtab[T_CHAR].sort=V_FND;
  typtab[T_CHAR].size=BYTESIZE;
  typtab[T_INTP].name[0]=0;
  typtab[T_INTP].sort=V_PTR;
  typtab[T_INTP].type=T_INT;
  typtab[T_INTP].size=target.wordsize;
  typtab[T_CHARP].name[0]=0;
  typtab[T_CHARP].sort=V_PTR;
  typtab[T_CHARP].type=T_CHAR;
  typtab[T_CHARP].size=target.wordsize;
  strcp(typtab[T_DOUBLE].name,"double");
  typtab[T_DOUBLE].sort=V_FND;
  typtab[T_DOUBLE].size=8;
  strcp(typtab[T_FLOAT].name,"float");
  typtab[T_FLOAT].sort=V_FND;
  typtab[T_FLOAT].size=4;
  strcp(typtab[T_UINT].name,"unsigned");
  typtab[T_UINT].sort=V_FND;
  typtab[T_UINT].size=target.wordsize;
}
/* M4: a value of floating-point class (held in %xmm as a double once loaded). */
func isfp(t:int){return (t==T_DOUBLE)||(t==T_FLOAT);}
func initst()
{
}
func prstrct(s:int)
{
  var int:k;
  comment();
  outstr("structn ");
  outdec(s);
  outstr(" sz:");
  outdec(typtab[s].size);
  outstr(" name ");
  outstr(typtab[s].name);
  nl();
  k=typtab[s].type;
  while(k){
  comment();
  outstr("type ");
  outdec(fieldtab[k].type);
  outstr(" ");
  outstr(fieldtab[k].name);
  nl();
  k=fieldtab[k].next;
  }
}
func findfiel(nm:*char,s:int)
{
  var int:k;
  comment();
  outstr("typsort[");
  outdec(s);
  outstr("]=");
  outdec(typtab[s].sort);
  nl();
  if(typtab[s].sort!=V_STR){
  error("cannot find a field in a non-struct");
  return 0;
  }
  k=typtab[s].type;
  while(k){
  if(strid(nm,fieldtab[k].name))return k;
  k=fieldtab[k].next;
  }
  return 0;
}
func afield(t:int,fname:*char,offs:int)
{
  /*fprintf(stderr,"strptr=%d\n",strptr);*/
  comment();outstr("strptr=");outdec(strptr);nl();
  if(strptr>=nmstrele)
  {
    /*fprintf(stderr,"reallocating field table\n");*/
    comment();outstr("reallocating field table");nl();
    nmstrele=nmstrele+NMSTRELE;
    comment();outstr("nmstrele=");outdec(nmstrele);nl();
    chkmem(fieldtab=realloc(fieldtab,nmstrele*sizeof(sfield)));
  }
  strcp(fieldtab[strptr].name,fname);
  fieldtab[strptr].type=t;
  fieldtab[strptr].offset=offs;
  fieldtab[strptr].next=0;
  comment();outstr("++,strptr=");outdec(strptr);nl();
  return strptr++;
}
func gggg(){return 209;}
func endst()
{
  blanks();
  return ((ch()==';')||(ch()==0));
}
func delsymlist(p:*ssymlist)
{
  if(!p)return;
  delsymlist(p->next);
  free(p);
}
func dovar()
{
  var int:typ,istyp,wdfd,wcnst;
  var *ssymlist:lst,lptr;
  var **ssymlist:lpom;
  var *ssym:idx;
  var [NAMESIZE]char:sname;
  istyp=0;
  lst=lptr=0;
  lpom=&lst;
  wdfd=1;wcnst=0;
  while(1)
  {
    if(amatch("extern",6))wdfd=0;
    else if(amatch("const",5))wcnst=1;   /* M6: var const TYPE:name */
    else break;
  }
  if(cbtype())
  {
    istyp=1;
    typ=gettypen();
    while(1)
    {
      if(amatch("extern",6))wdfd=0;
      else break;
    }
    if(!match(":"))
    error("':' expected");
    while(1)
    {
      if(amatch("extern",6))wdfd=0;
      else break;
    }
  }
  blanks();
  if(!an(ch()))error("expected name of variable");
  while(symname(sname))
  {
    chkmem((*lpom)=calloc(1,sizeof(ssymlist)));
    strcp((*lpom)->sym.name,sname);
    lpom=&(*lpom)->next;
    (*lpom)=0;
    if(istyp)
    {if(match(";"))break;}
    else
    {if(match(":"))break;}
    if(endst())break;
    if(!match(","))
    {
      error("',' or ':'|';' expected");
      junk();
      break;
    }
  }
  if(!istyp)
  {
    while(1)
    {
      if(amatch("extern",6))wdfd=0;
      else
      break;
    }
    typ=gettypen();
    while(1)
    {
      if(amatch("extern",6))wdfd=0;
      else
      break;
    }
    ns();
  }
  for(lptr=lst;lptr;lptr=lptr->next)
  {
    idx=findglb(lptr->sym.name);
    if(idx)
    {
      if(idx->sort!=S_VARG)
      {
        error("multidef global var");
        break;
      }
      else if(idx->dfd)
      {
        error("multidef global var, was defined");
        break;
      }
      else if(typ!=idx->type)
      {
        error("conflicting types!");
        break;
      }
    }
    idx=addglb(lptr->sym.name,S_VARG,wdfd,0,typ);
    if(wcnst)idx->cnst=1;   /* M6 const */
    if(wdfd)++nvars;
  }
  delsymlist(lst);
}
func addmac()
{
  comment();
  ol(".mac");
}
func match(lit:*char)
{
  var int:k;
  blanks();
  if(k=streq(line+lptr,lit)){
  lptr=lptr+k;
  return 1;
  }
  return 0;
}
func streq(str1:*char,str2:*char)
{
  var int:k;
  k=0;
  while(str2[k]){
  if(str1[k]!=str2[k])return 0;
  ++k;
  }
  return k;
}
func strid(str1:*char,str2:*char)
{
  var int:k;
  k=0;
  while(str2[k]){
  if(str1[k]!=str2[k])return 0;
  ++k;
  }
  if(str1[k])return 0;
  return 1;
}
func amatch(lit:*char,len:int)
{
  var int:k;
  blanks();
  if(k=astreq(line+lptr,lit,len)){
  lptr=lptr+k;
  return 1;
  }
  return 0;
}
func blanks()
{
  while(1)
  {
    while(!ch())
    {
      insline();
      preproce();
      if(iseof)break;
    }
    if(ch()==' ')gch();
    else
    if(ch()==9)gch();
    else
      return ;
  }
}
func an(c:char)
{
  /*return ((alpha(c))||(numeric(c)));*/
  return ((c>='a')&&(c<='z'))||((c>='A')&&(c<='Z'))||
  ((c>='0')&&(c<='9'))||(c=='_');
}
func numeric(c:char)
{
  return ((c>='0')&&(c<='9'));
}
func alpha(c:char)
{
  return (((c>='a')&&(c<='z'))||((c>='A')&&(c<='Z'))||(c=='_'));
}
func gch()
{
  if(!ch())return 0;
  return line[lptr++];
}
func ch()
{
  return line[lptr];
}
func insline()
{
  var int:k;
  if(!isinp)iseof=1;
  if(iseof)return ;
  lptr=0;
  line[0]=0;
  while((k=getchar())>0){
  if((k==10)||(lptr>=linemax))break;
  line[lptr++]=k;
  }
  line[lptr]=0;
  if(k<0)isinp=0;
  if(lptr){
  comment();
  outstr(line);
  nl();
  lptr=0;
  }
  cline++;
}
func preproce()
{
}
func astreq(str1:*char,str2:*char,len:int)
{
  var int:k;
  k=0;
  while(k<len){
  if((str1[k])!=(str2[k]))break;
  if(!str1[k])break;
  if(!str2[k])break;
  ++k;
  }
  if(an(str1[k]))return 0;
  if(an(str2[k]))return 0;
  return k;
}
func domethod()
{
  methodcls=1;
  var [NAMESIZE]char:tname,mname;
  if(!symname(tname))
  {error("symbol name expected");methodcls=0;return;}
  if(!(match(".")||match("::")))
  {error("'.' or '::' expected");methodcls=0;return;}
  if(!symname(mname))
  {error("method name expected");methodcls=0;return;}
  var int:stridx;
  stridx=findtyp(tname);
  if(!stridx)
  {error("no such type");methodcls=0;return;}
  if(typtab[stridx].sort!=V_STR)
  {error("must be a structure to have a method");methodcls=0;return;}
  var int:k;
  if(!(k=findfiel(mname,stridx)))
  {error("no such method");methodcls=0;return;}
  if(typtab[fieldtab[k].type].sort!=V_FNC)
  {error("method must be a function");methodcls=0;return;}
  methodcls=stridx;/*the type in which the method is*/
  methodidx=k;/*the index of the method in fieldtab*/
  dofunc();
  methodcls=0;
  methodidx=0;
}
func dofunc()
{
  var [NAMESIZE]char:n;
  var [NAMESIZE]char:argn;
  var int:argtype;
  var *ssym:gp;
  var int:k;
  var [8]int:paramtyp;   /* M4 slice 4b: type of each register param, by position */
  var int:nfpparam;      /* M4 slice 4b: how many params are doubles */
  nfpparam=0;
  comment();
  ol(".fnc");
  if(methodcls&&methodidx)
  {
    strcp(n,typtab[methodcls].name);
    strcat(n,".");/* DANGEROUS !! */
    strcat(n,fieldtab[methodidx].name);/* DANGEROUS- FixMe */
  }
  else if(!symname(n))
  {
    error("wrong function declaration");
    reset();
    return ;
  }
  comment();
  outstr(">> ");
  outstr(n);
  nl();
  gp=findglb(n);
  /*comment();
  outstr("gp:");
  outdec(gp);
  nl();*/
  if(gp){
  if(gp->sort!=S_FUNC)error("multidef");
  }
  else
  {
    gp=addglb(n,S_FUNC,0,0,T_INT);
  }
  curfunc=gp;
  cursret=0;   /* M6 2b: set below if this function returns a struct */
  if(!match(tlarg/*"("*/))error("missing '('");
  argstk=0;
  Zsp=0;
  /*locptr=STARTLOC;*/
  ssymtabfree(&locsymtab);
  if(methodcls&&methodidx)
  {
    if(target.arch!=ARCH_I386)
    addloc("this",S_VARL,1,-(argstk+target.wordsize),getptrty(methodcls));
    else
    addloc("this",S_VARL,1,argstk+2*target.wordsize,getptrty(methodcls));
    paramtyp[0]=T_INTP;   /* 'this' is a pointer (integer class), never a double */
    argstk=argstk+target.wordsize;
  }
  while(!match(trarg/*")"*/))
  {
    if(cbtype())
    {
      argtype=gettypen();
      if(match(":"));
      if(!symname(argn))
      {
        error("parameter name expected");
        junk();
      }
      /*if(endst())break;*/
    }
    else
    {
      if(!symname(argn))
      {
        error("parameter name expected");
        junk();
      }
      if(endst())break;
      if(!match(":"))error("':' expected");
      argtype=gettypen();
    }
    k=gettsize(argtype);
    /* round arg slot up to a target word (i386: 4, x86_64: 8) */
    if(k&(target.wordsize-1))k=k+target.wordsize-(k&(target.wordsize-1));
    if(target.arch!=ARCH_I386)
    {
      /* SysV/AAPCS64: params 1-6 arrive in registers and are spilled to
         -(slot)(fp); params 7+ arrive on the stack (caller-pushed). */
      var int:pidx;var int:boff;
      pidx=argstk/target.wordsize;
      if(argtype==T_FLOAT)   /* slice 5: float at the ABI boundary is single-prec */
      error("float parameter not supported yet -- use double");
      if(pidx<8)paramtyp[pidx]=argtype;   /* slice 4b: remember param types */
      if(argtype==T_DOUBLE)nfpparam=nfpparam+1;
      /* Big-endian: a sub-word param (char) is passed/spilled inside a full word,
         so its byte lives at the *high* end of the slot. Shift the symbol offset
         to that byte; reads/writes/address-of then all hit the right byte. */
      boff=0;
      if(target.bigendian&&(gettsize(argtype)<target.wordsize))
      boff=target.wordsize-gettsize(argtype);
      if(pidx<target.nargreg)
      addloc(argn,S_VARL,1,-(argstk+target.wordsize)+boff,argtype);
      else
      /* stack params sit above the 16-byte frame record at a per-slot stride
         (==wordsize, but 16 on arm64 where each pushed arg is a 16-byte slot) */
      addloc(argn,S_VARL,1,2*target.wordsize+(pidx-6)*target.stackslot+boff,argtype);
      argstk=argstk+target.wordsize;
    }
    else
    {
      addloc(argn,S_VARL,1,argstk+2*target.wordsize,argtype);
      argstk=argstk+k;
    }
    if(!match(","))if(ch()!=')')
    {
      error("comma or ')' expected");
      break;
    }
    if(endst())break;
  }
  /* optional return-type annotation:  func f(...) : double  (M4 slice 4b).
     Absent -> int (unchanged); set on gp so forward declarations carry it too. */
  if(match(":"))
  {
    gp->type=gettypen();
    if(gp->type==T_FLOAT)   /* slice 5: float return is single-prec at the ABI */
    error("float return not supported yet -- use double");
  }
  if(match(";"))return ;
  nfunc++;
  var *snamelist:savenmlst;
  savenmlst=cnmlst;
  cnmlst=gp->nmlst;
  var *scodegen:savecg;
  /*fprintf(stderr,"dofunc:ccg=%d\n",ccg);*/
  savecg=ccg;
  /*fprintf(stderr,"dofunc:savecg=%d\n",savecg);*/
  var scodegen:codeg;
  cg_init(&codeg);
  ccg=&codeg;
  if(gp->dfd)error("this function was already defined");
  gp->dfd=1;
  ol(target.dir_text);
  ol(target.dir_align);
  outasm(target.dir_globl);
  outname(n);
  nl();
  ot(target.dir_type);
  tab();
  outname(n);
  outasm(target.dir_func);
  nl();
  outname(n);
  col();
  nl();
  /*ol("pushl %ebp");
  ol("movl %esp, %ebp");*/
  /* M6 2b: a struct-returning function takes a hidden pointer to the caller's
     result location as its LAST parameter (added after the explicit params, so
     at the call site it is pushed first and lands in the last argument register /
     stack slot). doreturn copies the returned struct through it. A method (which
     already has a hidden 'this') returning a struct is not supported yet. */
  if((typtab[gp->type].sort==V_STR)&&!(methodcls&&methodidx))
  {
    /* the sret pointer is the last param; on the register targets it must land in
       a free argument register, i.e. the explicit params must leave one. A struct
       return alongside >= nargreg explicit params (sret would spill to the stack)
       is not supported yet -- reject cleanly rather than miscompile. i386 passes
       every param on the stack, so it has no such limit. */
    if((target.arch!=ARCH_I386)&&(argstk/target.wordsize>=target.nargreg))
    error("a struct-returning function with this many parameters is not supported yet");
    if(target.arch!=ARCH_I386)
    cursret=addloc("0sret",S_VARL,1,-(argstk+target.wordsize),T_INTP);
    else
    cursret=addloc("0sret",S_VARL,1,argstk+2*target.wordsize,T_INTP);
    if(argstk/target.wordsize<8)paramtyp[argstk/target.wordsize]=T_INTP;
    argstk=argstk+target.wordsize;
  }
  zenter();
  if(target.arch!=ARCH_I386)
  {
    /* reserve slots for and spill only the register params (1-6); params 7+ are
       on the caller's stack at positive offsets and need no spill. */
    var int:nsp;
    nsp=argstk/target.wordsize;
    if(nsp>target.nargreg)nsp=target.nargreg;
    if(nsp>0)
    {
      Zsp=modstk(Zsp-nsp*target.wordsize);
      /* riscv and mips pass FP args in integer registers, so a double param
         arrives in an integer arg register too -- spill it (its bits) with the
         plain integer spillargs, then it is read back as a double via ldc1/fld. */
      if((nfpparam==0)||(target.arch==ARCH_RISCV)||(target.arch==ARCH_MIPS))
      spillargs(nsp);   /* all-integer params: unchanged, byte-identical path */
      else
      {
        /* mixed/float params: route by SysV class -- doubles came in %xmm0..,
           ints/ptrs in %rdi.., each spilled to its own slot -(pidx+1)*ws(%rbp). */
        var int:pi;var int:ireg;var int:freg;
        ireg=0;freg=0;
        for(pi=0;pi<nsp;pi++)
        {
          if(paramtyp[pi]==T_DOUBLE)
          {sargfp(-(pi+1)*target.wordsize,freg);freg=freg+1;}
          else
          {sargint(-(pi+1)*target.wordsize,ireg);ireg=ireg+1;}
        }
      }
    }
  }
  statemen();
  /*ol("movl %ebp, %esp");
  ol("popl %ebp");*/
  zleave();
  zret();
  cg_print(&codeg);
  cg_done(&codeg);
  /*fprintf(stderr,"dofunc:savecg=%d\n",savecg);*/
  ccg=savecg;
  cnmlst=savenmlst;
  /*fprintf(stderr,"dofunc:ccg=%d\n",ccg);*/
}
func _zret()
{
  ol("ret");
}
func statemen()
{
  /*fprintf(stderr,"statemen():ccg=%d\n",ccg);*/
  blanks();
  if((!ch())&&iseof)return 0;
  else
  if(amatch("var",3))dolocvar();
  else if(match(tlcomp/*"{"*/))compound();
  else if(amatch("if",2))
    {
      doif();
      lastst=stif;
    }
  else if(amatch("while",5))
    {
    dowhile();
    lastst=stwhile;
    }
  else if(amatch("for",3))
    {
    dofor();
    lastst=stfor;
    }
  else if(amatch("do",2))
    {
    dodo();
    lastst=stdo;
    }
  else if(amatch("switch",6))
    {
    doswitch();
    lastst=stswitch;
    }
  else if(amatch("return",6))
    {
    doreturn();
    ns();
    lastst=streturn;
    }
  else if(amatch("break",5))
    {
    dobreak();
    ns();
    lastst=stbreak;
    }
  else if(amatch("continue",8))
    {
    docont();
    ns();
    lastst=stcont;
    }
  else if(match(";"));
  else
    {
    expressi();
    ns();
    lastst=stexp;
    }
  return lastst;
}
/* M6 2b: copy a struct (the lvalue `src`) through the pointer held in the local
   `sretsym` -- i.e. *sretsym = src. Word-by-word (byte tail if any): load the
   pointer, push it, load the source word, store it through the popped pointer at
   the running offset. Used by doreturn to write the result into the caller's
   sret location. */
func copystructp(sretsym:*ssym,src:*elval)
{
  var elval:pw,sw,dp;
  var int:n,off,ws;
  n=typtab[src->typ].size;
  ws=target.wordsize;
  off=0;
  while(off+ws<=n)
  {
    pw.sort=L_ID;pw.idx=sretsym;pw.offset=0;pw.typ=T_INTP;getmem(&pw);
    zpush();
    sw.sort=L_ID;sw.idx=src->idx;strcp(sw.name,src->name);sw.offset=src->offset+off;sw.typ=T_INT;getmem(&sw);
    dp.sort=L_SP;dp.offset=off;dp.typ=T_INT;store(&dp);
    off=off+ws;
  }
  while(off<n)
  {
    pw.sort=L_ID;pw.idx=sretsym;pw.offset=0;pw.typ=T_INTP;getmem(&pw);
    zpush();
    sw.sort=L_ID;sw.idx=src->idx;strcp(sw.name,src->name);sw.offset=src->offset+off;sw.typ=T_CHAR;getmem(&sw);
    dp.sort=L_SP;dp.offset=off;dp.typ=T_CHAR;store(&dp);
    off=off+1;
  }
}
/* M6 2b: compute the address of a (named local or global) lvalue into the
   accumulator and push it -- used to pass &dst as a struct-return sret pointer. */
func pushaddr(lval:*elval)
{
  if(lval->idx&&(lval->idx->sort==S_VARL))zlea(lval->idx->offset+lval->offset);
  else if(lval->idx&&(lval->idx->sort==S_VARG))zlda(lval->idx->name,lval->offset);
  else error("cannot take the address of the struct-return target");
  zpush();
}
func doreturn()
{
  if(!endst())
  {
    if(cursret)
    {
      /* M6 2b: struct-returning function -- the return expression is a struct
         lvalue; copy it through the hidden sret pointer (do NOT rvalue it). */
      var *enode:rn;var elval:rlv;
      rn=bexptree();
      foldtree(rn);
      treetocode(rn,&rlv);
      if(typtab[rlv.typ].sort!=V_STR)
      error("a struct-returning function must return a struct");
      else if((rlv.sort!=L_ID)||(!rlv.idx))
      error("the returned struct must be a named struct variable (returning *p or a struct through a pointer is not supported yet)");
      else if(typtab[rlv.typ].size!=typtab[curfunc->type].size)
      error("returned struct has the wrong size");
      else copystructp(cursret,&rlv);
      delenode(rn);
    }
    else
    {
    var int:rt;
    rt=expressi();
    /* convert the return value to the function's return type (M4 slice 4b).
       A double-returning function leaves the result in %xmm0; otherwise a
       double result is truncated to int (slice 1 behaviour, e.g. main). */
    if(curfunc&&(curfunc->type==T_DOUBLE))
    {if(rt!=T_DOUBLE)i2f();}
    else
    {if(rt==T_DOUBLE)zf2i();}
    }
  }
  zleave();
  /*ol("movl %ebp, %esp");
  ol("popl %ebp");*/
  zret();
}
func compound()
{
  ++ncmp;
  while(!match(trcomp/*"}"*/))
  {
    statemen();
    if(iseof)break;
  }
  --ncmp;
}
func modstk(newsp:int)
{
  var int:k;
  k=newsp-Zsp;
  if(!k)return newsp;
  cmodstk(k);
  return newsp;
  if(k>0){
  ot("addl $");
  outdec(k);
  outasm(", %esp");
  nl();
  return newsp;
  }
  else
  {
    ot("subl $");
    outdec(-k);
    outasm(", %esp");
    nl();
    return newsp;
  }
}
func dolocvar()
{
  var [NAMESIZE]char:sname;
  var int:p1;
  var int:typ,istyp,wcnst,hasinit,irt;
  var *ssym:idx;
  var int:k;
  var *ssymlist:lst,lptr;
  var **ssymlist:lpom;
  var *enode:inode;
  var elval:ilv;
  lst=lptr=0;
  lpom=&lst;
  istyp=0;
  wcnst=0;hasinit=0;
  while(amatch("const",5))wcnst=1;   /* M6: var const TYPE:name (local) */
  if(cbtype())
  {
    /*fprintf(stderr,"line=%s\n",line);
    fprintf(stderr,"can be type\n");*/
    istyp=1;
    typ=gettypen();
    if(!match(":"))error("':' expected");
    k=gettsize(typ);
    comment();
    outstr("size:");
    outdec(k);
    nl();
    k=roundup(k);
    comment();
    outdec(k);
    nl();
  }
  blanks();
  if(!an(ch()))error("expected name of variable");
  /*p1=locptr;*/
  while(symname(sname))
  {
    chkmem((*lpom)=calloc(1,sizeof(ssymlist)));
    strcp((*lpom)->sym.name,sname);
    lpom=&(*lpom)->next;
    (*lpom)=0;
    if(istyp)
    {if(match(";"))break;
     if(match("=")){hasinit=1;break;}}   /* M6: var TYPE:name = expr; (initializer) */
    else
    {if(match(":"))break;}
    if(endst())break;
    if(!match(","))
    {
      error("',' or ':'|';' expected");
      junk();
      break;
    }
  }
  if(!istyp)
  {
    typ=gettypen();
    ns();
    k=gettsize(typ);
    comment();
    outstr("size:");
    outdec(k);
    nl();
    k=roundup(k);
    comment();
    outdec(k);
    nl();
  }
  for(lptr=lst;lptr;lptr=lptr->next)
  {
    idx=findloc(lptr->sym.name);
    /*fprintf(stderr,"adding %s\n",lptr->sym.name);*/
    if(idx)
    {
      error("local multidef");
    }
    idx=addloc(lptr->sym.name,S_VARL,1,Zsp-k,typ);
    if(wcnst)idx->cnst=1;   /* M6 const */
    /* mark int/pointer scalars for leaf-function register promotion; the marker
       (frame offset) is matched against CD_LDLW/STLW and CD_LEA in the post-pass */
    if((typ==T_INT)||(typ==T_UINT)||(typtab[typ].sort==V_PTR))zlocal(Zsp-k);
    Zsp=modstk(Zsp-k);
  }
  /*  while(symname(sname))
  {
    idx=findloc(sname);
    if(idx){
    error("local multidef");
    }
    addloc(sname,S_VARL,1,Zsp-k,typ);
    Zsp=modstk(Zsp-k);
    if(match(";"))break;
    if(endst())break;
    if(!match(","))
    {
      error("',' or ';' expected");
      junk();
      break;
    }
    }*/
  if(hasinit)
  {
    /* M6: var TYPE:name = expr;  -- emit the initializer as a direct store to the
       (last) declared variable. Below the comma operator so it stops at ';'.
       Stored directly (not via ct_ASSIGN), so a const local is initialized once
       here and rejected on any later assignment. idx is that last variable. */
    inode=hier1();
    foldtree(inode);
    if(treetocode(inode,&ilv))rvalue(&ilv);
    irt=ilv.typ;
    if(isfp(typ)&&!isfp(irt))i2f();
    else if(!isfp(typ)&&isfp(irt))zf2i();
    ilv.sort=L_ID;ilv.idx=idx;ilv.offset=0;ilv.typ=typ;strcp(ilv.name,idx->name);
    store(&ilv);
    delenode(inode);
    ns();
  }
  delsymlist(lst);
}
func doif()
{
  /*var int:flev;*/
  var **ssymlist:flev;
  var int:fsp;
  var int:flab1;
  var int:flab2;
  flev=locsymtab.front;
  /*flev=locptr;*/
  fsp=Zsp;
  flab1=getlabel();
  test(flab1);
  statemen();
  Zsp=modstk(fsp);
  /*locptr=flev;*/
  ssymtabcut(&locsymtab,flev);
  if(!amatch("else",4)){
  /*printlab(flab1);
  col();
  nl();*/
  clab(flab1);
  return ;
  }
  jump(flab2=getlabel());
  /*printlab(flab1);
  col();
  nl();*/
  clab(flab1);
  statemen();
  Zsp=modstk(fsp);
  /*locptr=flev;*/
  ssymtabcut(&locsymtab,flev);
  /*printlab(flab2);
  col();
  nl();
  */
  clab(flab2);
}
func test(label:int)
{
  needbrac(tlarg/*"("*/);
  expressi();
  needbrac(trarg/*")"*/);
  testjump(label);
}
func dobreak()
{
  var int:ptr;
  if(!wqptr)return ;
  ptr=readwhil();
  modstk(wqsp[ptr]);
  jump(wqlab[ptr]);
}
func docont()
{
  var int:ptr;
  if(!wqptr)return ;
  ptr=readwhil();
  modstk(wqsp[ptr]);
  jump(wqloop[ptr]);
}
func dofor()
{
  var **ssymlist:thesym;
  var int:thesp;
  var int:theloop,thecont;
  var int:thelab;
  var int:tl;
  /*thesym=locptr;*/
  thesym=locsymtab.front;
  thesp=Zsp;
  theloop=getlabel();
  thelab=getlabel();
  thecont=getlabel();
  addwhile(thesym,thesp,thecont,thelab);
  needbrac(tlarg/*"("*/);
  expressi();/* i=0 */
  ns();
  /*printlab(theloop);
  col();
  nl();*/
  clab(theloop);
  expressi();/* i<N */
  testjump(thelab);
  ns();
  /*fprintf(stderr,"dofor:ccg=%d\n",ccg);*/
  var *scodegen:savecg;
  savecg=ccg;
  /*fprintf(stderr,"dofor:savecg=%d\n",savecg);*/
  var scodegen:cg1;
  cg_init(&cg1);
  ccg=&cg1;
  tl=getlitst();
  /*printlab(thecont);col();nl();*/
  clab(thecont);
  blanks();
  if(!streq(line+lptr,trarg)/*ch()!=')'*/)
  expressi();/* i++ */
  var scodegen:cg2;
  cg_init(&cg2);
  ccg=&cg2;
  getlitst();
  needbrac(trarg/*")"*/);
  statemen();
  Zsp=modstk(thesp);
  /*cg_print(&cg2);*/
  cg_transfer(&cg2,savecg);
  cg_done(&cg2);
  /*cg_print(&cg1);*/
  cg_transfer(&cg1,savecg);
  cg_done(&cg1);
  ccg=savecg;
  dumpltst(tl);
  jump(theloop);
  /*printlab(thelab);
  col();
  nl();*/
  clab(thelab);
  /*locptr=thesym;*/
  ssymtabcut(&locsymtab,thesym);
  delwhile();
}
func dodo()
{
  var *ssymlist:thesym;
  var int:thesp;
  var int:theloop;
  var int:thelab;
  /*thesym=locptr;*/
  thesym=locsymtab.front;
  thesp=Zsp;
  theloop=getlabel();
  thelab=getlabel();
  addwhile(thesym,thesp,theloop,thelab);
  /*printlab(theloop);
  col();
  nl();*/
  clab(theloop);
  statemen();
  Zsp=modstk(thesp);
  if(!amatch("while",5)){
  error("'while' expected");
  }
  needbrac(tlarg/*"("*/);
  expressi();
  /*ol("testl %eax, %eax");
  ot("jne");
  tab();
  printlab(theloop);
  nl();*/
  testnejump(theloop);
  /*printlab(thelab);
  col();
  nl();*/
  clab(thelab);
  needbrac(trarg/*")"*/);
  ns();
  /*locptr=thesym;*/
  ssymtabcut(&locsymtab,thesym);
  delwhile();
}
func dowhile()
{
  var **ssymlist:thesym;
  var int:thesp;
  var int:theloop;
  var int:thelab;
  /*thesym=locptr;*/
  thesym=locsymtab.front;
  thesp=Zsp;
  theloop=getlabel();
  thelab=getlabel();
  addwhile(thesym,thesp,theloop,thelab);
  /*printlab(theloop);
  col();
  nl();*/
  clab(theloop);
  test(thelab);
  statemen();
  Zsp=modstk(thesp);
  jump(theloop);
  /*printlab(thelab);
  col();
  nl();*/
  clab(thelab);
  /*locptr=thesym;*/
  ssymtabcut(&locsymtab,thesym);
  delwhile();
}
/* switch(expr){ case C: ... break; ... default: ... }  -- C semantics including
   fall-through. Layout is dispatch-first: the switch value is evaluated once into
   a temp frame slot, then on entry we jump over the case bodies to a dispatch that
   compares the saved value against each (constant-expression) case label and jumps
   to the matching body; bodies fall through to one another and `break` jumps to the
   end. The compares reuse the ordinary `==` codegen (load/push/load/pop/eq), so the
   peephole and regspill passes treat them like any expression. break/continue use
   the existing loop queue (break -> end; continue -> enclosing loop). */
#define SWMAX 256
func doswitch()
{
  var **ssymlist:thesym;
  var int:thesp;
  var int:voff;var int:k;var int:rt;
  var int:endlab;var int:disp;var int:deflab;
  var int:i;var int:cont;
  var [SWMAX]int:cval;
  var [SWMAX]int:clb;
  var int:ncase;
  thesym=locsymtab.front;
  thesp=Zsp;
  endlab=getlabel();
  disp=getlabel();
  deflab=0;
  ncase=0;
  /* evaluate the controlling expression once, save it in a temp frame slot */
  needbrac(tlarg/*"("*/);
  rt=expressi();
  needbrac(trarg/*")"*/);
  if(rt==T_DOUBLE)zf2i();   /* switch on a double: truncate to int */
  k=roundup(gettsize(T_INT));
  voff=Zsp-k;
  zstlw(voff);
  Zsp=modstk(voff);
  /* break -> endlab (restores sp to thesp); continue -> enclosing loop's continue */
  if(wqptr>0)cont=wqloop[wqptr-1];
  else cont=endlab;
  addwhile(thesym,thesp,cont,endlab);
  jump(disp);               /* on entry, skip the bodies; run the dispatch */
  /* parse the body: emit case/default labels + statements, record (value,label) */
  needbrac(tlcomp/*"{"*/);
  while(!match(trcomp/*"}"*/))
  {
    blanks();
    if((!ch())&&iseof){error("unterminated switch");break;}
    if(amatch("case",4))
    {
      var int:cv;
      cv=constexpr("case value must be a constant integer");
      if(!match(":"))error("':' expected after case value");
      if(ncase>=SWMAX)error("too many case labels");
      else{cval[ncase]=cv;clb[ncase]=getlabel();clab(clb[ncase]);ncase=ncase+1;}
    }
    else if(amatch("default",7))
    {
      if(!match(":"))error("':' expected after default");
      if(deflab)error("duplicate default");
      else{deflab=getlabel();clab(deflab);}
    }
    else statemen();
  }
  Zsp=modstk(thesp);        /* end of body: restore sp, fall through to the end */
  jump(endlab);
  /* dispatch -- the saved value is at voff(%rbp); compares are balanced push/pops */
  clab(disp);
  Zsp=voff;                 /* runtime sp here is voff (entry subtracted to it) */
  for(i=0;i<ncase;i=i+1)
  {
    zldlw(voff);
    zpush();
    zldn(cval[i]);
    zpop();
    zeq();
    testnejump(clb[i]);
  }
  if(deflab)jump(deflab);
  else{Zsp=modstk(thesp);jump(endlab);}   /* no match, no default -> restore + exit */
  clab(endlab);
  Zsp=thesp;                /* every path reaches here with sp restored to thesp */
  ssymtabcut(&locsymtab,thesym);
  delwhile();
}
func addwhile(sym:int,sp:int,loop:int,lab:int)
{
  if(wqptr>=WQMAX){
  error("too many nested loops");
  return ;
  }
  wqsym[wqptr]=sym;
  wqsp[wqptr]=sp;
  wqloop[wqptr]=loop;
  wqlab[wqptr]=lab;
  wqptr++;
}
func readwhil()
{
  if(!wqptr){
  error("no active loops");
  return 0;
  }
  return wqptr-1;
}
func delwhile()
{
  if(wqptr>0)wqptr--;
}
func _zpush()
{
  ol("pushl %eax");
  Zsp=Zsp-4;
}
func _mult()
{
  ol("imull %edx");
}
func _zpop()
{
  ol("popl %edx");
  Zsp=Zsp+4;
}
func _zmod()
{
  div();
  ol("movl %edx, %eax");
}
func _div()
{
  ol("xchgl %eax, %edx");
  ol("movl %edx, %ecx");
  ol("cltd");
  ol("idivl %ecx");
}
func _increg(k:int)
{
  if(!k)return ;
  if(k<3)while(k--)ol("incl %eax");
  else
  {
    ot("addl $");
    outdec(k);
    outstr(", %eax");
    nl();
  }
}
func _decreg(k:int)
{
  if(!k)return ;
  if(k<3)while(k--)ol("decl %eax");
  else
  {
    ot("subl $");
    outdec(k);
    outstr(", %eax");
    nl();
  }
}
func _mulreg(k:int,s:*char)
{
  var int:l;
  if(k==1)return ;
  else
  if(k==0){
    ot("xorl ");
    outstr(s);
    outstr(", ");
    outstr(s);
    nl();
  }
  else
    {
    l=1;
    while(l<15)if(k==(1<<l)){
      ot("sall $");
      outdec(l);
      outstr(", ");
      outstr(s);
      nl();
      return ;
    }
    else
      l++;
    }
  ot("imull $");
  outdec(k);
  outstr(", ");
  outstr(s);
  nl();
}
func _divconst(k:int)
{
  var int:l;
  if(k==1)return ;
  if(!k){
  error("division by zero");
  return ;
  }
  l=1;
  while(l<15)if(k==(1<<l)){
  ot("sarl $");
  outdec(l);
  outstr(", %eax");
  nl();
  return ;
  }
  else
  l++;
  ol("cltd");
  ot("divl $");
  outdec(k);
  nl();
}
func _zadd()
{
  ol("addl %edx, %eax");
}
func _zsub()
{
  ol("subl %eax, %edx");
  ol("movl %edx, %eax");
}
func _neg()
{
  ol("negl %eax");
}
func _zeq()
{
  ot("cmpl");
  ot("%eax, %edx");
  nl();
  ot("sete");
  ot("%al");
  nl();
  ot("movzbl");
  ot("%al, %eax");
  nl();
}
func _zne()
{
  ot("cmpl");
  ot("%eax, %edx");
  nl();
  ot("setne");
  ot("%al");
  nl();
  ot("movzbl");
  ot("%al, %eax");
  nl();
}
func _zge()
{
  ot("cmpl");
  ot("%eax, %edx");
  nl();
  ot("setge");
  ot("%al");
  nl();
  ot("movzbl");
  ot("%al, %eax");
  nl();
}
func _uge()
{
  ot("cmpl");
  ot("%eax, %edx");
  nl();
  ot("setae");
  ot("%al");
  nl();
  ot("movzbl");
  ot("%al, %eax");
  nl();
}
func _ule()
{
  ot("cmpl");
  ot("%eax, %edx");
  nl();
  ot("setbe");
  ot("%al");
  nl();
  ot("movzbl");
  ot("%al, %eax");
  nl();
}
func _zle()
{
  ot("cmpl");
  ot("%eax, %edx");
  nl();
  ot("setle");
  ot("%al");
  nl();
  ot("movzbl");
  ot("%al, %eax");
  nl();
}
func _ult()
{
  ot("cmpl");
  ot("%eax, %edx");
  nl();
  ot("setb");
  ot("%al");
  nl();
  ot("movzbl");
  ot("%al, %eax");
  nl();
}
func _zlt()
{
  ot("cmpl");
  ot("%eax, %edx");
  nl();
  ot("setl");
  ot("%al");
  nl();
  ot("movzbl");
  ot("%al, %eax");
  nl();
}
func _ugt()
{
  ot("cmpl");
  ot("%eax, %edx");
  nl();
  ot("seta");
  ot("%al");
  nl();
  ot("movzbl");
  ot("%al, %eax");
  nl();
}
func _zgt()
{
  ot("cmpl");
  ot("%eax, %edx");
  nl();
  ot("setg");
  ot("%al");
  nl();
  ot("movzbl");
  ot("%al, %eax");
  nl();
}
func _zor()
{
  ol("orl %edx, %eax");
}
func _zxor()
{
  ol("xorl %edx, %eax");
}
func _zand()
{
  ol("andl %edx, %eax");
}
func _asr()
{
  ol("movl %eax, %ecx");
  ol("movl %edx, %eax");
  ol("sarl %cl, %eax");
}
func _asl()
{
  ol("movl %eax, %ecx");
  ol("movl %edx, %eax");
  ol("sall %cl, %eax");
}
func _lnot()
{
  ol("testl %eax,%eax");
  ol("sete %al");
  ol("movzbl %al, %eax");
}
func _bnot()
{
  ol("notl %eax");
}
func _testjump(label:int)
{
  ol("testl %eax, %eax");
  ot("je");
  tab();
  printlab(label);
  nl();
}
func _testnejump(label:int)
{
  ol("testl %eax, %eax");
  ot("jne");
  tab();
  printlab(label);
  nl();
}
func _jump(label:int)
{
  ot("jmp ");
  printlab(label);
  nl();
}
func _zcall(sname:*char)
{
  ot("call ");
  outname(sname);
  nl();
}
func inittarget()
{
  if(archsel==ARCH_X86_64)inittarget_x86_64();
  else if(archsel==ARCH_ARM64)inittarget_arm64();
  else if(archsel==ARCH_RISCV)inittarget_riscv();
  else if(archsel==ARCH_MIPS)inittarget_mips();
  else inittarget_i386();
}
/* ELF/GAS directives are shared by i386 and x86_64; only arch + word size
   (and, in icodegen, the register names) differ. */
func inittarget_elf()
{
  target.label_prefix=".L";
  target.sym_prefix="";
  target.dir_text=".text";
  target.dir_align=".align 16";
  target.dir_globl=".globl ";
  target.dir_type=".type";
  target.dir_func=",@function";
  target.dir_section=".section";
  target.dir_rodata=".rodata";
  target.bigendian=0;   /* little-endian default; mips overrides */
  target.strictalign=0; /* x86/arm64/riscv tolerate unaligned; mips overrides */
  target.nsavereg=3;    /* RG_B/RG_C/RG_E free for spills (i386 ebx/esi/edi) */
  target.directop=0;    /* backends opt in once their op lowerings use r2nd() */
  target.nlocalreg=0;   /* register-rich targets override; i386/mips have none */
}
/* round a data size/offset up to the alignment unit: a word on strict-alignment
   targets (mips faults on an unaligned ld/sd), else 4 as the i386 heritage. */
func roundup(n:int)
{
  var int:a;
  a=4;
  if(target.strictalign)a=target.wordsize;
  if(n&(a-1))n=n+a-(n&(a-1));
  return n;
}
func inittarget_i386()
{
  inittarget_elf();
  target.arch=ARCH_I386;
  target.wordsize=WORDSIZE;
  target.stackslot=WORDSIZE;
  target.nargreg=6;    /* i386 is cdecl (stack args); unused */
  target.directop=1;   /* op lowerings read the 2nd operand via r2nd() */
}
func inittarget_x86_64()
{
  inittarget_elf();
  target.arch=ARCH_X86_64;
  target.wordsize=8;   /* int==pointer==8 bytes (UPLNC's word model) */
  target.stackslot=8;
  target.nargreg=6;    /* SysV: %rdi..%r9 */
  target.directop=1;   /* op lowerings read the 2nd operand via r2nd() */
  target.nlocalreg=2;  /* %r10/%r11: free caller-saved (leaf local promotion) */
}
func inittarget_arm64()
{
  inittarget_elf();
  target.arch=ARCH_ARM64;
  target.wordsize=8;   /* AArch64 LP64: int==pointer==8 bytes */
  target.stackslot=16; /* sp must stay 16-byte aligned -> push 16 per word */
  target.nargreg=6;    /* AAPCS64 has x0..x7, but we use 6 (as on x86_64) */
  target.directop=1;   /* op lowerings read the 2nd operand via r2nd() */
  target.nlocalreg=2;  /* x11/x12: free caller-saved (leaf local promotion) */
}
func inittarget_riscv()
{
  inittarget_elf();
  target.arch=ARCH_RISCV;
  target.wordsize=8;   /* RV64 LP64: int==pointer==8 bytes */
  target.stackslot=8;  /* RISC-V doesn't fault on 8-byte sp pushes; the
                          pad-to-16-at-calls logic keeps the ABI alignment */
  target.nargreg=8;    /* a0..a7 -- FP args share these, so 6 isn't enough */
  target.nsavereg=3;   /* RG_B/RG_C/RG_E are t1/t2/t3, distinct from t0 scratch */
  target.directop=1;   /* op lowerings read the 2nd operand via r2nd() */
  target.nlocalreg=2;  /* t4/t5: free caller-saved (leaf local promotion) */
}
func inittarget_mips()
{
  inittarget_elf();
  target.arch=ARCH_MIPS;
  target.wordsize=8;   /* MIPS64 N64 LP64: int==pointer==8 bytes (big-endian) */
  target.stackslot=8;  /* like riscv: no sp-alignment fault; pad at calls */
  target.nargreg=8;    /* N64: $a0..$a7 ($4..$11) */
  target.dir_align=".align 3";  /* MIPS .align is power-of-2: 2^3 = 8-byte */
  target.bigendian=1;  /* MSB-first: shifts sub-word param offsets (see dofunc) */
  target.strictalign=1;/* ld/sd fault unless 8-aligned -> align all data to word */
  target.nsavereg=3;   /* RG_B/RG_C/RG_E are $14/$15/$24, distinct from scratch */
  target.directop=1;   /* op lowerings read the 2nd operand via r2nd() */
}
func printlab(label:int)
{
  outasm(target.label_prefix);
  outdec(label);
}
func indirect(lval:*int)
{
}

func pretree(node:*enode,ofil:*int)
{
  if(!node)
  return;
  fprintf(ofil,"(");
  pretree(node->l,ofil);
  if(node->op==OP_LEAF)
  {
    if(node->leaf.vid==L_NUM)
    fprintf(ofil,"%d",node->leaf.val);
    else if(node->leaf.vid==L_FNUM)
    fprintf(ofil,"%s",fpoolbuf+fpooloff[node->leaf.val]);
    else if(node->leaf.vid==L_STR)
    fprintf(ofil,"\"\"",litq+node->leaf.val);
    else if(node->leaf.vid==L_ID)
    fprintf(ofil,"%s",node->name);
    else
    error("unknown leaf");
  }
  else if(node->op==OP_LIST)
  {
    fprintf(ofil,"[]");
  }
  else if(node->op==OP_FUNC)
  {
    fprintf(ofil,"$");
  }
  else if(node->op==OP_COMMA)
  {
    fprintf(ofil,",");
  }
  else if(node->op==OP_COND)
  {
    fprintf(ofil,"?");
  }
  else if(node->op==OP_ASSIGN)
  {
    fprintf(ofil,"=");
  }
  else if(node->op==OP_EQ)
  {
    fprintf(ofil,"==");
  }
  else if(node->op==OP_NEQ)
  {
    fprintf(ofil,"!=");
  }
  else if(node->op==OP_GT)
  {
    fprintf(ofil,">");
  }
  else if(node->op==OP_LT)
  {
    fprintf(ofil,"<");
  }
  else if(node->op==OP_GE)
  {
    fprintf(ofil,">=");
  }
  else if(node->op==OP_LE)
  {
    fprintf(ofil,"<=");
  }
  else if(node->op==OP_SHL)
  {
    fprintf(ofil,"<<");
  }
  else if(node->op==OP_SHR)
  {
    fprintf(ofil,">>");
  }
  else if(node->op==OP_BAND)
  {
    fprintf(ofil,"&");
  }
  else if(node->op==OP_BOR)
  {
    fprintf(ofil,"|");
  }
  else if(node->op==OP_BXOR)
  {
    fprintf(ofil,"^");
  }
  else if(node->op==OP_LAND)
  {
    fprintf(ofil,"&&");
  }
  else if(node->op==OP_LOR)
  {
    fprintf(ofil,"||");
  }
  else if(node->op==OP_PLUS)
  {
    fprintf(ofil,"+");
  }
  else if(node->op==OP_MINUS)
  {
    fprintf(ofil,"-");
  }
  else if(node->op==OP_MUL)
  {
    fprintf(ofil,"*");
  }
  else if(node->op==OP_DIV)
  {
    fprintf(ofil,"/");
  }
  else if(node->op==OP_REM)
  {
    fprintf(ofil,"%");
  }
  else if(node->op==OP_1PP)
  {
    fprintf(ofil,"++@");
  }
  else if(node->op==OP_1MM)
  {
    fprintf(ofil,"--@");
  }
  else if(node->op==OP_UMINUS)
  {
    fprintf(ofil,"u-");
  }
  else if(node->op==OP_2PP)
  {
    fprintf(ofil,"@++");
  }
  else if(node->op==OP_2MM)
  {
    fprintf(ofil,"@--");
  }
  else if(node->op==OP_STAR)
  {
    fprintf(ofil,"*@");
  }
  else if(node->op==OP_ADDR)
  {
    fprintf(ofil,"&@");
  }
  else if(node->op==OP_BNOT)
  {
    fprintf(ofil,"~");
  }
  else if(node->op==OP_LNOT)
  {
    fprintf(ofil,"!");
  }
  else if(node->op==OP_DOT)
  {
    fprintf(ofil,".%s",node->name);
  }
  else error("unknown op");
  pretree(node->r,ofil);
  if(node->op==OP_COND)
  {
    fprintf(ofil,":");
    pretree(node->third,ofil);
  }
  fprintf(ofil,")");
}

func cttype(node:*enode)
{
  if(!node)return T_INT;
  if(node->op==OP_LEAF)
  {
    if(node->leaf.vid==L_NUM)
    return T_INT;
    else if(node->leaf.vid==L_FNUM)
    return T_DOUBLE;
    else if(node->leaf.vid==L_ID)
    return node->leaf.idx->type;
    else if(node->leaf.vid==L_STR)
    return T_CHARP;
  }
  else if(node->op==OP_STAR)
  {
    /* dereference / index: yield the element type of a ptr or array.
       cttype is a pure type oracle (no error(), no side effects) -- it is
       walked over arbitrary call-argument trees, so it must be total. */
    var int:t;
    t=cttype(node->r);
    if(typtab[t].sort==V_PTR||typtab[t].sort==V_ARR)
    return typtab[t].type;
    return T_INT;
  }
  else if(node->op==OP_ADDR)
  /* address-of yields a pointer -- never a double; T_INTP suffices for the
     only consumer (the FP-argument counter). Avoid getptrty (it mutates the
     type table and can error). */
  return T_INTP;
  else if(node->op==OP_FUNC)
  {
    /* a call yields the callee's return type, so a double-returning call used
       as an argument is itself routed through the FP path (slice 4b). */
    if(node->l&&(node->l->op==OP_LEAF)&&node->l->leaf.idx
       &&(node->l->leaf.idx->sort==S_FUNC))
    return node->l->leaf.idx->type;
    return T_INT;
  }
  else if(node->op==OP_PLUS||node->op==OP_MINUS||node->op==OP_MUL
       ||node->op==OP_DIV||node->op==OP_REM)
  {
    var int:t1,t2;
    t1=cttype(node->l);
    t2=cttype(node->r);
    if((t1==T_DOUBLE)||(t2==T_DOUBLE))return T_DOUBLE;
    if((typtab[t1].sort==V_PTR)||(typtab[t1].sort==V_ARR))return t1;
    if((typtab[t2].sort==V_PTR)||(typtab[t2].sort==V_ARR))return t2;
    return T_INT;
  }
  else if(node->op==OP_COND)
  return cttype(node->r);
  else if(node->op==OP_ASSIGN)
  return cttype(node->l);
  return T_INT;   /* default: treat as int (e.g. call results) */
}
func treetocode(node:*enode,lval:*elval)
{
  if(!node)
  return 0;
  if(node->op==OP_LEAF)
  {
    if(node->leaf.vid==L_NUM)
    {
      lval->sort=L_NUM;
      lval->idx=0;
      lval->offset=0;
      lval->typ=T_INT;
      lval->val=node->leaf.val;
      return 1;
    }
    else if(node->leaf.vid==L_FNUM)
    {
      lval->sort=L_FNUM;
      lval->idx=0;
      lval->offset=0;
      lval->typ=T_DOUBLE;
      lval->val=node->leaf.val;   /* float-pool index */
      return 1;
    }
    else if(node->leaf.vid==L_ID)
    {
      lval->sort=L_ID;
      lval->idx=node->leaf.idx;
      lval->offset=0;
      lval->typ=node->leaf.idx->type;
      strcp(lval->name,node->name);
      return 1;
    }
    else if(node->leaf.vid==L_STR)
    {
      lval->sort=L_STR;
      lval->idx=0;
      lval->offset=node->leaf.val;
      lval->typ=T_CHARP;
      return 1;
    }
    else
    error("how to code a leaf?");
  }
  else if(node->op==OP_COMMA)
  return ct_COMMA(node,lval);
  else if(node->op==OP_LOR)
  return ct_LOR(node,lval);
  else if(node->op==OP_LAND)
  return ct_LAND(node,lval);
  else if(node->op==OP_BOR)
  return ct_BOR(node,lval);
  else if(node->op==OP_BXOR)
  return ct_BXOR(node,lval);
  else if(node->op==OP_BAND)
  return ct_BAND(node,lval);
  else if(node->op==OP_EQ)
  return ct_EQ(node,lval);
  else if(node->op==OP_NEQ)
  return ct_NEQ(node,lval);
  else if(node->op==OP_GT)
  return ct_GT(node,lval);
  else if(node->op==OP_LT)
  return ct_LT(node,lval);
  else if(node->op==OP_GE)
  return ct_GE(node,lval);
  else if(node->op==OP_LE)
  return ct_LE(node,lval);
  else if(node->op==OP_SHL)
  return ct_SHL(node,lval);
  else if(node->op==OP_SHR)
  return ct_SHR(node,lval);
  else if(node->op==OP_PLUS)
  return ct_PLUS(node,lval);
  else if(node->op==OP_MINUS)
  return ct_MINUS(node,lval);
  else if(node->op==OP_ASSIGN)
  return ct_ASSIGN(node,lval);
  else if(node->op==OP_MUL)
  return ct_MUL(node,lval);
  else if(node->op==OP_DIV)
  return ct_DIV(node,lval);
  else if(node->op==OP_REM)
  return ct_REM(node,lval);
  else if(node->op==OP_1PP)
  return ct_1PP(node,lval);
  else if(node->op==OP_1MM)
  return ct_1MM(node,lval);
  else if(node->op==OP_2PP)
  return ct_2PP(node,lval);
  else if(node->op==OP_2MM)
  return ct_2MM(node,lval);
  else if(node->op==OP_UMINUS)
  return ct_UMINUS(node,lval);
  else if(node->op==OP_STAR)
  return ct_STAR(node,lval);
  else if(node->op==OP_ADDR)
  return ct_ADDR(node,lval);
  else if(node->op==OP_LNOT)
  return ct_LNOT(node,lval);
  else if(node->op==OP_BNOT)
  return ct_BNOT(node,lval);
  else if(node->op==OP_FUNC)
  return ct_FUNC(node,lval);
  else if(node->op==OP_DOT)
  return ct_DOT(node,lval);
  else if(node->op==OP_COND)
  return ct_COND(node,lval);
  else error("to be implemented");
}
func ct_COND(node:*enode,lval:*elval)
{
  /* c ? a : b  -- node->l = c, node->r = a, node->third = b */
  var elval:lc,la,lb;
  var int:elselab,exitlab;
  elselab=getlabel();
  exitlab=getlabel();
  if(treetocode(node->l,&lc))rvalue(&lc);   /* condition -> accumulator */
  testjump(elselab);                        /* if zero, take the else branch */
  if(treetocode(node->r,&la))rvalue(&la);   /* then  -> accumulator */
  jump(exitlab);
  clab(elselab);
  if(treetocode(node->third,&lb))rvalue(&lb);/* else -> accumulator */
  clab(exitlab);
  lval->sort=L_ONREG;
  lval->idx=0;
  lval->offset=0;
  lval->typ=la.typ;   /* result type taken from the 'then' branch */
  return 0;
}
func ct_COMMA(node:*enode,lval:*elval)
{
  var *enode:cnode;
  var int:k;
  var elval:lval1;
  for(cnode=node;cnode;cnode=cnode->r)
  {
    k=treetocode(cnode->l,&lval1);
    if(k)rvalue(&lval1);
    if(cnode->r&&cnode->r->op!=OP_COMMA)
      return treetocode(cnode->r,lval);
  }
}
/* whole-struct assignment  s1 = s2  (M6 2a). Both sides are struct lvalues --
   always an address (named struct variable or a struct sub-field). Copy the
   bytes word-by-word (byte tail if any) by reusing getmem/store on constructed
   scalar lvals at incrementing offsets, so no new opcode or pointer juggling is
   needed and it works on every backend. Through-pointer struct operands (L_POI)
   are left for later -- a clean error, not a miscompile. The result is the
   destination struct lvalue (so `s3 = s1 = s2` chains); return 0 so a statement
   does not try to rvalue a struct. */
func ct_structasgn(node:*enode,dst:*elval,lval:*elval)
{
  var elval:src;
  var elval:sw,dw;
  var int:n,off,ws;
  if((dst->sort!=L_ID)||(!dst->idx))
  {error("struct assignment target must be a named struct variable");return 0;}
  /* M6 2b: s = f(...) where f returns a struct -- have the callee write straight
     into s through its sret pointer (no temporary, no second copy). */
  if(node->r&&(node->r->op==OP_FUNC)&&node->r->l
     &&(node->r->l->op==OP_LEAF)&&node->r->l->leaf.idx
     &&(node->r->l->leaf.idx->sort==S_FUNC)
     &&(typtab[node->r->l->leaf.idx->type].sort==V_STR))
  {
    var elval:dummy;
    g_sretp=dst;
    treetocode(node->r,&dummy);   /* ct_FUNC sees g_sretp and writes into *dst */
    g_sretp=0;
    lval->sort=L_ID;lval->idx=dst->idx;lval->offset=dst->offset;lval->typ=dst->typ;
    return 0;
  }
  treetocode(node->r,&src);
  if(typtab[src.typ].sort!=V_STR)
  {error("struct assignment needs a struct on the right-hand side");return 0;}
  if((src.sort!=L_ID)||(!src.idx))
  {error("struct assignment source must be a named struct variable");return 0;}
  if(typtab[dst->typ].size!=typtab[src.typ].size)
  error("struct assignment between different-sized structs");
  n=typtab[dst->typ].size;
  ws=target.wordsize;
  off=0;
  /* a global load reads the symbol name from elval.name, a store from
     idx->name (existing asymmetry), so copy both into each word lval. */
  while(off+ws<=n)
  {
    sw.sort=L_ID;sw.idx=src.idx;strcp(sw.name,src.name);sw.offset=src.offset+off;sw.typ=T_INT;
    dw.sort=L_ID;dw.idx=dst->idx;strcp(dw.name,dst->name);dw.offset=dst->offset+off;dw.typ=T_INT;
    getmem(&sw);store(&dw);
    off=off+ws;
  }
  while(off<n)
  {
    sw.sort=L_ID;sw.idx=src.idx;strcp(sw.name,src.name);sw.offset=src.offset+off;sw.typ=T_CHAR;
    dw.sort=L_ID;dw.idx=dst->idx;strcp(dw.name,dst->name);dw.offset=dst->offset+off;dw.typ=T_CHAR;
    getmem(&sw);store(&dw);
    off=off+1;
  }
  lval->sort=L_ID;lval->idx=dst->idx;lval->offset=dst->offset;lval->typ=dst->typ;
  return 0;
}
func ct_ASSIGN(node:*enode,lval:*elval)
{
  var int:k;
  var elval:lval1,lval2;
  k=treetocode(node->l,&lval1);
  if(!k){needlval();return 0;}
  /* M6 const: reject assigning to a const variable (directly, by name -- a write
     *through* a const pointer, `*p = x`, is L_POI and stays allowed). */
  if((lval1.sort==L_ID)&&lval1.idx&&lval1.idx->cnst)
  error("assignment to a const variable");
  if(typtab[lval1.typ].sort==V_STR)
  return ct_structasgn(node,&lval1,lval);   /* M6 2a: whole-struct copy */
  if(lval1.sort==L_POI)
  {
    zpush();
    lval1.sort=L_SP;
  }
  if(treetocode(node->r,&lval2))rvalue(&lval2);
  /* convert the RHS (in the accumulator) to the target's class (M4). A float
     destination wants a double in %xmm0 here -- the store then narrows it. */
  if(isfp(lval1.typ)&&!isfp(lval2.typ))i2f();    /* int -> double */
  else if(!isfp(lval1.typ)&&isfp(lval2.typ))zf2i();/* double -> int */
  lval->sort=L_ONREG;
  lval->idx=0;
  lval->offset=0;
  lval->typ=lval1.typ;   /* assigned value is now the target type */
  store(&lval1);
  return 0;
}
func ct_LOR(node:*enode,lval:*elval)
{
  var elval:lval1,lval2;
  var *enode:cnode;
  var int:onelab,exitlab;
  if(treetocode(node->l,&lval1))rvalue(&lval1);
  onelab=getlabel();
  exitlab=getlabel();
  testnejump(onelab);
  cnode=node->r;
  while(cnode->op==OP_LOR)
  {
    if(treetocode(cnode->l,&lval1))rvalue(&lval1);
    testnejump(onelab);
    cnode=cnode->r;
  }
  if(treetocode(cnode,&lval2))rvalue(&lval2);
  testnejump(onelab);
  /*ol("xorl %eax, %eax");*/
  zldn(0);
  jump(exitlab);
  /*printlab(onelab);col();nl();*/
  clab(onelab);
  /*ol("movl $1, %eax");*/
  zldn(1);
  /*printlab(exitlab);col();nl();*/
  clab(exitlab);
  lval->sort=L_ONREG;
  lval->idx=0;
  lval->offset=0;
  lval->typ=T_INT;
  return 0;
}
func ct_LAND(node:*enode,lval:*elval)
{
  var elval:lval1,lval2;
  var *enode:cnode;
  var int:zerolab,exitlab;
  if(treetocode(node->l,&lval1))rvalue(&lval1);
  zerolab=getlabel();
  exitlab=getlabel();
  testjump(zerolab);
  cnode=node->r;
  while(cnode->op==OP_LAND)
  {
    if(treetocode(cnode->l,&lval1))rvalue(&lval1);
    testjump(zerolab);
    cnode=cnode->r;
  }
  if(treetocode(cnode,&lval2))rvalue(&lval2);
  testjump(zerolab);
  /*ol("movl $1, %eax");*/
  zldn(1);
  jump(exitlab);
  /*printlab(zerolab);col();nl();*/
  clab(zerolab);
  /*ol("xorl %eax, %eax");*/
  zldn(0);
  /*printlab(exitlab);col();nl();*/
  clab(exitlab);
  lval->sort=L_ONREG;
  lval->idx=0;
  lval->offset=0;
  lval->typ=T_INT;
  return 0;
}
func ct_BOR(node:*enode,lval:*elval)
{
  var elval:lval1,lval2;
  if(treetocode(node->l,&lval1))rvalue(&lval1);
  zpush();
  if(treetocode(node->r,&lval2))rvalue(&lval2);
  zpop();
  zor();
  lval->sort=L_ONREG;
  lval->idx=0;
  lval->offset=0;
  lval->typ=uresult(lval1.typ,lval2.typ);
  return 0;
}
func ct_BXOR(node:*enode,lval:*elval)
{
  var elval:lval1,lval2;
  if(treetocode(node->l,&lval1))rvalue(&lval1);
  zpush();
  if(treetocode(node->r,&lval2))rvalue(&lval2);
  zpop();
  zxor();
  lval->sort=L_ONREG;
  lval->idx=0;
  lval->offset=0;
  lval->typ=uresult(lval1.typ,lval2.typ);
  return 0;
}
func ct_BAND(node:*enode,lval:*elval)
{
  var elval:lval1,lval2;
  if(treetocode(node->l,&lval1))rvalue(&lval1);
  zpush();
  if(treetocode(node->r,&lval2))rvalue(&lval2);
  zpop();
  zand();
  lval->sort=L_ONREG;
  lval->idx=0;
  lval->offset=0;
  lval->typ=uresult(lval1.typ,lval2.typ);
  return 0;
}
func ct_EQ(node:*enode,lval:*elval)
{
  var elval:lval1,lval2;
  if(treetocode(node->l,&lval1))rvalue(&lval1);
  zpush();
  if(treetocode(node->r,&lval2))rvalue(&lval2);
  zpop();
  zeq();
  lval->sort=L_ONREG;
  lval->idx=0;
  lval->offset=0;
  lval->typ=T_INT;
  return 0;
}
func ct_NEQ(node:*enode,lval:*elval)
{
  var elval:lval1,lval2;
  if(treetocode(node->l,&lval1))rvalue(&lval1);
  zpush();
  if(treetocode(node->r,&lval2))rvalue(&lval2);
  zpop();
  zne();
  lval->sort=L_ONREG;
  lval->idx=0;
  lval->offset=0;
  lval->typ=T_INT;
  return 0;
}
func ct_GT(node:*enode,lval:*elval)
{
  var elval:lval1,lval2;
  if(treetocode(node->l,&lval1))rvalue(&lval1);
  zpush();
  if(treetocode(node->r,&lval2))rvalue(&lval2);
  zpop();
  if(!issigned(lval1.typ)||!issigned(lval2.typ))
  ugt();
  else
  zgt();

  lval->sort=L_ONREG;
  lval->idx=0;
  lval->offset=0;
  lval->typ=T_INT;
  return 0;
}
func ct_LT(node:*enode,lval:*elval)
{
  var elval:lval1,lval2;
  if(treetocode(node->l,&lval1))rvalue(&lval1);
  zpush();
  if(treetocode(node->r,&lval2))rvalue(&lval2);
  zpop();
  if(!issigned(lval1.typ)||!issigned(lval2.typ))
  ult();
  else
  zlt();

  lval->sort=L_ONREG;
  lval->idx=0;
  lval->offset=0;
  lval->typ=T_INT;
  return 0;
}
func ct_GE(node:*enode,lval:*elval)
{
  var elval:lval1,lval2;
  if(treetocode(node->l,&lval1))rvalue(&lval1);
  zpush();
  if(treetocode(node->r,&lval2))rvalue(&lval2);
  zpop();
  if(!issigned(lval1.typ)||!issigned(lval2.typ))
  uge();
  else
  zge();

  lval->sort=L_ONREG;
  lval->idx=0;
  lval->offset=0;
  lval->typ=T_INT;
  return 0;
}
func ct_LE(node:*enode,lval:*elval)
{
  var elval:lval1,lval2;
  if(treetocode(node->l,&lval1))rvalue(&lval1);
  zpush();
  if(treetocode(node->r,&lval2))rvalue(&lval2);
  zpop();
  if(!issigned(lval1.typ)||!issigned(lval2.typ))
  ule();
  else
  zle();

  lval->sort=L_ONREG;
  lval->idx=0;
  lval->offset=0;
  lval->typ=T_INT;
  return 0;
}
func ct_SHL(node:*enode,lval:*elval)
{
  var elval:lval1,lval2;
  if(treetocode(node->l,&lval1))rvalue(&lval1);
  zpush();
  if(treetocode(node->r,&lval2))rvalue(&lval2);
  zpop();
  asl();
  lval->sort=L_ONREG;
  lval->idx=0;
  lval->offset=0;
  if(lval1.typ==T_UINT)lval->typ=T_UINT;else lval->typ=T_INT;   /* result keeps the shifted value's type */
  return 0;
}
func ct_SHR(node:*enode,lval:*elval)
{
  var elval:lval1,lval2;
  if(treetocode(node->l,&lval1))rvalue(&lval1);
  zpush();
  if(treetocode(node->r,&lval2))rvalue(&lval2);
  zpop();
  lval->sort=L_ONREG;
  lval->idx=0;
  lval->offset=0;
  if(lval1.typ==T_UINT){shr();lval->typ=T_UINT;}   /* logical shift for an unsigned value */
  else{asr();lval->typ=T_INT;}                       /* arithmetic shift (signed) */
  return 0;
}
func ct_MINUS(node:*enode,lval:*elval)
{
  var elval:lval1,lval2;
  var int:isptr;
  isptr=0;
  if(treetocode(node->l,&lval1))rvalue(&lval1);
  if(lval1.typ==T_DOUBLE)fpush();else zpush();
  if(treetocode(node->r,&lval2))rvalue(&lval2);
  if(fparith(&lval1,&lval2,CD_FSUB))
  {lval->sort=L_ONREG;lval->idx=0;lval->offset=0;lval->typ=T_DOUBLE;return 0;}
  zpop();
  lval->sort=L_ONREG;
  lval->idx=0;
  lval->offset=0;
  lval->typ=uresult(lval1.typ,lval2.typ);
  if(typtab[lval1.typ].sort==V_PTR||
   typtab[lval1.typ].sort==V_ARR)
  {
    if(typtab[lval2.typ].sort==V_PTR||
     typtab[lval2.typ].sort==V_ARR)
    {
      zsub();
      if(typtab[lval1.typ].type!=typtab[lval2.typ].type)
      error("subtracting pointers of different types");
      divconst(gettsize(typtab[lval1.typ].type));
      isptr=0;/*?*/
      lval->typ=T_INT;/*?*/
    }
    else
    {
      mulreg(gettsize(typtab[lval1.typ].type),/*"%eax"*/RG_A);
      zsub();
      lval->typ=lval1.typ;
    }
  }
  else
  {
    if(typtab[lval2.typ].sort==V_PTR||
     typtab[lval2.typ].sort==V_ARR)
    error("subtracting a pointer");
    zsub();
  }
  return 0;/*on register*/
}
func ct_PLUS(node:*enode,lval:*elval)
{
  var elval:lval1,lval2;
  var int:isptr;
  isptr=0;
  if(treetocode(node->l,&lval1))rvalue(&lval1);
  if(lval1.typ==T_DOUBLE)fpush();else zpush();
  if(treetocode(node->r,&lval2))rvalue(&lval2);
  lval->sort=L_ONREG;
  lval->idx=0;
  lval->offset=0;
  if(fparith(&lval1,&lval2,CD_FADD)){lval->typ=T_DOUBLE;return 0;}
  lval->typ=uresult(lval1.typ,lval2.typ);
  if(typtab[lval1.typ].sort==V_PTR||
   typtab[lval1.typ].sort==V_ARR)
  {
    mulreg(gettsize(typtab[lval1.typ].type),/*"%eax"*/RG_A);
    isptr=1;
    lval->typ=lval1.typ;
  }
  zpop();
  if(typtab[lval2.typ].sort==V_PTR||
   typtab[lval2.typ].sort==V_ARR)
  {
    if(isptr)error("cannot add pointer to pointer");
    mulreg(gettsize(typtab[lval2.typ].type),/*"%edx"*/RG_D);
    isptr=1;/*legacy?*/
    lval->typ=lval2.typ;
  }
  zadd();
  return 0;/*on register*/
}
/* M4: if either operand is double, finish a binary op as FP (xmm) and return 1;
   else return 0 (the caller does the integer path). The left operand must
   already have been pushed with fpush when it is double (see callers). */
func fparith(l1:*elval,l2:*elval,op:int)
{
  if((l1->typ==T_DOUBLE)||(l2->typ==T_DOUBLE))
  {
    /* right operand is in the accumulator: promote it if it is an int */
    if(l2->typ!=T_DOUBLE)i2f();        /* (double)%rax -> %xmm0 */
    /* left operand is on the stack (fpush if double, zpush if int) */
    if(l1->typ==T_DOUBLE)fpop();       /* double -> %xmm1 */
    else{zpop();i2f1();}               /* int -> %rdx -> (double)%xmm1 */
    fbinop(op);
    return 1;
  }
  return 0;
}
func ct_MUL(node:*enode,lval:*elval)
{
  var elval:lval1,lval2;
  if(treetocode(node->l,&lval1))rvalue(&lval1);
  if(lval1.typ==T_DOUBLE)fpush();else zpush();
  if(treetocode(node->r,&lval2))rvalue(&lval2);
  lval->sort=L_ONREG;
  lval->idx=0;
  lval->offset=0;
  if(fparith(&lval1,&lval2,CD_FMUL)){lval->typ=T_DOUBLE;return 0;}
  zpop();
  mult();
  lval->typ=uresult(lval1.typ,lval2.typ);
  return 0;
}
func ct_DIV(node:*enode,lval:*elval)
{
  var elval:lval1,lval2;
  if(treetocode(node->l,&lval1))rvalue(&lval1);
  if(lval1.typ==T_DOUBLE)fpush();else zpush();
  if(treetocode(node->r,&lval2))rvalue(&lval2);
  lval->sort=L_ONREG;
  lval->idx=0;
  lval->offset=0;
  if(fparith(&lval1,&lval2,CD_FDIV)){lval->typ=T_DOUBLE;return 0;}
  zpop();
  if((lval1.typ==T_UINT)||(lval2.typ==T_UINT)){udiv();lval->typ=T_UINT;}
  else{div();lval->typ=T_INT;}
  return 0;
}
func ct_REM(node:*enode,lval:*elval)
{
  var elval:lval1,lval2;
  if(treetocode(node->l,&lval1))rvalue(&lval1);
  zpush();
  if(treetocode(node->r,&lval2))rvalue(&lval2);
  zpop();
  lval->sort=L_ONREG;
  lval->idx=0;
  lval->offset=0;
  if((lval1.typ==T_UINT)||(lval2.typ==T_UINT)){umod();lval->typ=T_UINT;}
  else{zmod();lval->typ=T_INT;}
  return 0;
}
/* M6 const: reject ++/-- that targets a const variable by name (a const pointer
   may still be dereferenced-and-modified, *p++ etc., since that is L_POI). */
func chkconst(lval:*elval)
{
  if((lval->sort==L_ID)&&lval->idx&&lval->idx->cnst)
  error("modifying a const variable");
}
func ct_1PP(node:*enode,lval:*elval)
{
  var int:k,sz;
  k=treetocode(node->r,lval);
  if(!k){needlval();return 0;}
  chkconst(lval);
  if(lval->sort==L_POI)
  {
    zpush();
    rvalue(lval);
    lval->sort=L_SP;
  }
  else rvalue(lval);
  if(typtab[lval->typ].sort==V_PTR)
  sz=gettsize(typtab[lval->typ].type);
  else sz=1;
  increg(sz);
  store(lval);
  lval->sort=L_ONREG;
  lval->idx=0;
  lval->offset=0;
  return 0;
}
func ct_1MM(node:*enode,lval:*elval)
{
  var int:k,sz;
  k=treetocode(node->r,lval);
  if(!k){needlval();return 0;}
  chkconst(lval);
  if(lval->sort==L_POI)
  {
    zpush();
    rvalue(lval);
    lval->sort=L_SP;
  }
  else rvalue(lval);
  if(typtab[lval->typ].sort==V_PTR)
  sz=gettsize(typtab[lval->typ].type);
  else sz=1;
  decreg(sz);
  store(lval);
  lval->sort=L_ONREG;
  lval->idx=0;
  lval->offset=0;
  return 0;
}
func ct_2PP(node:*enode,lval:*elval)
{
  var int:k,sz;
  k=treetocode(node->r,lval);
  if(!k){needlval();return 0;}
  chkconst(lval);
  if(lval->sort==L_POI)
  {
    zpush();
    rvalue(lval);
    lval->sort=L_SP;
  }
  else rvalue(lval);
  if(typtab[lval->typ].sort==V_PTR)
  sz=gettsize(typtab[lval->typ].type);
  else sz=1;
  increg(sz);
  store(lval);
  decreg(sz);
  lval->sort=L_ONREG;
  lval->idx=0;
  lval->offset=0;
  return 0;
}
func ct_2MM(node:*enode,lval:*elval)
{
  var int:k,sz;
  k=treetocode(node->r,lval);
  if(!k){needlval();return 0;}
  chkconst(lval);
  if(lval->sort==L_POI)
  {
    zpush();
    rvalue(lval);
    lval->sort=L_SP;
  }
  else rvalue(lval);
  if(typtab[lval->typ].sort==V_PTR)
  sz=gettsize(typtab[lval->typ].type);
  else sz=1;
  decreg(sz);
  store(lval);
  increg(sz);
  lval->sort=L_ONREG;
  lval->idx=0;
  lval->offset=0;
  return 0;
}
func ct_UMINUS(node:*enode,lval:*elval)
{
  var int:k;
  k=treetocode(node->r,lval);
  if(k)rvalue(lval);
  neg();
  lval->sort=L_ONREG;
  lval->idx=0;
  lval->offset=0;
  return 0;
}
func ct_STAR(node:*enode,lval:*elval)
{
  var int:k;
  k=treetocode(node->r,lval);
  if(lval->sort==L_ID||lval->sort!=L_STR)
  {
    if(typtab[lval->typ].sort!=V_ARR&&typtab[lval->typ].sort!=V_PTR)
    {error("need a pointer");return k;}
    if(k)rvalue(lval);
    lval->sort=L_POI;
    lval->typ=typtab[lval->typ].type;
    lval->offset=0;
    return 1;
  }
  else if(lval->sort==L_STR)
  {
    if(k)rvalue(lval);
    lval->sort=L_POI;
    lval->typ=T_CHAR;
    lval->offset=0;
    return 1;
  }
  else{error("error with *pointe");return 0;}
}
func ct_ADDRDIR(node:*enode,lval:*elval)
{
  var int:k;
  k=treetocode(node,lval);
  if(lval->sort==L_ID&&lval->idx)
  {
    if(lval->idx->sort==S_VARG)
    {
      /*ot("movl $");
      outname(lval->idx->name);
      if(lval->offset)
      {outasm("+");outdec(lval->offset);}
      outasm(", %eax");
      nl();*/
      zlda(lval->idx->name,lval->offset);
    }
    else if(lval->idx->sort==S_VARL)
    {
      /*ot("leal ");
      outdec(lval->idx->offset+lval->offset);
      outasm("(%ebp), %eax");
      nl();*/
      zlea(lval->idx->offset+lval->offset);
    }
    else if(lval->idx->sort==S_FUNC)
    {
      error("address of function: to be implemented");
    }
    else error("error taking address");
  }
  else if(lval->sort==L_NUM)
  error("how to take the address of a number?");
  else if(lval->sort==L_STR)
  {
    loadlita(lval);
  }
  else if(lval->sort==L_POI)
  {
    if(lval->offset)
    {
      increg(lval->offset);
      lval->offset=0;
    }
  }
  else error("error after &");
  lval->typ=getptrty(lval->typ);
  return 0;
}
func ct_ADDR(node:*enode,lval:*elval)
{
  var int:k;
  return ct_ADDRDIR(node->r,lval);
  k=treetocode(node->r,lval);
  if(lval->sort==L_ID&&lval->idx)
  {
    if(lval->idx->sort==S_VARG)
    {
      /*ot("movl $");
      outname(lval->idx->name);
      if(lval->offset)
      {outasm("+");outdec(lval->offset);}
      outasm(", %eax");
      nl();*/
      zlda(lval->idx->name,lval->offset);
    }
    else if(lval->idx->sort==S_VARL)
    {
      /*ot("leal ");
      outdec(lval->idx->offset+lval->offset);
      outasm("(%ebp), %eax");
      nl();*/
      zlea(lval->idx->offset+lval->offset);
    }
    else if(lval->idx->sort==S_FUNC)
    {
      error("address of function: to be implemented");
    }
    else error("error taking address");
  }
  else if(lval->sort==L_NUM)
  error("how to take the address of a number?");
  else if(lval->sort==L_STR)
  {
    loadlita(lval);
  }
  else if(lval->sort==L_POI)
  {
    if(lval->offset)
    {
      increg(lval->offset);
      lval->offset=0;
    }
  }
  else error("error after &");
  lval->typ=getptrty(lval->typ);
  return 0;
}
func ct_LNOT(node:*enode,lval:*elval)
{
  var int:k;
  k=treetocode(node->r,lval);
  if(k)rvalue(lval);
  lnot();
  lval->sort=L_ONREG;
  lval->idx=0;
  lval->offset=0;
  lval->typ=T_INT;/*logical*/
  return 0;
}
func ct_BNOT(node:*enode,lval:*elval)
{
  var int:k;
  k=treetocode(node->r,lval);
  if(k)rvalue(lval);
  bnot();
  lval->sort=L_ONREG;
  lval->idx=0;
  lval->offset=0;
  return 0;
}
func ct_FUNC(node:*enode,lval:*elval)
{
  var int:k;
  var elval:lval1,lval2;
  var *enode:l,r;
  l=node->l;
  if(l&&((l->op==OP_LEAF&&l->leaf.vid==L_ID
   &&l->leaf.idx
   &&l->leaf.idx->sort==S_FUNC)
     ))
  {
    var int:nargs;
    var int:structret;var *elval:sretp;
    r=node->r;
    nargs=0;
    /* M6 2b: struct-returning call -- pass &dst (captured in g_sretp by the
       `s = f()` handler) as a hidden sret pointer, pushed first so it lands in
       the last argument slot, matching the callee's last (sret) parameter. */
    structret=0;sretp=0;
    if(l->leaf.idx&&(typtab[l->leaf.idx->type].sort==V_STR))
    {
      if(!g_sretp)error("a struct-returning call's result must be captured by a struct assignment (s = f(...)); it cannot be used directly here");
      else{structret=1;sretp=g_sretp;g_sretp=0;}
    }
    if(target.arch!=ARCH_I386)   /* x86_64 / arm64 / riscv: register convention */
    {
      var int:savezsp;var int:cnt;var *enode:rr;var int:pad;var int:nstack;
      var int:cfp;var int:cint;var int:ireg;var int:freg;var int:i;var int:j;
      var [32]int:atypes;
      savezsp=Zsp;
      cnt=0;rr=r;while(rr){cnt++;rr=rr->r;}
      cfp=0;rr=r;while(rr){if(isfp(cttype(rr->l)))cfp=cfp+1;rr=rr->r;}
      if(structret&&(cfp>0))error("struct return with floating-point arguments not supported yet");
      if(structret)cnt=cnt+1;   /* the hidden sret pointer is an extra argument */
      /* the sret pointer must land in a register (matching the callee's last
         param); if the args overflow past the argument registers it would spill
         to the stack at an offset the callee does not expect -- reject cleanly. */
      if(structret&&(cnt>target.nargreg))error("a struct-returning call with this many arguments is not supported yet");
      /* RISC-V and MIPS pass FP args as raw bits in the *integer* registers (the
         variadic convention -- what printf reads), so they take the integer path
         below; only x86_64/arm64 use the separate FP-register marshaling. A
         struct-returning call always takes the integer path. */
      if((cfp>0)&&(!structret)&&(target.arch!=ARCH_RISCV)&&(target.arch!=ARCH_MIPS))
      {
        /* FP marshaling: doubles -> %xmm0../d0.., ints/ptrs -> %rdi../x0..
           (slot offsets use stackslot: 8 on x86_64, 16 on arm64). On arm64 the
           %al count is ignored -- AAPCS64 needs no vector-register count. */
        cint=cnt-cfp;
        if(cint>6)error(">6 integer args alongside floats");
        if(cfp>8)error(">8 floating-point args");
        pad=(((Zsp-cnt*target.stackslot)%16)+16)%16;
        if(pad)Zsp=modstk(Zsp-pad);
        j=cnt-1;rr=r;
        while(rr){k=treetocode(rr->l,&lval2);if(k)rvalue(&lval2);
          if(isfp(lval2.typ))fpush();else zpush();
          atypes[j]=lval2.typ;j=j-1;rr=rr->r;}
        ireg=0;freg=0;
        for(i=0;i<cnt;i++)
        {
          if(isfp(atypes[i])){margfp(i*target.stackslot,freg);freg=freg+1;}
          else{margint(i*target.stackslot,ireg);ireg=ireg+1;}
        }
        zcall(l->leaf.idx->name,freg);   /* %al = #xmm regs (x86_64 varargs) */
        Zsp=modstk(savezsp);
      }
      else
      {
        /* stackslot == wordsize except on arm64 (16), where each pushed arg
           occupies a 16-byte slot so sp stays aligned -- so the alignment pad
           is always 0 there and the marshal/cleanup byte counts match. */
        nstack=cnt-target.nargreg;if(nstack<0)nstack=0;
        if(cnt>target.nargreg)pad=(((Zsp-nstack*target.stackslot)%16)+16)%16;
        else pad=(((Zsp-cnt*target.stackslot)%16)+16)%16;
        if(pad)Zsp=modstk(Zsp-pad);
        /* push each arg; a double on riscv is fpush'd as raw bits (fsd) so the
           integer marshal ld's it into the arg register. On x86_64/arm64 there
           are no FP args here (cfp==0), so this is the plain integer push. */
        if(structret)pushaddr(sretp);   /* sret pointer pushed first (deepest) */
        while(r){k=treetocode(r->l,&lval2);if(k)rvalue(&lval2);
          if(isfp(lval2.typ))fpush();else zpush();r=r->r;}
        if(cnt>target.nargreg){marshal(target.nargreg);Zsp=modstk(Zsp+target.nargreg*target.stackslot);}
        else marshal(cnt);
        zcall(l->leaf.idx->name,0);
        Zsp=modstk(savezsp);
      }
    }
    else
    {
    if(structret){pushaddr(sretp);nargs=nargs+target.wordsize;}   /* sret first (deepest) */
    while(r)
    {
      k=treetocode(r->l,&lval2);
      if(k)rvalue(&lval2);
      /* i386 cdecl: a double is passed as 8 bytes on the stack -- fpush pops the
         x87 accumulator (st0) into the slot. Ints/pointers are the usual 4-byte
         push. A float argument has already decayed to a double in st0. */
      if(isfp(lval2.typ)){fpush();nargs=nargs+8;}
      else{zpush();nargs=nargs+target.wordsize;}
      r=r->r;
    }
    zcall(l->leaf.idx->name,0);
    Zsp=modstk(Zsp+nargs);
    }
  }
  else if(l&&l->op==OP_DOT)
  {
    /*error("calling of method: to be constructed");*/
    var int:nargs;
    r=node->r;
    nargs=0;
    var int:savezsp2;var int:cnt2;var *enode:rr2;var int:pad2;
    if(target.arch!=ARCH_I386)
    {
      savezsp2=Zsp;
      cnt2=1;rr2=r;while(rr2){cnt2++;rr2=rr2->r;}   /* explicit args + this */
      if(cnt2>target.nargreg)pad2=(((Zsp-(cnt2-target.nargreg)*target.stackslot)%16)+16)%16;
      else pad2=(((Zsp-cnt2*target.stackslot)%16)+16)%16;
      if(pad2)Zsp=modstk(Zsp-pad2);
    }
    while(r)
    {
      k=treetocode(r->l,&lval2);
      if(k)rvalue(&lval2);
      /* methods marshal args as integers on both targets; a floating-point
         method argument would push a stale accumulator -- reject it cleanly. */
      if(isfp(lval2.typ))
      error("floating-point method arguments not supported yet");
      zpush();
      nargs=nargs+target.wordsize;
      r=r->r;
    }
    /*zcall(l->leaf.idx->name);*/
    /*fprintf(stderr,"tree:");*/
    /*pretree(l->l,stderr);fprintf(stderr,"\n");*/
    k=ct_ADDRDIR(l->l,&lval2);
    /*fprintf(stderr,"lval2.sort=%d,offset=%d,typ=%d\n",
    lval2.sort,lval2.offset,lval2.typ);*/
    if(typtab[lval2.typ].sort!=V_PTR)
    {
      error("should be pointer...");
      fprintf(stderr,"typtab[lval2.typ]=%d\n",
          typtab[lval2.typ].sort);
    }
    if(typtab[typtab[lval2.typ].type].sort!=V_STR)
    {
      error("methods are for structures...\n");
    }
    if(k)rvalue(&lval2);
    zpush();
    nargs=nargs+target.wordsize;
    var [NAMESIZE]char:methodname;
    strcp(methodname,typtab[typtab[lval2.typ].type].name);
    strcat(strcat(methodname,"."),l->name);/* DANGEROUS!!! FixMe! */
    cnmlst->addm(methodname);
    if(target.arch!=ARCH_I386)
    {
      if(cnt2>target.nargreg){marshal(target.nargreg);Zsp=modstk(Zsp+target.nargreg*target.stackslot);}
      else marshal(cnt2);
      zcall(methodname,0);
      Zsp=modstk(savezsp2);
    }
    else
    {
      zcall(methodname,0);
      Zsp=modstk(Zsp+nargs);
    }
  }
  else
  {
    error("function by ptr needs to be implemented");
    fprintf(stderr,
        "l->op=%d,l->leaf.vid=%d\n",
        l->op,l->leaf.vid);
  }
  lval->sort=L_ONREG;
  lval->idx=0;
  lval->offset=0;
  lval->typ=T_INT;/*the result*/
  /* propagate the callee's declared return type to the call expression, so
     pointer- and char-returning functions are type-correct at the call site --
     *f(), f()->m, f()[i], f()+n all work, matching cttype() which already
     returns this type. A `:double` return still routes through %xmm0 (M4 slice
     4b); a plain (int) function is unchanged. Struct returns are not yet
     supported (separate work), so leave a V_STR result as int here. The compiler
     declares no return types, so its own calls all stay int and the self-host
     fixpoints are byte-identical. */
  if(l&&(l->op==OP_LEAF)&&l->leaf.idx&&(l->leaf.idx->sort==S_FUNC)
     &&(typtab[l->leaf.idx->type].sort!=V_STR))
  lval->typ=l->leaf.idx->type;
  return 0;
}
func ct_DOT(node:*enode,lval:*elval)
{
  var int:k,i;
  /*var elval:lval1,lval2;*/
  k=treetocode(node->l,lval);
  if(!k)
  {error("bizarre to '.' something on register");return k;}
  if(typtab[lval->typ].sort!=V_STR)
  {error("'.' is for structures");return k;}
  i=findfiel(node->name,lval->typ);
  if(!i)
  {error("no such field");prstrct(lval->typ);return k;}
  lval->typ=fieldtab[i].type;
  lval->offset=lval->offset+fieldtab[i].offset;
  return k;
}
func loadlita(lval:*elval)
{
  /*ot("movl $");
  printlab(stlab);
  outstr("+");
  outdec(lval->offset);
  outstr(", %eax");
  nl();*/
  cloadlita(lval->offset);
}
func store(lval:*elval)
{
  if(lval->sort==L_ID&&lval->idx)
  {
    if(lval->idx->sort==S_VARG)
    {
      if(lval->typ==T_INT||lval->typ==T_UINT||
       typtab[lval->typ].sort==V_PTR)
      /*ot("movl %eax, ");*/
      zstow(lval->idx->name,lval->offset);
      else if(lval->typ==T_CHAR)
      /*ot("movb %al, ");*/
      zstob(lval->idx->name,lval->offset);
      else if(lval->typ==T_DOUBLE)
      cfstglb(lval->idx->name,lval->offset);
      else if(lval->typ==T_FLOAT)
      cfstglbs(lval->idx->name,lval->offset);
      else error("error in global storing");
      /*outname(lval->idx->name);
      if(lval->offset)
      {outstr("+");outdec(lval->offset);}
      nl();*/
    }
    else if(lval->idx->sort==S_VARL)
    {
      if(lval->typ==T_INT||lval->typ==T_UINT||
       typtab[lval->typ].sort==V_PTR)
      /*ot("movl %eax, ");*/
      zstlw(lval->idx->offset+lval->offset);
      else if(lval->typ==T_CHAR)
      /*ot("movb %al, ");*/
      zstlb(lval->idx->offset+lval->offset);
      else if(lval->typ==T_DOUBLE)
      cfstloc(lval->idx->offset+lval->offset);
      else if(lval->typ==T_FLOAT)
      cfstlocs(lval->idx->offset+lval->offset);
      else error("error in local storing");
      /*outdec(lval->idx->offset+lval->offset);
      outasm("(%ebp)");
      nl();*/
    }
    else error("don't know how to store");
  }
  else if(lval->sort==L_SP)
  {
    /* store through a popped address (%rdx). FP values come from %xmm0; a float
       is narrowed back to 4 bytes on the way out. */
    if(lval->typ==T_DOUBLE)
    {zpop();cfstbre2(lval->offset);}
    else if(lval->typ==T_FLOAT)
    {zpop();cfstbre2s(lval->offset);}
    else
    {
      zpop();
      if(typtab[lval->typ].size==BYTESIZE)/*ot("movb %al, ");*/
      zstob2(lval->offset);
      else if(typtab[lval->typ].size==target.wordsize)/*ot("movl %eax, ");*/
      zstow2(lval->offset);
      else error("error storing object if strange size");
      /*outdec(lval->offset);outstr("(%edx)");nl();*/
    }
  }
  else error("how to store?");
}
func rvalue(lval:*elval)
{
  if(!lval)
  {error("rvalue(0)");return;}
  if(lval->sort==L_NUM)
  loadnum(lval);
  else if(lval->sort==L_FNUM)/*float literal -> %xmm0*/
  cloadflit(lval->val);
  else if(lval->sort==L_ID&&lval->idx)/*variable...*/
  getmem(lval);
  else if(lval->sort==L_POI)
  loadbyre(lval);
  else if(lval->sort==L_STR)
  {
    loadlita(lval);
  }
  else
  {
    fprintf(stderr,"lval->sort=%d\n",lval->sort);
    error("code generator error");
  }
}
func loadbyre(lval:*elval)
{
  /* FP element/pointee: load into %xmm0 (not %rax). A float widens to a double
     and the type decays, exactly as for named float variables (slice 5). */
  if(lval->typ==T_DOUBLE)
  cfldbre(lval->offset);
  else if(lval->typ==T_FLOAT)
  {cfldbres(lval->offset);lval->typ=T_DOUBLE;}
  else if(typtab[lval->typ].size==BYTESIZE)/*ot("movsbl ");*/
  zlbrb(lval->offset);
  else if(typtab[lval->typ].size==target.wordsize)/*ot("movl ");*/
  zlbrw(lval->offset);
  else if(typtab[lval->typ].sort==V_ARR)/*ot("leal ");*/
  zlbra(lval->offset);
  else error("error in loadbyreg()");
  /*outdec(lval->offset);
  outstr("(%eax), %eax");nl();*/
}
func getmem(lval:*elval)
{
  /*trc("getmem");*/
  if(lval->typ==T_CHAR)
  {
    /*ot("movsbl ");*/
    if(lval->idx->sort==S_VARG)
    {
      zldb(lval->name,lval->offset);
      /*outname(lval->name);
      if(lval->offset)
      {
        outasm("+");
        outdec(lval->offset);
      }
      outasm(", %eax");
      nl();*/
    }
    else if(lval->idx->sort==S_VARL)
    {
      zldlb(lval->idx->offset+lval->offset);
      /*outdec(lval->idx->offset+lval->offset);
      outasm("(%ebp), %eax");
      nl();*/
    }
    else error("error loading 'char' object");
  }
  else if(lval->typ==T_DOUBLE)
  {
    if(lval->idx->sort==S_VARG)
    cfldglb(lval->name,lval->offset);
    else if(lval->idx->sort==S_VARL)
    cfldloc(lval->idx->offset+lval->offset);
    else error("error loading 'double' object");
  }
  else if(lval->typ==T_FLOAT)
  {
    /* load the 4-byte float, widening it to a double in %xmm0; from here on the
       value is an ordinary double (slice 5), so decay the type. */
    if(lval->idx->sort==S_VARG)
    cfldglbs(lval->name,lval->offset);
    else if(lval->idx->sort==S_VARL)
    cfldlocs(lval->idx->offset+lval->offset);
    else error("error loading 'float' object");
    lval->typ=T_DOUBLE;
  }
  else if(lval->typ==T_INT||lval->typ==T_UINT||lval->typ==T_INTP
      ||lval->typ==T_CHARP
      ||typtab[lval->typ].sort==V_PTR)
  {
    /*ot("movl ");*/
    if(lval->idx->sort==S_VARG)
    {
      zldw(lval->name,lval->offset);
      /*outname(lval->name);
      if(lval->offset)
      {
        outasm("+");
        outdec(lval->offset);
      }
      outasm(", %eax");
      nl();*/
    }
    else if(lval->idx->sort==S_VARL)
    {
      zldlw(lval->idx->offset+lval->offset);
      /*outdec(lval->idx->offset+lval->offset);
      outasm("(%ebp), %eax");
      nl();*/
    }
    else error("getmem ?");
  }
  else if(typtab[lval->typ].sort==V_ARR)
  {
    if(lval->idx->sort==S_VARG)
    {
      zlda(lval->name,lval->offset);
      /*ot("movl $");
      outname(lval->name);
      if(lval->offset)
      {
        outasm("+");
        outdec(lval->offset);
      }
      outasm(", %eax");nl();*/
    }
    else if(lval->idx->sort==S_VARL)
    {
      zlea(lval->idx->offset+lval->offset);
      /*ot("leal ");
      outdec(lval->idx->offset+lval->offset);
      outasm("(%ebp), %eax");nl();*/
    }
    else error("still: how to getmem?");
  }
  else error("again error");
}
func loadnum(lval:*elval)
{
  zldn(lval->val);
  /*ot("movl $");
  outdec(lval->val);
  outasm(", %eax");
  nl();*/
}
/* M5 constant folding: collapse a constant *integer* subtree to a single L_NUM
   literal before codegen. Target-neutral (it rewrites the expression tree), so
   every backend then emits less code. Only integer literals are folded -- never
   float literals (L_FNUM; the compiler does no float arithmetic) -- and never
   division/remainder by zero (left for the existing runtime path). Folding uses
   the host's 64-bit int, which matches the 64-bit targets exactly and matches
   the 32-bit i386 for the small constants that actually occur. */
func foldtree(node:*enode)
{
  var int:a;var int:b;var int:res;var int:ok;
  if(!node)return;
  if(node->op==OP_LEAF)return;
  foldtree(node->l);
  foldtree(node->r);
  foldtree(node->third);
  ok=0;
  if(node->l&&node->r
     &&(node->l->op==OP_LEAF)&&(node->l->leaf.vid==L_NUM)
     &&(node->r->op==OP_LEAF)&&(node->r->leaf.vid==L_NUM))
  {
    a=node->l->leaf.val;b=node->r->leaf.val;ok=1;
    if(node->op==OP_PLUS)res=a+b;
    else if(node->op==OP_MINUS)res=a-b;
    else if(node->op==OP_MUL)res=a*b;
    else if(node->op==OP_DIV){if(b)res=a/b;else ok=0;}
    else if(node->op==OP_REM){if(b)res=a%b;else ok=0;}
    else if(node->op==OP_BAND)res=a&b;
    else if(node->op==OP_BOR)res=a|b;
    else if(node->op==OP_BXOR)res=a^b;
    else if(node->op==OP_SHL)res=a<<b;
    else if(node->op==OP_SHR)res=a>>b;     /* arithmetic, matches ct_SHR */
    else if(node->op==OP_EQ)res=(a==b);
    else if(node->op==OP_NEQ)res=(a!=b);
    else if(node->op==OP_LT)res=(a<b);
    else if(node->op==OP_GT)res=(a>b);
    else if(node->op==OP_LE)res=(a<=b);
    else if(node->op==OP_GE)res=(a>=b);
    else if(node->op==OP_LAND)res=(a&&b);
    else if(node->op==OP_LOR)res=(a||b);
    else ok=0;
  }
  else if((!node->l)&&node->r
          &&(node->r->op==OP_LEAF)&&(node->r->leaf.vid==L_NUM))
  {
    a=node->r->leaf.val;ok=1;
    if(node->op==OP_UMINUS)res=0-a;
    else if(node->op==OP_BNOT)res=~a;
    else if(node->op==OP_LNOT)res=!a;
    else ok=0;
  }
  if(ok)
  {
    if(node->l)delenode(node->l);
    if(node->r)delenode(node->r);
    node->l=0;node->r=0;
    node->op=OP_LEAF;
    node->leaf.vid=L_NUM;
    node->leaf.val=res;
    node->leaf.idx=0;
  }
}
func expressi()
{
  var *enode:node;
  var elval:lval;
  var int:rt;
  node=bexptree();
  foldtree(node);   /* M5: fold constant integer subexpressions */
  fprintf(stdout,"#:");pretree(node,stdout);fprintf(stdout,"\n");
  rt=T_INT;
  if(treetocode(node,&lval))rvalue(&lval);
  rt=lval.typ;   /* treetocode fills lval.typ whether or not rvalue was needed */
  delenode(node);
  return rt;   /* result type, so callers can convert (M4) */
}
func bexptree()
{
  var *enode:node;
  node=hcomma();
  return node;
}
func hcomma1()
{
  var *enode:node,newnode;
  node=hier1();
  blanks();
  if(ch()!=',')
  return node;
  while(1)
  {
    if(match(","))
    {
      newnode=getenode();
      newnode->l=node;
      newnode->r=hier1();
      newnode->third=0;
      newnode->op=OP_COMMA;
      node=newnode;
    }
    else return node;
  }
}
func hcomma()
{
  var *enode:node,newnode;
  node=hier1();
  blanks();
  if(ch()!=',')
  return node;
  while(1)
  {
    if(match(","))
    {
      newnode=getenode();
      newnode->l=node;
      newnode->r=hcomma();
      newnode->third=0;
      newnode->op=OP_COMMA;
      node=newnode;
    }
    else return node;
  }
}
func hier1()
{
  var *enode:node,newnode;
  node=hcond();
  if(match("="))
  {
    newnode=getenode();
    newnode->l=node;
    newnode->r=hier1();
    newnode->third=0;
    newnode->op=OP_ASSIGN;
    node=newnode;
  }
  return node;
}
func hcond()
{
  var *enode:node,newnode;
  node=hlor();
  if(match("?"))
  {
    newnode=getenode();
    newnode->l=node;
    newnode->r=hcond();
    blanks();
    if(!match(":"))
    error("':' expected i conditional");
    newnode->third=hcond();
    newnode->op=OP_COND;
    node=newnode;
  }
  return node;
}
func hlor()
{
  var *enode:node,newnode;
  node=hland();
  blanks();
  if(match("||"))
  {
    newnode=getenode();
    newnode->l=node;
    newnode->r=hlor();
    newnode->third=0;
    newnode->op=OP_LOR;
    node=newnode;
  }
  return node;
}
func h1lor()
{
  var *enode:node,newnode;
  node=hland();
  blanks();
  if(!streq(line+lptr,"||"))
  return node;
  while(match("||"))
  {
    newnode=getenode();
    newnode->l=node;
    newnode->r=hland();
    newnode->third=0;
    newnode->op=OP_LOR;
    node=newnode;
  }
  return node;
}
func hland()
{
  var *enode:node,newnode;
  node=hbor();
  blanks();
  if(match("&&"))
  {
    newnode=getenode();
    newnode->l=node;
    newnode->r=hland();
    newnode->third=0;
    newnode->op=OP_LAND;
    node=newnode;
  }
  return node;
}
func h1land()
{
  var *enode:node,newnode;
  node=hbor();
  blanks();
  if(!streq(line+lptr,"&&"))
  return node;
  while(match("&&"))
  {
    newnode=getenode();
    newnode->l=node;
    newnode->r=hbor();
    newnode->third=0;
    newnode->op=OP_LAND;
    node=newnode;
  }
  return node;
}
func hbor()
{
  var *enode:node,newnode;
  node=hbxor();
  if(ch()!='|'||streq(line+lptr,"||"))
  return node;
  while(1)
  {
    blanks();
    if(streq(line+lptr,"|")&&!streq(line+lptr,"||"))
    {
      gch();
      newnode=getenode();
      newnode->l=node;
      newnode->r=hbxor();
      newnode->third=0;
      newnode->op=OP_BOR;
      node=newnode;
    }
    else
    return node;
  }
}
func hbxor()
{
  var *enode:node,newnode;
  node=hband();
  blanks();
  if(ch()!='^'||streq(line+lptr,"^^"))
  return node;
  while(1)
  {
    blanks();
    if(streq(line+lptr,"^")&&!streq(line+lptr,"^^"))
    {
      gch();
      newnode=getenode();
      newnode->l=node;
      newnode->r=hband();
      newnode->third=0;
      newnode->op=OP_BXOR;
      node=newnode;
    }
    else return node;
  }
}
func hband()
{
  var *enode:node,newnode;
  node=hequal();
  blanks();
  if(ch()!='&'||streq(line+lptr,"&&"))
  return node;
  while(1)
  {
    blanks();
    if(ch()=='&'&&!streq(line+lptr,"&&"))
    {
      gch();
      newnode=getenode();
      newnode->l=node;
      newnode->r=hequal();
      newnode->third=0;
      newnode->op=OP_BAND;
      node=newnode;
    }
    else return node;
  }
}
func hequal()
{
  var *enode:node,newnode;
  node=hgt();
  blanks();
  if(!streq(line+lptr,"==")&&!streq(line+lptr,"!="))
  return node;
  while(1)
  {
    if(match("=="))
    {
      newnode=getenode();
      newnode->l=node;
      newnode->r=hgt();
      newnode->third=0;
      newnode->op=OP_EQ;
      node=newnode;
    }
    else if(match("!="))
    {
      newnode=getenode();
      newnode->l=node;
      newnode->r=hgt();
      newnode->third=0;
      newnode->op=OP_NEQ;
      node=newnode;
    }
    else return node;
  }
}
func hgt()
{
  var *enode:node,newnode;
  node=hshift();
  blanks();
  if(!streq(line+lptr,"<")
   &&!streq(line+lptr,">")
   &&!streq(line+lptr,"<=")
   &&!streq(line+lptr,">=")
   ||streq(line+lptr,"<<")
   ||streq(line+lptr,">>"))
  return node;
  while(1)
  {
    if(match("<="))
    {
      newnode=getenode();
      newnode->l=node;
      newnode->r=hshift();
      newnode->third=0;
      newnode->op=OP_LE;
      node=newnode;
    }
    else if(match(">="))
    {
      newnode=getenode();
      newnode->l=node;
      newnode->r=hshift();
      newnode->third=0;
      newnode->op=OP_GE;
      node=newnode;
    }
    else if(streq(line+lptr,"<")&&!streq(line+lptr,"<<"))
    {
      gch();
      newnode=getenode();
      newnode->l=node;
      newnode->r=hshift();
      newnode->third=0;
      newnode->op=OP_LT;
      node=newnode;
    }
    else if(streq(line+lptr,">")&&!streq(line+lptr,">>"))
    {
      gch();
      newnode=getenode();
      newnode->l=node;
      newnode->r=hshift();
      newnode->third=0;
      newnode->op=OP_GT;
      node=newnode;
    }
    else return node;
  }
}
func hshift()
{
  var *enode:node,newnode;
  node=hplusminus();
  blanks();
  if(!streq(line+lptr,"<<")&&!streq(line+lptr,">>"))
  return node;
  while(1)
  {
    if(match("<<"))
    {
      newnode=getenode();
      newnode->l=node;
      newnode->r=hplusminus();
      newnode->third=0;
      newnode->op=OP_SHL;
      node=newnode;
    }
    else if(match(">>"))
    {
      newnode=getenode();
      newnode->l=node;
      newnode->r=hplusminus();
      newnode->third=0;
      newnode->op=OP_SHR;
      node=newnode;
    }
    else return node;
  }
}
func hplusminus()
{
  var *enode:node,newnode;
  node=hmuldiv();
  blanks();
  if((ch()!='+')&&(ch()!='-'))
  return node;
  while(1)
  {
    if(match("+"))
    {
      newnode=getenode();
      newnode->l=node;
      newnode->r=hmuldiv();
      newnode->third=0;
      newnode->op=OP_PLUS;
      node=newnode;
    }
    else if(match("-"))
    {
      newnode=getenode();
      newnode->l=node;
      newnode->r=hmuldiv();
      newnode->third=0;
      newnode->op=OP_MINUS;
      node=newnode;
    }
    else
    return node;
  }
}
func hmuldiv()
{
  var *enode:node,newnode;
  node=hunary();
  blanks();
  if((ch()!='*')&&(ch()!='/')&&(ch()!='%'))
  return node;
  while(1)
  {
    if(match("*"))
    {
      newnode=getenode();
      newnode->l=node;
      newnode->r=hunary();
      newnode->third=0;
      newnode->op=OP_MUL;
      node=newnode;
    }
    else if(match("/"))
    {
      newnode=getenode();
      newnode->l=node;
      newnode->r=hunary();
      newnode->third=0;
      newnode->op=OP_DIV;
      node=newnode;
    }
    else if(match("%"))
    {
      newnode=getenode();
      newnode->l=node;
      newnode->r=hunary();
      newnode->third=0;
      newnode->op=OP_REM;
      node=newnode;
    }
    else
    return node;
  }
}
func hunary()
{
  var *enode:node,newnode;
  if(match("++"))
  {
    node=hunary();
    newnode=getenode();
    newnode->l=0;
    newnode->r=node;
    newnode->third=0;
    newnode->op=OP_1PP;
    node=newnode;
    return node;
  }
  else if(match("--"))
  {
    node=hunary();
    newnode=getenode();
    newnode->l=0;
    newnode->r=node;
    newnode->third=0;
    newnode->op=OP_1MM;
    node=newnode;
    return node;
  }
  else if(match("+"))
  {
    node=hunary();
    return node;
  }
  else if(ch()=='-'&&!numeric(line[lptr+1])/*match("-")*/)
  {
    gch();
    node=hunary();
    newnode=getenode();
    newnode->l=0;
    newnode->r=node;
    newnode->third=0;
    newnode->op=OP_UMINUS;
    node=newnode;
    return node;
  }
  else if(match("*"))
  {
    node=hunary();
    newnode=getenode();
    newnode->l=0;
    newnode->r=node;
    newnode->third=0;
    newnode->op=OP_STAR;
    node=newnode;
    return node;
  }
  else if(match("!"))
  {
    node=hunary();
    newnode=getenode();
    newnode->l=0;
    newnode->r=node;
    newnode->third=0;
    newnode->op=OP_LNOT;
    node=newnode;
    return node;
  }
  else if(match("~"))
  {
    node=hunary();
    newnode=getenode();
    newnode->l=0;
    newnode->r=node;
    newnode->third=0;
    newnode->op=OP_BNOT;
    node=newnode;
    return node;
  }
  else if(match("&"))
  {
    node=hunary();
    newnode=getenode();
    newnode->l=0;
    newnode->r=node;
    newnode->third=0;
    newnode->op=OP_ADDR;
    node=newnode;
    return node;
  }
  else
  {
    node=hsubscr();
    if(match("++"))
    {
      newnode=getenode();
      newnode->l=0;
      newnode->r=node;
      newnode->third=0;
      newnode->op=OP_2PP;
      node=newnode;
    }
    else if(match("--"))
    {
      newnode=getenode();
      newnode->l=0;
      newnode->r=node;
      newnode->third=0;
      newnode->op=OP_2MM;
      node=newnode;
    }
    return node;
  }
}
func hsubscr()
{
  var *enode:node,newnode;
  node=primary();
  blanks();
  if((ch()=='[')||
   streq(line+lptr,tlarg)
   ||(ch()=='.')
   ||streq(line+lptr,"->"))
  while (1)
    {
    if(match("["))
      {/* a[i] --> *((a)+(i)) */
      newnode=getenode();
      newnode->l=node;
      newnode->r=hcomma();
      needbrac("]");
      newnode->third=0;
      newnode->op=OP_PLUS;
      node=getenode();
      node->l=0;
      node->r=newnode;
      node->third=0;
      node->op=OP_STAR;
      }
    else if(match(tlarg/*"("*/))
      {
      newnode=getenode();
      newnode->l=node;
      newnode->r=0;
      newnode->third=0;
      newnode->op=OP_FUNC;
      node=newnode;
      blanks();
      while(!streq(line+lptr,trarg))
        {
        if(endst())break;
        newnode=getenode();
        newnode->l=hier1();
        newnode->r=node->r;
        newnode->third=0;
        newnode->op=OP_LIST;
        node->r=newnode;
        if(!match(","))break;
        }
      needbrac(trarg/*")"*/);
      }
    else if(match("->"))
      {/* p->a (*p).a */
      var [NAMESIZE]char:nm;
      if(!symname(nm))
        error("field name expected");
      newnode=getenode();
      newnode->l=0;
      newnode->r=node;
      newnode->third=0;
      newnode->op=OP_STAR;
      node=getenode();
      node->l=newnode;
      node->r=0;
      node->third=0;
      node->op=OP_DOT;
      strcp(node->name,nm);
      }
    else if(match("."))
      {
      var [NAMESIZE]char:nm;
      if(!symname(nm))
        error("field name expected");
      newnode=getenode();
      newnode->l=node;
      newnode->r=0;
      newnode->third=0;
      newnode->op=OP_DOT;
      strcp(newnode->name,nm);
      node=newnode;
      }
    else
      return node;
    }
  return node;
}
func getenode()
{
  return chkmem(calloc(1,sizeof(enode)));
}
func delenode(node:*enode)
{
  if(!node)return;
  delenode(node->l);
  delenode(node->r);
  delenode(node->third);
  free(node);
}
func primary()
{
  var *enode:node;
  var [1]int: num;
  var [NAMESIZE]char: nm;
  if(match(tlarg))
  {
    node=bexptree();
    needbrac(trarg);
    return node;
  }
  if(amatch("sizeof",6))
  {
    var int:t,s;
    needbrac(tlarg);
    t=gettypen();
    s=gettsize(t);
    needbrac(trarg);
    node=getenode();
    node->l=node->r=node->third=0;
    node->op=OP_LEAF;
    node->leaf.vid=L_NUM;
    node->leaf.val=s;
    return node;
  }
  {
    var int:nr;
    nr=number(num);
    if(nr)
    {
      node=getenode();
      node->l=node->r=node->third=0;
      node->op=OP_LEAF;
      node->leaf.vid=(nr==2)?L_FNUM:L_NUM;   /* 2 => float literal; uses ?: */
      node->leaf.val=num[0];
      return node;
    }
  }
  if(pstr(num))
  {
    node=getenode();
    node->l=node->r=node->third=0;
    node->op=OP_LEAF;
    node->leaf.vid=L_NUM;
    node->leaf.val=num[0];
    return node;
  }
  if(symname(nm))
  {
    var *ssym:k;
    node=getenode();
    node->l=node->r=node->third=0;
    node->op=OP_LEAF;
    node->leaf.vid=L_ID;
    strcp(node->name,nm);
    if(methodcls&&methodidx&&(k=findfiel(nm,methodcls)))
    {
      var *enode:ths;
      var *ssym:t;
      ths=getenode();
      ths->l=ths->r=ths->third=0;
      ths->op=OP_LEAF;
      ths->leaf.vid=L_ID;
      if(!(t=findloc("this")))
      error("internal error: missing 'this'");
      ths->leaf.idx=t;
      strcp(ths->name,"this");
      node->r=ths;
      node->op=OP_STAR;
      var *enode:newnode;
      newnode=getenode();
      newnode->l=node;
      newnode->r=0;
      newnode->third=0;
      newnode->op=OP_DOT;
      strcp(newnode->name,nm);
      node=newnode;
    }
    else if(k=findloc(nm))
    {
      node->leaf.idx=k;
      if(cnmlst)cnmlst->addm(nm);
    }
    else if(k=findglb(nm))
    {
      if(k->sort==S_CONST)        /* enum constant -> fold to its integer value */
      {node->leaf.vid=L_NUM;node->leaf.val=k->offset;}
      else
      {
        node->leaf.idx=k;
        if(cnmlst)cnmlst->addm(nm);
      }
    }
    else
    {/* undeclared function */
      k=addloc(nm,S_VARL,1,0,T_INT);
      k->sort=S_FUNC;
      k->dfd=0;
      node->leaf.idx=k;
      if(cnmlst)cnmlst->addm(nm);
    }
    return node;
  }
  if(qstr(num))
  {
    node=getenode();
    node->l=node->r=node->third=0;
    node->op=OP_LEAF;
    node->leaf.vid=L_STR;
    node->leaf.val=num[0];
    return node;
  }
  error("wrong expression");
  return 0;
}
func pstr(val:*int)
{
  var int:k;
  var char:c;
  k=0;
  if(!match("'"))return 0;
  while((c=gch())!=39)
  {
    if(c!=92)
    k=((k&255)<<8)+(c&255);
    else
    {
      c=gch();
      if(!c)break;
      if(c=='n')c=10;
      else if(c=='t')c=9;
      else if(c=='b')c=8;
      else if(c=='f')c=12;
      k=((k&255)<<8)+(c&255);
    }
  }
  val[0]=k;
  /*fprintf(stderr,"the character:%d\n",k);*/
  return 1;
}
func qstr(val:*int)
{
  var int:k;
  var char:c;
  k=0;
  if(!match(quote))return 0;
  val[0]=stptr;
  while(ch()!='"')
  {
    if(!ch())break;
    if(stptr>=STMAX)
    {
      error("string space exhausted");
      while(!match(quote))if(!gch())break;
      return 1;
    }
    c=gch();
    if(c!=92)litq[stptr++]=c;
    else
    {
      c=gch();
      if(!c)break;
      if(c=='n')c=10;
      else if(c=='t')c=9;
      else if(c=='b')c=8;
      else if(c=='f')c=12;
      litq[stptr++]=c;
    }
  }
  gch();
  litq[stptr++]=0;
  return 1;
}
func addfloat(s:*char)  /* store a float-literal's text, return its pool index */
{
  var int:i;
  if(fpoolptr>=200){error("too many float literals");return 0;}
  i=fpoolptr++;
  fpooloff[i]=fpoolbp;
  while(*s)fpoolbuf[fpoolbp++]=*s++;
  fpoolbuf[fpoolbp++]=0;
  return i;
}
func dumpfloats()       /* emit .LF<i>: .double <text> for each float literal */
{
  var int:i;
  if(!fpoolptr)return ;
  ot(target.dir_section);
  ot(target.dir_rodata);
  nl();
  /* The pool follows the byte-granular string pool in .rodata, so its .double
     entries are at an arbitrary offset. On a strict-alignment target (mips)
     `ldc1` from a non-8-aligned .LF faults, so word-align the pool start; the
     8-byte .double entries then stay aligned. dir_align is the target's
     power-of-2/byte form (".align 3" == 8 bytes on mips). */
  if(target.strictalign){ot(target.dir_align);nl();}
  for(i=0;i<fpoolptr;i++)
  {
    outstr(".LF");outdec(i);col();nl();
    ot(".double ");outstr(fpoolbuf+fpooloff[i]);nl();
  }
}
func number(val:*int)
{
  var int:k;
  var int:d;
  var int:minus;
  var char:c;
  var [48]char:buf;
  var int:bp;
  k=minus=1;bp=0;
  if(match("0x")){
  k=0;
  while(numeric(ch())||((ch()>='a')&&(ch()<='f'))){
    c=inbyte();
    if(numeric(c)){
    k=(k<<4)+(c-'0');
    }
    else
    {
      k=(k<<4)+(c-'a'+10);
    }
  }
  val[0]=k;
  return 1;
  }
  while(k){
  k=0;
  if(match("+"))k=1;
  if(match("-")){
    minus=-1;
    k=1;
    buf[bp++]='-';
  }
  }
  if(!numeric(ch()))return 0;
  while(numeric(ch())){
  c=inbyte();
  buf[bp++]=c;
  k=k*10+(c-'0');
  }
  /* a '.' or exponent makes this a floating-point literal: keep the text and
     hand it to the assembler as a .double (M4). */
  if((ch()=='.')||(ch()=='e')||(ch()=='E')){
    if(ch()=='.'){
      buf[bp++]=inbyte();
      while(numeric(ch()))buf[bp++]=inbyte();
    }
    if((ch()=='e')||(ch()=='E')){
      buf[bp++]=inbyte();
      if((ch()=='+')||(ch()=='-'))buf[bp++]=inbyte();
      while(numeric(ch()))buf[bp++]=inbyte();
    }
    buf[bp]=0;
    val[0]=addfloat(buf);
    return 2;
  }
  if(minus<0)k=(-k);
  val[0]=k;
  return 1;
}
func needbrac(p:*char)
{
  if(!match(p)){
  error("missing bracket");
  comment();
  outstr(p);
  nl();
  }
}
func needlval()
{
  error("must be lvalue");
}
func ns()
{
  if(!match(";"))error("missing ';'");
}
func issigned(t:int)
{
  return (t==T_INT)||(t==T_CHAR);
}
/* M6: result type of an integer binary op -- unsigned if either operand is, so
   unsignedness propagates through arithmetic and a later compare / >> on the
   result still uses the unsigned variant. */
func uresult(t1:int,t2:int)
{
  if((t1==T_UINT)||(t2==T_UINT))return T_UINT;
  return T_INT;
}
func gettsize(t:int)
{
  if(t==T_INT)return target.wordsize;
  else if(t==T_UINT)return target.wordsize;
  else if(t==T_CHAR)return BYTESIZE;
  else if(t==T_DOUBLE)return 8;
  else if(t==T_FLOAT)return 4;
  else if(t==T_INTP)return target.wordsize;
  else if(t==T_CHARP)return target.wordsize;
  else if((t>=F_TYPE)&&(t<typptr))return typtab[t].size;
  else
  {
    error("strange type");
    return 0;
  }
}
/*returns type 'function of a type' */
func getfnctype(t:int)
{
  if(t>=typptr)
  {
    error("getfnctype:unknown type");
    return T_INTP;
  }
  var int:k;
  for(k=1;k<typptr;k++)
  if((typtab[k].sort==V_FNC)&&(typtab[k].type==t))return k;
  k=typget();
  typtab[k].name[0]=0;
  typtab[k].sort=V_FNC;
  typtab[k].type=t;
  typtab[k].size=0;/*maybe...*/
  return k;
}
func typget()
{
  if(typptr>=NUMTYP)
  {
    numtyp=numtyp+NUMTYP;
    chkmem(typtab=realloc(typtab,sizeof(styp)*numtyp));
  }
  return typptr++;
}
/*returns pointer to a type */
func getptrty(t:int)
{
  var int:k;
  if(t>=typptr){
  error("unknown type");
  return T_INTP;
  }
  k=1;
  while(k<typptr){
  if((typtab[k].sort==V_PTR)&&(typtab[k].type==t))return k;
  k++;
  }
  if(typptr>=numtyp){
  /*fprintf(stderr,"reallocating types\n");*/
  numtyp=numtyp+NUMTYP;
  chkmem(typtab=realloc(typtab,sizeof(styp)*numtyp));
  }
  typtab[typptr].name[0]=0;
  typtab[typptr].sort=V_PTR;
  typtab[typptr].type=t;
  typtab[typptr].size=target.wordsize;
  return typptr++;
}
func cbtype()
{
  var [NAMESIZE]char:sname;
  blanks();
  /*fprintf(stderr,"cbtype()\n");
  fprintf(stderr,"line=%s\n",line);*/
  if(ch()=='*'||ch()=='[')
  return 1;
  if(!fsymname(sname))
  return 0;
  /*fprintf(stderr,"got a name:%s\n,line=%s\n",sname,line);*/
  if(!findtyp(sname))
  return 0;
  return 1;
}
func gettypen()
{
  var [NAMESIZE]char:tname;
  var int:k;
  var int:l;
  var int:t;
  var int:c;
  var [1]int:dim;
  trc("gettypename");
  if(amatch("char",4))return T_CHAR;
  if(amatch("int",3))return T_INT;
  if(amatch("unsigned",8))return T_UINT;
  if(amatch("double",6))return T_DOUBLE;
  if(amatch("float",5))return T_FLOAT;
  if(alpha(ch())){
  k=l=0;
  while(an(c=line[lptr+k])){
    if(k<NAMEMAX)tname[l++]=c;
    k++;
  }
  comment();
  outstr("l=");
  outdec(l);
  nl();
  tname[l]=0;
  comment();
  outstr("typename:");
  outstr(tname);
  nl();
  if(t=findtyp(tname)){
    lptr=lptr+k;
    comment();
    outstr("type handle:");
    outdec(t);
    nl();
    trc(line+lptr);
    return t;
  }
  else
    {
    error("unknown type");
    return T_INT;
    }
  }
  if(match("*")){
  if(!(t=gettypen()))return 0;
  k=1;
  while(k<typptr){
    if((typtab[k].sort==V_PTR)&&(typtab[k].type==t))return k;
    k++;
  }
  if(typptr>=numtyp){
    /*fprintf(stderr,"reallocating types\n");*/
    numtyp=numtyp+NUMTYP;
    chkmem(typtab=realloc(typtab,sizeof(styp)*numtyp));
    }
  typtab[typptr].name[0]=0;
  typtab[typptr].sort=V_PTR;
  typtab[typptr].type=t;
  typtab[typptr].size=target.wordsize;
  return typptr++;
  }
  if(match("[")){
  /* a constant integer expression (literal, enum constant, or arithmetic on
     them), not just a bare number -- so [N]int with an enum N works, and a bad
     dimension errors cleanly instead of looping. */
  dim[0]=constexpr("array dimension must be a constant integer");
  if(dim[0]<1)dim[0]=1;
  needbrac("]");
  if(!(t=gettypen()))return 0;
  k=1;
  while(k<typptr){
    if((typtab[k].sort==V_ARR)&&(typtab[k].type==t)
     &&(typtab[k].dim==dim[0]))return k;
    k++;
  }
  if(typptr>=numtyp){
    /*fprintf(stderr,"reallocating types\n");*/
    numtyp=numtyp+NUMTYP;
    chkmem(typtab=realloc(typtab,sizeof(styp)*numtyp));
  }
  typtab[typptr].name[0]=0;
  typtab[typptr].sort=V_ARR;
  typtab[typptr].type=t;
  typtab[typptr].size=gettsize(t)*dim[0];
  typtab[typptr].dim=dim[0];
  return typptr++;
  }
  error("type expected");
  return T_INT;
}
func outname(n:*char)
{
  outasm(target.sym_prefix);
  outasm(n);
}
func inbyte()
{
  while(!ch()){
  if(iseof)return 0;
  insline();
  preproce();
  }
  return gch();
}
func junk()
{
  if(an(inbyte()))while(an(ch()))gch();
  else
  while(!an(ch())){
    if(!ch())break;
    gch();
  }
  blanks();
}
func strcp(d:*char,s:*char)
{
  while(*d++=*s++);
}
func findsym(sname:*char,syms:*ssym,ptr:int)
{
  var int:k;
  /*fprintf(stderr,"sname=%s,ptr=%d\n",sname,ptr);*/
  for(k=0;k<ptr;k++)
  {
    /*fprintf(stderr,"1");*/
    if(strid(sname,syms[k].name))
    {return syms+k;fprintf(stderr,"2\n");}
    /*fprintf(stderr,"2");*/
  }
  return 0;
}
func outdec(n:int)
{
  if(n<0){
  outbyte('-');
  n=-n;
  }
  outint(n);
}
func outint(n:int)
{
  var int:q;
  q=n/10;
  if(q)outint(q);
  outbyte('0'+n%10);
}
func error(p:*char)
{
  var int:k;
  comment();
  outstr("Error:");
  outstr(p);
  fprintf(stderr,"---->Error:%s\n",p);
  fprintf(stderr,"%s\n",line);
  for(k=lptr;k--;)fprintf(stderr," ");
  fprintf(stderr,"^\n");
  nl();
  ++errcnt;
}
func reset()
{
  lptr=0;
  line[0]=0;
}
func ol(p:*char)
{
  ot(p);
  nl();
}
func dumplits()
{
  var int:j;
  var int:k;
  if(!stptr)return ;
  ot(target.dir_section);
  ot(target.dir_rodata);
  nl();
  printlab(stlab);
  col();
  nl();
  k=0;
  while(k<stptr){
  defbyte();
  j=10;
  while(j--){
    outdec(litq[k++]);
    if(!j|(k>=stptr)){
    nl();
    break;
    }
    outbyte(',');
  }
  }
}
func defbyte()
{
  ot(".byte ");
}
func defstora()
{
  ot(".comm ");
}
func printmap()
{
  var of:*int;
  if(!(of=fopen(mapname,"w")))
  {
    fprintf(stderr,"can't open map file %s\n",mapname);
    return;
  }
  var int:s;
  var *ssymlist:lst;
  for(lst=glbsymtab.lst;lst;lst=lst->next)
  {
    fprintf(of,"%-10s\t%d\t%d\n",lst->sym.name,
        lst->sym.line,
        lst->sym.sort);
  }
  fclose(of);
}
func dumpglbs()
{
  var int:s;
  var *ssymlist:lst;
  for(lst=glbsymtab.lst;lst;lst=lst->next)
  {
    if(lst->sym.sort==S_VARG)if(lst->sym.dfd)
    {
      defstora();
      outname(lst->sym.name);
      comma();
      s=gettsize(lst->sym.type);
      outdec(s);
      /* .comm alignment: char stays byte-aligned; everything else gets word
         alignment on strict targets (mips ld/sd fault otherwise), else 4. */
      if(lst->sym.type==T_CHAR)outasm(",1");
      else if(target.strictalign){comma();outdec(target.wordsize);}
      else outasm(",4");
      nl();
    }
  }
}
func trailer()
{
  nl();
  comment();
  outstr("<<End of compilation>>");
  nl();
  ot(".ident");
  tab();
  outstr(quote);
  outstr("T Cmplr");
  outstr(quote);
  nl();
  /*tstcg();*/
}
func nl()
{
  outbyte(10);
}
func tab()
{
  outbyte(9);
}
func col()
{
  outbyte(':');
}
func comma()
{
  outbyte(',');
}
func comment()
{
  outbyte('#');
  outbyte(':');
}
func ot(p:*char)
{
  tab();
  outasm(p);
}
func outbyte(c:char)
{
  if(!tolitstk)return outbyte1(c);
  return putlitst(c);
}
func outbyte1(c:char)
{
  if(!c)return 0;
  putchar(c);
  return c;
}
func outasm(p:*char)
{
  while(outbyte(*p++));
}
func outstr(p:*char)
{
  while(*p)outbyte(*p++);
}
func symname(sname:*char)
{
  var int:k;
  var int:l;
  var char:c;
  blanks();
  if(!alpha(ch()))return 0;
  k=l=0;
  while(an(ch()))
  {
    if(k<NAMEMAX)
    {
      sname[l++]=gch();
      k++;
    }
    else
    {
      k++;
      gch();
    }
  }
  sname[l]=0;
  return 1;
}
func fsymname(sname:*char)
{
  var int:k;
  var int:l;
  var char:c;
  var int:qptr;
  blanks();
  if(!alpha(ch()))return 0;
  k=l=0;
  qptr=lptr;
  /*fprintf(stderr,"%s\n",line);*/
  while(an(line[qptr]))
  {
    /*fprintf(stderr,"%s\n",line);*/
    if(k<NAMEMAX)
    {
      sname[l++]=line[qptr++];
      k++;
    }
    else
    {
      k++;
      qptr++;
    }
  }
  sname[l]=0;
  return 1;
}
func trc(p:*char)
{
  comment();
  outstr(p);
  nl();
}
