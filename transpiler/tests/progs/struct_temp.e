/* struct temps: pre-allocated at statement level so TWO struct calls in one
   expression do not corrupt the operand stack, and a million-iteration loop
   reuses the slot (no frame leak). -> 42 */
struct pair{int a;int b;};
func mk(x:int,y:int):pair
{
  var q:pair;
  q.a=x;q.b=y;
  return q;
}
func main()
{
  var i:int = 0;
  var s:int = 0;
  var r:int = 0;
  while(i<1000000)
  {
    s=mk(i,1).b+s;        /* one temp per iteration: slot must be REUSED */
    i++;
  }
  if(s==1000000)r=r+21;
  if(mk(1,2).a+mk(3,39).b==40)r=r+21;   /* two temps in one expression */
  return r;               /* 42 */
}
