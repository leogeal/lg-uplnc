/* slice 4b: a double parameter arrives in %xmm0 and is spilled to its slot,
   then truncated to int.  dtoi(42.0) -> 42. */
func dtoi(x:double)
{
  var int:i;
  i=x;
  return i;
}
func main(){return dtoi(42.0);}
