func add_over(){return 2147483647+1;}
func sub_over(){return -2147483647-2;}
func mul_over(){return 1073741824*4;}
func neg_over(){return -(-2147483647-1);}
func div_over(){return (-2147483647-1)/-1;}
func shl_over(){return 1073741824<<1;}
func main()
{
  if(sizeof(int)==4)
  {
    var int:x;
    x=2147483647;
    x=x+1;
    if(x<0)return 42;
    return 1;
  }
  return (2147483647+1)>2147483647?42:1;
}
