/* a leaf function with scalar int locals (promoted to registers on x86_64/arm64/
   riscv) AND a floating-point ++: the FP-increment's scratch register must not be
   one of the promoted-local registers (x86_64 FINC once used %r11 = a promoted
   local, corrupting it). x and y must survive the d++. -> 42 */
func f()
{
  var int:x;var int:y;var double:d;
  x=20;y=22;d=5.0;
  d++;              /* must not clobber x or y */
  return x+y;       /* 42 if the promoted locals survived */
}
func main()
{
  return f();
}
