#!/usr/bin/perl
use File::Basename;
use File::Temp qw(tempfile);

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
  print "$LPP $enames[$i] | $LANGC > $snames[$i]\n";
  ($tmpfh,$tmpname)=tempfile();
  open($lppfh,'-|',$LPP,$enames[$i]) or die "cannot run $LPP: $!";
  while(<$lppfh>)
    {
    print $tmpfh $_;
    }
  close($lppfh) or die "$LPP failed for $enames[$i]";
  close($tmpfh);
  $pid=fork();
  die "fork failed: $!" unless defined $pid;
  if($pid==0)
    {
    open(STDIN,'<',$tmpname) or die "cannot read $tmpname: $!";
    open(STDOUT,'>',$snames[$i]) or die "cannot write $snames[$i]: $!";
    exec {$LANGC} $LANGC;
    die "cannot exec $LANGC: $!";
    }
  waitpid($pid,0);
  unlink($tmpname);
  die "$LANGC failed for $enames[$i]" if $?;
  }
$slist="@snames";
print $slist . "\n";
print "gcc -o $outname @snames\n";
system('gcc','-o',$outname,@snames)==0 or die "gcc failed";
