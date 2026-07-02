/* a ?: whose arms mix int and double must yield a double (both arms converted to
   the same register class), not silently read the wrong register. -> 42 */
func main()
{
  var int:c;var double:r;var int:acc;
  acc=0;
  c=1;r=(c?40:2.5);        /* then arm is int, result is double 40.0 */
  if(r==40.0)acc=acc+10;   /* 10 */
  c=0;r=(c?40:2.5);        /* else arm is double 2.5 */
  if(r>2.4)acc=acc+10;     /* r==2.5 -> 20 */
  c=1;r=(c?2.5:99);        /* then arm is double 2.5 */
  if(r<2.6)acc=acc+11;     /* 31 */
  c=0;r=(c?2.5:99);        /* else arm is int, result is double 99.0 */
  if(r==99.0)acc=acc+11;   /* 42 */
  return acc;
}
