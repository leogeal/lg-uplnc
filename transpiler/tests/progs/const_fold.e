/* M5 constant folding: every operand here is a literal, so the whole
   expression collapses to a single constant at compile time.
   3*10 + 16/2 + 2*2 - (1<<0) + (5%4) = 30+8+4-1+1 = 42 */
func main()
{
  return 3*10 + 16/2 + 2*2 - (1<<0) + (5%4);
}
