/*      -*- C -*-                                                       */
/************************************************************************
                       This is the preprocessor 
*************************************************************************/
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
#define MAXINC 10
var extern stderr,stdin,stdout:*int;
var ifil,ofil:*int;
var ifiles:[MAXINC]*int;
var iptr:int;
var line,rline:[160]char;
var lptr,rlptr:int;
var isinp,iseof:int;
var errcnt:int;
var strpool:[3000]char;
var strptr:int;
struct cmac{*char n; *char sub;};
var mactab:[200]cmac;
var macptr:int;
func strcp(d:*char,s:*char)
{
  while(*d++=*s++);
}
func ch()
{
  return line[lptr];
}
func gch()
{
  return line[lptr++];
}
func putres(c:int)
{
  if(rlptr>=159)
  {
    rline[159]=0;
    if(c)error("output buffer overflow");
    return 0;
  }
  return rline[rlptr++]=c;
}
func putmac(c:int)
{
  /*fprintf(stderr,"putmac:c=%d\n",c);*/
  if(strptr>=2999)
  {
    strpool[2999]=0;
    strptr=3000;
    if(c)error("string pool full");
    return 0;
  }
  return strpool[strptr++]=c;
}
func getnewstr()
{
  if(strptr>2999)
  {error("getnewstr:string pool full");return 0;}
  return strptr;
}
func addmac()
{
  var [16]char:sname;
  var int:k,l;
  if(!symname(sname))
  {error("wrong macro name");return;}
  if(macptr>=199)
  {error("mactab full");return;}
  sb();
  k=getnewstr();
  mactab[macptr].n=strpool+k;
  l=0;
  while(putmac(sname[l++]))
  ;
  k=getnewstr();
  mactab[macptr].sub=strpool+k;
  while(putmac(line[lptr++]));
  /*fprintf(stderr,"macro name=%s, sub=%s\n",mactab[macptr].n,
      mactab[macptr].sub);*/
  macptr++;
}
func strid(str1:*char,str2:*char)
{
  var int: k;
  k=0;
  while(str2[k])
  {if(str1[k]!=str2[k])return 0;k++;}
  if(str1[k])return 0;
  return 1;
}
func findmac(s:*char)
{
  var int: i;
  for(i=1;i<macptr;i++)
  if(strid(s,mactab[i].n))
    return i;
  return 0;
}
func symname(sname:*char)
{
  var int:k,l,too_long;var char: c;
  sb();
  if(!alpha(line[lptr]))return 0;
  for(k=l=too_long=0;an(line[lptr]);)
  {
    if(k<15)
    {sname[l++]=line[lptr++];k++;}
    else
    {too_long=1;k++;lptr++;}
  }
  if(too_long)error("identifier too long");
  sname[l]=0;
  return 1;
}
func amatch(lit:*char,len:int)
{
  var int:k;
  sb();
  if(k=astreq(line+lptr,lit,len))
  {
    lptr=lptr+k;
    return 1;
  }
  return 0;
}
func error(p:*char)
{
  fprintf(stderr,"***** Error:%s\nline:%s\n",p,line);
  ++errcnt;
}
func an(c:int)
{
  return((alpha(c))||(numeric(c)));
}
func numeric(c:int)
{
  return((c>='0')&&(c<='9'));
}
func alpha(c:int)
{
  return (((c>='a')&&(c<='z'))||((c>='A')&&(c<='Z'))||(c=='_'));
}
func insline()
{
  var int:k,longline;
  if(!isinp)iseof=1;
  if(iseof)return;
  lptr=0;
  longline=0;
  line[0]=0;
  while((k=fgetc(ifil))>0)
  {
    if(k==10)
    {break;}
    if(lptr>=158)
    {
      longline=1;
      while((k=fgetc(ifil))>0)if(k==10)break;
      break;
    }
    line[lptr++]=k;
  }
  line[lptr]=0;
  if(longline)error("input line too long");
  if(k<0)
  {
    if(iptr>0)
    {
      fclose(ifil);
      ifil=ifiles[--iptr];
    }
    else
    isinp=0;
  }
  /*fprintf(stderr,"<<<<<<%s\n",line);*/
}
func isb(c:int)
{
  return (line[lptr]==32)||(line[lptr]==9)||
  (line[lptr]==10);
}
func sb()
{
  while((line[lptr]==32)||(line[lptr]==9)||
    (line[lptr]==10))
  lptr++;
}
func match(lit:*char)
{
  var int:k;
  sb();
  if(k=streq(line+lptr,lit))
  {lptr=lptr+k;return 1;}
  return 0;
}
func streq(str1:*char,str2:*char)
{
  var int:k;
  for(k=0;str2[k];k++)
  if(str1[k]!=str2[k])return 0;
  return k;
}
func astreq(str1:*char,str2:*char,len:int)
{
  var int: k;
  k=0;   
  while(k<len)
  {
    if((str1[k])!=(str2[k]))break;
    if(!str1[k])break;
    if(!str2[k])break;
    k++;
  }
  if(an(str1[k]))return 0;
  if(an(str2[k]))return 0;
  return k;
}
func prep()
{
  rline[0]=0;
  rlptr=0;
  lptr=0;
  lptr=0;
  while(line[lptr])
  {
    var [16]char:sname;
    var int:k;
    if(isb(line[lptr]))
      {putres(' ');lptr++;}
    else if(symname(sname))
    {
      if(k=findmac(sname))
      {
        var *char:p;
        p=mactab[k].sub;
        /*fprintf(stderr,"substituting:%s\n",p);*/
        while(*p)putres(*p++);
      }
      else
      {
        k=0;
        while(sname[k])putres(sname[k++]);
      }
    }
    else if(line[lptr]==39)
    {
      putres(gch());
      while(ch()!=39)
      {
        if(!ch())
        {error("unterminated char const");break;}
        else if(ch()=='\\')
        {
          putres(gch());
          if(!ch())
          {
            if(iseof)
            break;
            insline();
            lptr=0;
          }
          else putres(gch());
        }
        else putres(gch());
      }
      if(ch()==39)
      putres(gch());
    }
    else if(line[lptr]=='"')
    {
      /*      fprintf(stderr,"quoted string=%s\n",line+lptr);*/
      putres(gch());
      while(ch()!='"')
      {
        if(!ch())
        {error("unterminated string");break;}
        else if(ch()=='\\')
        {
          putres(gch());
          if(!ch())
          {
            if(iseof)
            break;
            insline();
            lptr=0;
          }
          else putres(gch());
        }
        else putres(gch());
      }
      if(ch()=='"')putres(gch());
    }
    else if((line[lptr]=='/')&&(line[lptr+1]=='*'))
    {
      lptr=lptr+2;
      while(!((ch()=='*')&&(line[lptr+1]=='/')))
      {
        if(!ch())
        {
          if(iseof)
          {
            error("unterminated comment");
            break;
          }
          insline();
          lptr=0;
        }
        else
        gch();
      }
      if((ch()=='*')&&(line[lptr+1]=='/'))
      lptr=lptr+2;
    }
    else putres(gch());
  }
  putres(0);
  strcp(line,rline);
  lptr=0;
  if(amatch("#define",7))
  {
    addmac();
    rline[0]=0;
  }
  else if(lptr=0,amatch("#include",8))
  {
    doinclude();
    rline[0]=0;
  }
}
func doinclude()
{
  var [160]char:newn;
  var int:k,c,too_long;
  var int:delim;
  too_long=0;
  sb();
  if(ch()=='"'){delim='"';gch();}
  else if(ch()=='<'){delim='>';gch();}
  else delim=0;
  for(k=0;k<159&&ch()&&!isblank(ch())&&ch()!=delim;k++)
  {
    if(ch()==92)
    {
      gch();
      if(!ch())break;
      c=gch();
      if(c=='n')c=10;
      else if(c=='t')c=9;
      else if(c=='b')c=8;
      else if(c=='f')c=12;
      newn[k]=c;
    }
    else
    {
      c=gch();
      newn[k]=c;
    }
  }
  newn[k]=0;
  if(ch()&&!isblank(ch())&&ch()!=delim)
  {
    too_long=1;
    error("include path too long");
    while(ch()&&!isblank(ch())&&ch()!=delim)gch();
  }
  if(too_long)return;
  /*fprintf(stderr,"new name:%s\n",newn);*/
  if(iptr>=MAXINC-2)
  error("too many nested #include");
  else
  {
    ++iptr;
    if(!(ifiles[iptr]=ifil=fopen(newn,"r")))
    {
      error("error opening %s\n",newn);
      ifil=ifiles[--iptr];
    }
  }
}
func process()
{
  while(!iseof)
  {
    insline();
    prep();
    fputs(rline,ofil);fputc(10,ofil);
  }
}
func main(argc:int,argv:**char)
{
  var int:i,is_out,is_in;
  var *char: outn,inn;
  strptr=0;
  macptr=1;
  errcnt=0;
  iseof=0;
  isinp=1;
  is_in=is_out=0;
  outn=0;
  inn=0;
  iptr=0;
  for(i=1;i<argc;i++)
  {
    if(!is_in)
    {inn=argv[i];is_in=1;}
    else if(!is_out)
    {outn=argv[i];is_out=1;}
  }
  if(inn)
  {
    if(!(ifil=fopen(inn,"r")))
    {fprintf(stderr,"err in");exit(1);}
  }
  else
  ifil=stdin;
  if(outn)
  {
    if(!(ofil=fopen(outn,"w")))
    {fprintf(stderr,"err out");exit(1);}
  }
  else
  ofil=stdout;
  ifiles[0]=ifil;
  var int:c;
  process();
  
  if(inn)fclose(ifil);
  if(outn)fclose(ofil);
  if(errcnt)return 1;
  return 0;
}
