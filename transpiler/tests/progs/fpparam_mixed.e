/* slice 4b: mixed params -- ints in %rdi/%rsi (integer sequence), the double in
   %xmm0 (vector sequence), each spilled to its own slot.  10+22.0+10 -> 42. */
func mix(i:int,x:double,j:int)
{
  var int:r;
  r=i+x+j;
  return r;
}
func main(){return mix(10,22.0,10);}
