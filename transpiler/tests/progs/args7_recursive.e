func f(a:int,b:int,c:int,d:int,e:int,g:int,h:int){if(a>6)return f(a-1,b,c,d,e,g,h);return h;}
func main(){return f(40,0,0,0,0,0,42);}
