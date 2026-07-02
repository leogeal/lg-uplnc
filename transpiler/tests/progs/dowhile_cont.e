/* continue inside a do-while must jump to the condition test, not the body top.
   do{ i++; if(i<5) continue; }while(0): the body runs once, continue re-tests
   while(0) which is false -> exit with i==1.  A body-top continue target would
   loop until i==5 (the pre-fix miscompile). */
func main()
{
  var int:i;
  i=0;
  do{
    i=i+1;
    if(i<5)continue;
  }while(0);
  return i;
}
