/* Mandelbrot membership count on a fixed grid: double arithmetic in a tight
   escape loop (FP loads/stores, compares, mul/add). The iteration count is a
   pure function of IEEE double semantics, so one expected value serves every
   backend (qemu's softfloat matches hardware IEEE). */
#define W 320
#define H 240
#define MAXIT 64
func main()
{
  var int:px,py,it,inside,rep;
  var double:x0,y0,x,y,t;
  inside=0;
  for(rep=0;rep<20;rep=rep+1)
  {
    inside=0;
    for(py=0;py<H;py=py+1)
    {
      for(px=0;px<W;px=px+1)
      {
        x0=(px-W/2)*3.0/W-0.5;
        y0=(py-H/2)*2.4/H;
        x=0.0;y=0.0;it=0;
        while((it<MAXIT)&&(x*x+y*y<=4.0))
        {
          t=x*x-y*y+x0;
          y=2.0*x*y+y0;
          x=t;
          it=it+1;
        }
        if(it==MAXIT)inside=inside+1;
      }
    }
  }
  printf("mandel %d 20\n",inside);
  if(inside==16835)return 0;
  return 1;
}
