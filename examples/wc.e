/* wc -- count lines, words and characters on standard input.
   A small self-contained utility written in UPLNC (M7 "proof it's real").
   Build:  perl src/langdrv.pl -march=x86_64 examples/wc.e -o wc
   Run:    ./wc < somefile   ->   "<lines> <words> <chars>"            */

func iswhite(c:int)
{
  return (c==32)||(c==9)||(c==10)||(c==13)||(c==12)||(c==11);
}

func main()
{
  var int:c;
  var int:nl;var int:nw;var int:nc;
  var int:inword;
  nl=0;nw=0;nc=0;inword=0;
  while((c=getchar())>=0)
  {
    nc=nc+1;
    if(c==10)nl=nl+1;
    if(iswhite(c))
      inword=0;
    else
    {
      if(!inword)nw=nw+1;
      inword=1;
    }
  }
  printf("%d %d %d\n",nl,nw,nc);
  return 0;
}
