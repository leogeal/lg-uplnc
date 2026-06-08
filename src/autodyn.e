/*                    -*- C -*-                                            */
/*       Automatic allocation/deallocation by E.V., (C) 2003               */
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
#define _DYNSIZE 100
var int:_dynsize;
var **char: _dyn_ptr;
var int:_dynw;
func chkmem();
func initdyn()
{
  _dynsize=_DYNSIZE;
  chkmem(_dyn_ptr=calloc(_dynsize,sizeof(*char)));
  _dynw=0;
}
func dyncalloc(int:nmemb,int:size)
{
  if(_dynw>=_dynsize)
  {
    _dynsize=_dynsize+_DYNSIZE;
    chkmem(_dyn_ptr=realloc(_dyn_ptr,_dynsize*sizeof(*char)));
  }
  return _dyn_ptr[_dynw++]=chkmem(calloc(nmemb,size));
}
func autodynstr(*char:s)
{
  var int :l;
  var *char:res;
  l=strlen(s);
  res=dyncalloc(l+1,sizeof(char));
  strcp(res,s);
  return res;
}
var extern *int: stderr;
func donedyn()
{
  if(_dyn_ptr)
  {
    var int:i;
    i=_dynw;
    while(i)
    {
      free(_dyn_ptr[--i]);
      /*fprintf(stderr,"freed [%d]=%d\n",i,_dyn_ptr[i]);*/
    }
    free(_dyn_ptr);
  }
}
