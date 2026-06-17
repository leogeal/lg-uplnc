/* cat -- concatenate files (named on the command line) to standard output.
   With no file arguments, or for an argument of "-", it reads standard input.
   A small self-contained utility in UPLNC exercising main(argc,argv), fopen/
   fgetc/fclose, and fprintf(stderr,...). Exit status 1 if any file won't open.
   Build:  lpp1 cat.e | langc -march=x86_64 | gcc -no-pie -x assembler - -o cat */

var extern stderr,stdin,stdout:*int;

func catfp(fp:*int)            /* copy a stream to stdout, byte by byte */
{
  var int:c;
  while((c=fgetc(fp))>=0)putchar(c);
}

func isdash(s:*char)          /* the argument "-" means standard input */
{
  return (s[0]=='-')&&(s[1]==0);
}

func main(argc:int,argv:**char)
{
  var int:i;var int:rc;
  var *int:fp;
  rc=0;
  if(argc<2)
  {
    catfp(stdin);
    return 0;
  }
  for(i=1;i<argc;i=i+1)
  {
    if(isdash(argv[i]))
      catfp(stdin);
    else
    {
      fp=fopen(argv[i],"r");
      if(!fp)
      {
        fprintf(stderr,"cat: %s: cannot open\n",argv[i]);
        rc=1;
      }
      else
      {
        catfp(fp);
        fclose(fp);
      }
    }
  }
  return rc;
}
