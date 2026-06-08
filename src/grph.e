/*                    -*- C -*-                                            */
/*            The language compiler by E.V., (C) 2003                   */
/* graphing module */
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
var *int:grphxof;
struct ssq
{
  [NAMESIZE]char name;
  int x,y;
  *snamelist nmlst;
  func draw;
};
#define SQNUM 300
var grsq:[SQNUM]ssq;
var grsqbx,grsqby:int;
var int:grsqptr;
var grsqx,grsqy,grsqstepx,grsqstepy:int;
func grsqadd(*char:name,*snamelist:nmlst)
{
  if(grsqptr>=SQNUM){error("graphing table full");return;}
  var int:i;
  strcp(grsq[grsqptr].name,name);
  grsq[grsqptr].nmlst=nmlst;
  grsq[grsqptr].x=grsqx;
  grsq[grsqptr].y=grsqy;
  grsqx=grsqx+grsqstepx;
  grsqy=grsqy+grsqstepy;
  if(grsqstepx>0&&grsqx>/*-grsqy*/grsqbx)
  {grsqstepy=grsqstepx;grsqstepx=0;grsqbx=grsqbx/*+11*/;}
  else if(grsqstepx<0&&-grsqx>/*grsqy*/grsqbx)
  {grsqstepy=grsqstepx;grsqstepx=0;grsqbx=grsqbx+11;}
  else if(grsqstepy>0&&grsqy>/*grsqx*/grsqby)
  {grsqstepx=-grsqstepy;grsqstepy=0;grsqby=grsqby/*+11*/;}
  else if(grsqstepy<0&&-grsqy>grsqby/*-grsqx*/)
  {grsqstepx=-grsqstepy;grsqstepy=0;grsqby=grsqby+11;}
  
  return grsqptr++;
}
func grsqfind(*char s)
{
  var int:i;
  for(i=0;i<grsqptr;i++)
  if(strid(grsq[i].name,s))
    return i;
  return i;
}
method ssq.draw()
{
  fprintf(grphxof,"set arrow from %d,%d to %d,%d nohead\n",x-5,y-5,x+5,y-5);
  fprintf(grphxof,"set arrow from %d,%d to %d,%d nohead\n",x+5,y-5,x+5,y+5);
  fprintf(grphxof,"set arrow from %d,%d to %d,%d nohead\n",x+5,y+5,x-5,y+5);
  fprintf(grphxof,"set arrow from %d,%d to %d,%d nohead\n",x-5,y+5,x-5,y-5);
  fprintf(grphxof,"set label \"%s\" at %d,%d center font\"Helvetica,5\"\n",name,x,y);
}
func printgraph()
{
  var of:*int;
  if(!(of=fopen(graphname,"w")))
  {
    fprintf(stderr,"can't open graph file %s\n",graphname);
    return;
  }
  grsqbx=0;
  grsqby=0;
  grphxof=of;
  grsqptr=0;
  grsqx=grsqy=0;
  grsqstepx=11;grsqstepy=0;
  fprintf(grphxof,"set terminal postscript color solid\n");
  fprintf(grphxof,"set noborder\n");
  fprintf(grphxof,"set noxtics\n");
  fprintf(grphxof,"set noytics\n");
  fprintf(grphxof,"set nokey\n");
  var *ssymlist:lst;
  for(lst=glbsymtab.lst;lst;lst=lst->next)
  {
    if(lst->sym.nmlst)
    {
      var int :i;
      i=grsqadd(lst->sym.name,lst->sym.nmlst);
      /*grsq[i].draw();*/
    }
    if(0)fprintf(of,"%-10s\t%d\t%d\n {",lst->sym.name,
        lst->sym.line,
        lst->sym.sort);
    if(0&&lst->sym.nmlst)
    {
      var *snamenode:q;
      q=lst->sym.nmlst->lst;
      while(q)
      {
        fprintf(of,"%s",q->name);
        if(q->next)fprintf(of,",");
        q=q->next;
      }
    }
    if(0)fprintf(of,"}\n");
  }
  var int:i;
  for(i=0;i<grsqptr;i++)
  {
    var *snamenode:q;
    var int:j;
    for(q=grsq[i].nmlst->lst;q;q=q->next)
    {
      j=grsqfind(q->name);
      if(j<grsqptr)
      {
        fprintf(grphxof,"set arrow from %d,%d to %d,%d nohead lt 2 lw 0.2\n",
            grsq[i].x,grsq[i].y,grsq[j].x,grsq[j].y);
      }
    }
  }
  for(i=0;i<grsqptr;i++)
  {
    grsq[i].draw();
  }
  fprintf(grphxof,"plot [%d:%d][%d:%d] \"dat0.dat\"",-grsqbx-11,grsqbx+11,
      -grsqby-31,grsqby+31);
  fclose(of);
}

