#!/usr/bin/perl

  $ARGWWID = uc($ARGV[0]);
  $ARGWWID =~ s/3500/500/g;
open(CLI_SHOWVV_PIPE, "cli showvv -d |  ");
while(<CLI_SHOWVV_PIPE>) {
 if(/\d+\s+(\w+)\s+RW.*--\s+($ARGWWID)\s+20/) {
  $WWID = $2;
  $NEWWWID = lc($2);
  $VVNAME = $1;
  print "       multipath {\n";
  print "               wwid                    3$NEWWWID\n";
  print "               alias                   $VVNAME\n";
  print "       }\n";
 }
}
