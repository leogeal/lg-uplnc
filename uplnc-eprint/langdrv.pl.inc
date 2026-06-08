\begin{verbatim}
#!/usr/bin/perl
use File::Basename;

$LPP='./lpp1';
$LANGC='./langc';
$outname='a.out';
$numArgs=$#ARGV+1;
@enames=();
@snames=();
print "number of arguments:$numArgs\n";
for($i=0;$i<$numArgs;$i++)
  {
  print "\$ARGV[$i]=$ARGV[$i]\n";
  if($ARGV[$i] eq '-o')
    {
    if($i>=$numArgs-1)
      {
      print "ending with \"-o\"\n";
      exit 1;
      }
    $outname=$ARGV[$i+1];
    $i+=1;
    }
  else
    {
    push(@enames,$ARGV[$i]);
    ($xname,$xpath,$xsuffix)=fileparse($ARGV[$i],'\..*');
    print "\$xname=$xname, \$xpath=$xpath, \$xsuffix=$xsuffix, \n";
    $tsname=$xpath . $xname . '.s';
    print "\$tsname=$tsname\n";
    push(@snames,$tsname);
    }
  }
print("\$0=$0\n");
print "\@enames=@enames\n";
print "\@snames=@snames\n";
print "\$outname=$outname\n";
#$tt= $outname . "asdf\n";
#print $tt;
$nfiles=$#enames+1;
print "$nfiles files to compile\n";
for($i=0;$i<$nfiles;$i++)
  {
  $thecmd="$LPP $enames[$i] | $LANGC > $snames[$i]";
  print $thecmd . "\n";
  `$thecmd`;
  }
$slist="@snames";
print $slist . "\n";
$newcmd="gcc -o $outname @snames ";
print $newcmd . "\n";
`$newcmd`;
\end{verbatim}
