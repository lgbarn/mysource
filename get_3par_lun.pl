#!/usr/bin/perl

open(CLI_SHOWVV_PIPE, "cli showvv -d  $ARGV[0] | ");
while(<CLI_SHOWVV_PIPE>) {
 if(/\d+\s+(\w+)\s+RW.*--\s+(500.+)\s+20/) {
  $WWID = $2;
  $NEWWWID = lc($2);
  $VVNAME = $1;
  print "       multipath {\n";
  print "               wwid                    3$NEWWWID\n";
  print "               alias                   $VVNAME\n";
  print "       }\n";
 }
}
