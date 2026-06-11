struct box{int v; func setv; func get;};
method box.setv(x:int){v=x;}
method box.get(){return v;}
func main(){var box:b;b.setv(40);return b.get()+2;}
