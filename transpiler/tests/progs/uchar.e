/* unsigned char: byte storage, ZERO-extended on load (0..255), promoting to a
   signed word like C -- compares/div use the signed forms on in-range values.
   Discriminates from plain char (200 stays 200, not -56); byte stores wrap.
   Also exercises const parameters (writes rejected at compile time). -> 42 */
var gu:unsigned char = 200;
func take(const c:unsigned char)
{
  return c+1;             /* param read is fine; c stays 0..255 */
}
func main()
{
  var u:unsigned char = 0;
  var s:char = 0;
  var [4]unsigned char:a;
  var p:*unsigned char;
  var r:int = 0;
  u=200;
  if(u==200)r=r+8;        /* zero-extended: 200, not -56 */
  s=200;
  if(s!=200)r=r+6;        /* plain char stays signed: -56 */
  if(u>s)r=r+6;           /* 200 > -56 */
  a[0]=255;
  if(a[0]==255)r=r+6;     /* array element via pointer path */
  p=&a[0];
  if(*p==255)r=r+5;       /* deref zero-extends */
  u=u+100;                /* 300 -> byte-stores as 44 */
  if(u==44)r=r+5;
  if(gu==200)r=r+3;       /* global unsigned char */
  if(take(41)==42)r=r+3;  /* const param usable */
  return r;               /* 42 */
}
