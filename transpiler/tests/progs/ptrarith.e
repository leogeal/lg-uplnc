/* int* arithmetic: +, -, ptr-ptr diff, indexing, comparison. Returns 42. */
func main()
{
  var [8]int:a; var *int:p; var *int:q; var int:i; var int:s;
  for(i=0;i<8;i=i+1)a[i]=i*i;     /* 0,1,4,9,16,25,36,49 */
  p = &a[0];
  q = p + 5;                       /* &a[5], value 25 */
  s = *q;                          /* 25 */
  s = s + *(p + 2);                /* a[2]=4 -> 29 */
  s = s + p[7];                    /* a[7]=49 -> 78 */
  s = s + (q - p);                 /* ptr diff = 5 -> 83 */
  q = q - 2;                       /* &a[3], value 9 */
  s = s + *q;                      /* 9 -> 92 */
  if(p < q)s = s + 1;              /* a[0] before a[3] -> 93 */
  if(q < p)s = s + 1000;           /* false */
  return s - 51;                   /* 42 */
}
