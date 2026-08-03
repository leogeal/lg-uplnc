/* shimtest.e: the platform shim's cross-target proof. A pipe round-trip
   through full-width descriptor slots (the packed-C-int hazard the shim
   owns), poll hangup/error classification, a full-count write, and a failing
   read whose -1 must arrive sign-extended -- the exact class of bug cint.he
   exists for. Exit 42.

   Build: perl src/langdrv.pl -march=ARCH -o shimtest ide/shimtest.e ide/tshim.c */

func tsh_pipe(fds:*int);
func tsh_read(fd:int,buf:*char,n:int);
func tsh_write(fd:int,buf:*char,n:int);
func tsh_poll(fd:int,ms:int);
func tsh_close(fd:int);

func main()
{
  var [2]int:fds;
  var [16]char:buf;
  var i,r:int;
  if(tsh_pipe(fds))return 1;
  if(fds[0]==fds[1])return 2;          /* two distinct full-width values */
  for(i=0;i<8;i++)buf[i]='A'+i;
  if(tsh_write(fds[1],buf,8)!=8)return 3;
  for(i=0;i<16;i++)buf[i]=0;
  r=tsh_read(fds[0],buf,16);
  if(r!=8)return 4;
  for(i=0;i<8;i++)if(buf[i]!='A'+i)return 5;
  if(tsh_read(0-1,buf,1)>=0)return 6;  /* -1 must compare negative here */
  if(tsh_close(fds[1]))return 7;
  if(tsh_poll(fds[0],0)!=1)return 8;   /* a hangup makes EOF readable */
  if(tsh_read(fds[0],buf,1)!=0)return 9;
  if(tsh_close(fds[0]))return 10;
  if(tsh_poll(fds[0],0)>=0)return 11;  /* POLLNVAL is an error, not readable */
  return 42;
}
