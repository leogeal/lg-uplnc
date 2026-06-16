/* regression: 2-deep nesting whose inner-right is a division.
   div clobbers the x86/i386 2nd save register (%rcx/%ecx) if it is used
   for the depth-1 regspill save -> the held operand must not live there. */
func main()
{
  var int:w;var int:x;var int:y;var int:z;
  w=30;x=2;y=40;z=4;
  return w+(x+(y/z));
}
