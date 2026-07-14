/* v has three frame accesses but would require one entry save and two return
   restores. The break-even candidate must remain in memory. Returns 42. */
func ident(x:int)
{
  return x;
}

func cold(x:int)
{
  var int:v;
  v=x;
  ident(0);
  if(x)return v;
  return v;
}

func main()
{
  return cold(42);
}
