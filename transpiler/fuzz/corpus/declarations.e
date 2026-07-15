struct pair{int left;int right;};
func add(a:int,b:int){return a+b;}
func main()
{
  var p:pair;
  var [4]int:a;
  p.left=20;
  p.right=22;
  a[0]=add(p.left,p.right);
  return a[0];
}
