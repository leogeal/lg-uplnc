/* locals declared inside a repeatedly-entered scope, with a call in the body
   (which touches sp). The per-iteration frame must allocate and release the
   same amount -- on arm64 an 8-byte local costs a 16-byte slot, so alloc and
   release must both round to 16 or sp leaks. This checks the locals stay
   correct across the call; the unbounded-leak crash is covered separately. -> 42 */
func addone(x:int)
{
  return x+1;
}
func main()
{
  var int:i;var int:acc;
  i=0;acc=0;
  while(i<21)
  {
    var int:a;var int:b;
    a=addone(i);      /* a = i+1, computed across a call */
    b=i;
    acc=acc+(a-b);    /* each iteration adds exactly 1 -> 21 */
    i=i+1;
  }
  return acc+21;       /* 21 + 21 = 42 */
}
