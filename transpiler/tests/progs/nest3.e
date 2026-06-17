/* 3-deep call-free nesting: a+(b+(c+(d+e))) -- exercises the depth-2 save
   register (RG_E). Verifies saves more than two deep stay in registers. */
func main()
{
  var int:a;var int:b;var int:c;var int:d;var int:e;
  a=10;b=10;c=10;d=6;e=6;
  return a+(b+(c+(d+e)));
}
