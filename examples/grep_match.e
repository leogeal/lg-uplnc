/* Bounded, line-oriented regular-expression subset for the grep example. */
#include "grep_match.he"

func grep_matchhere(re:*char,text:*char,icase:int);
func grep_matchstar(atom:*char,next:*char,text:*char,icase:int);
var grep_steps:int;

func grep_lineend(c:int)
{
  return (c==0)||(c==10);
}

func grep_fold(c:int)
{
  if((c>='A')&&(c<='Z'))return c+('a'-'A');
  return c;
}

func grep_atomlen(re:*char)
{
  if((re[0]==92)&&re[1])return 2;
  return 1;
}

func grep_atommatch(atom:*char,c:int,icase:int)
{
  var int:p;
  if(grep_lineend(c))return 0;
  if(atom[0]==92)p=atom[1];
  else
  {
    if(atom[0]=='.')return 1;
    p=atom[0];
  }
  if(icase)return grep_fold(p)==grep_fold(c);
  return p==c;
}

func grep_matchstar(atom:*char,next:*char,text:*char,icase:int)
{
  var int:r;
  while(1)
  {
    r=grep_matchhere(next,text,icase);
    if(r)return r;
    if(!grep_atommatch(atom,*text,icase))return 0;
    text++;
  }
}

func grep_matchhere(re:*char,text:*char,icase:int)
{
  var int:n;
  grep_steps--;
  if(grep_steps<0)return -1;
  if(!re[0])return 1;
  if((re[0]=='$')&&!re[1])return grep_lineend(*text);
  n=grep_atomlen(re);
  if(re[n]=='*')return grep_matchstar(re,re+n+1,text,icase);
  if(grep_atommatch(re,*text,icase))
    return grep_matchhere(re+n,text+1,icase);
  return 0;
}

func grep_patvalid(pattern:*char)
{
  var int:i = 0;
  if(pattern[0]=='^')i=1;
  while(pattern[i])
  {
    if(i>=GREP_PATMAX)return 0;
    if(pattern[i]=='*')return 0;
    if(pattern[i]==92)
    {
      if(!pattern[i+1])return 0;
      i=i+2;
    }
    else i++;
    if(pattern[i]=='*')i++;
  }
  return i<=GREP_PATMAX;
}

func grep_match(pattern:*char,text:*char,icase:int)
{
  var int:r;
  grep_steps=GREP_STEPMAX;
  if(pattern[0]=='^')return grep_matchhere(pattern+1,text,icase);
  while(1)
  {
    r=grep_matchhere(pattern,text,icase);
    if(r)return r;
    if(grep_lineend(*text))return 0;
    text++;
  }
}
