#!/usr/bin/perl

################################################################################
#
#
#
#
#################< Configure parameter variables as needed >####################
#
# Get options passed to program.

#use strict;
#use warnings;
use Getopt::Std;
use POSIX qw(ceil floor);
use Net::SMTP;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use Array::Unique;

# Here are the valid argument options and what they get set to.
# -e <exp_par>, -f <volume_set_name_file> ,-h,	sets the
# following varibles $opt_e, $opt_f, $opt_h, $opt_w, $opt_t, $opt_m, $opt_z

$opt_ok = getopts("d:htmup:s:");

if ( !$opt_ok ) { &ShowHelp; }

if ($opt_s) { $server = $opt_s; }

if ($opt_f) { $filename = $opt_f; }

if ($opt_p) { $package = $opt_p; }

if ($opt_d) { $device = $opt_d; }

#if (($opt_h) || ($package eq "") || ($filename eq ""))  { &ShowHelp; }

#################< Change/set these constants as needed >######################
#
( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) =
  localtime(time);

$mon  = $mon + 1;
$year = $year - 100;

if ( length($hour) eq 1 ) { $hour = "0$hour"; }
if ( length($min)  eq 1 ) { $min  = "0$min"; }
if ( length($mday) eq 1 ) { $mday = "0$mday"; }
if ( length($mon)  eq 1 ) { $mon  = "0$mon"; }

@DAY = ( "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" );
$aday = $DAY[$wday];

#################< Change/set these variables as needed >#######################
#
$path       = "/root/lgbarn/snapshots/";
$start_time = "$mon$mday$year-$hour$min";
$log_name   = "$0-$filename-$start_time.log";
$tmp        = ".tmp";

################################################################################
# >> Main program starts here
#
$logFile = "$path$log_name";
$tmpFile = "$path$tmp";

#logger(
#    "\n=====================================================================\n"
#);
#logger(">>>> Start $0 process for '$filename' at $hour:$min\n\n");

if ($opt_d) {
    ( $result, $retval ) = cmd("multipath -l");
    @useResult = split( /[\r\n]/, $result );
    foreach $line (@useResult) {
        if ( $line =~ /^${device}\s+\(/ ) {
            #$device = $1;
            ( $result, $retval ) = cmd("multipath -l $device");
            @deviceResult = split( /[\r\n]/, $result );
            print "multipath -f ${device}\n";
            foreach $deviceLine (@deviceResult) {
              if ( $deviceLine =~ /(\d+:\d+:\d+:\d+)\s+(\w+)\s+/ ){
                  $scsiDevice = $1;
                  $blockDevice = $2;
                  print ("blockdev --flushbufs /dev/$blockDevice\n");
                  print ("echo 1 > /sys/class/scsi_device/$scsiDevice/device/delete\n");
               }
           }
         }
            #($result,$retval) = cmd("cli createvlun ${lun} auto ${server}\n");
        }
    }


#$full_filename = "/root/lgbarn/snapshots/$filename";
#
#open (VOLUME_SET_FILE, $full_filename) || die "can't open $full_filename:$!\n";
#
#
## Process each volume set
#
#while ($volume_set=<VOLUME_SET_FILE>) {
#   if ($opt_t) { logger("\nline is $volume_set\n\n"); }
##
#   if ($volume_set =~ m/(\S+)/) {
#     $vs = $1;
#     if ($opt_t) { logger("volume set is $vs\n\n"); }
#
#
#     ($result,$retval) = cmd("cli showvvset $vs");
#
#
#     @members = ($result =~ m/(\S+)/g);
#
#     if ($opt_t) { logger("there are $#members members\n\n"); }
#
#       $read_snap = "ro";
#       $write_snap = "rw";
#
#       $read_pairs = "";
#       $write_pairs = "";
#
#       for $i (5 .. $#members) {
#         if ($opt_t) { logger("member is $members[$i]\n\n"); }
#         $base = $members[$i];
###################### Start test section #############################
#	 @baseParse = split(/_/,$base);
#	 $srv = $baseParse[0];
#	 $pkg = $baseParse[1];
#	 $newPkg = "$package";
#	 $vg = $baseParse[2];
#	 $rest = $baseParse[3];
#	 $vgNum = $baseParse[2];
#	 $vgNum=~s/vg//g;
#	 $vgNum+=100;
#	 $newName="${srv}_${newPkg}_vg${vgNum}_${rest}";
#	 $snapsToDelete="${srv}_${newPkg}*";
###################### End test section #############################
#
#         $read_pairs =  $read_pairs . "$base:$newName.$read_snap ";
#         $write_pairs = $write_pairs . "$newName.$read_snap:$newName.$write_snap ";
#       }
#
#       if ($opt_d) {
#         ($result,$retval) = cmd("cli removevv -f -snaponly -pat $snapsToDelete");
#       }
#
#       if ($opt_w ) {
#         ($result,$retval) = cmd("cli creategroupsv -ro -f -exp 180d $read_pairs");
#         ($result,$retval) = cmd("cli creategroupsv -f -exp 180d $write_pairs");
#       }
#
#
#
#   }
#   else
#   {
#   logger("volume set not found");
#   };
#
#}

( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) =
  localtime(time);

$mon  = $mon + 1;
$year = $year - 100;

if ( length($hour) eq 1 ) { $hour = "0$hour"; }
if ( length($min)  eq 1 ) { $min  = "0$min"; }
if ( length($mday) eq 1 ) { $mday = "0$mday"; }
if ( length($mon)  eq 1 ) { $mon  = "0$mon"; }

@DAY = ( "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" );
$aday = $DAY[$wday];

#logger(
#    "\n>>>> End   $0 process for '$filename' Max RC $max_retval at $hour:$min\n"
#);
#logger(
#    "=====================================================================\n");
#
if ( $opt_m || $max_retval ) { &SendMail; }

exit $max_retval;

# >> Main program ends here
################################################################################
sub cmd {
    my $cmd = shift;
    #logger("$cmd\n");
    my $result = `$cmd 2>&1`;
    #logger("$result\n");
    my $retval = ( $? >> 8 );
    #logger("return code $retval\n\n");
    $max_retval = max $max_retval, $retval;
    return $result, $retval;
}

#sub logger {
#    my $logmessage = shift;
#    #open my $log, ">>", "$logFile" or die "Could not open $logFile: $!";
#    print $log $logmessage;
#}

sub SendMail {
    #
    my $mailServer    = 'smtp.ams360.local';
    my $mailSender    = 'dfw-infrastructure@vertafore.com';
    my $mailRecipient = 'dfw-infrastructure@vertafore.com';
    my $mailcc        = 'john.smith@AOL.com';
    my $mailSubject   = "'$log_name'";

    local $/ = undef;
    open( LGFH, "$logFile" );
    binmode LGFH;
    $string = <LGFH>;
    close LGFH;

 #my $mailBody      = "\nHere are the log file contents of '$logFile'\n$string";
 #
 #$mailmsg=Net::SMTP->new($mailServer);
 #$mailmsg->mail($mailSender);
 #$mailmsg->to($mailRecipient);
 #$mailmsg->cc($mailcc);
 #$mailmsg->data();
 #$mailmsg->datasend("To: $mailRecipient\n");
 #$mailmsg->datasend("cc: $mailcc\n");
 #$mailmsg->datasend("Subject: $mailSubject\n\n");
 #$mailmsg->datasend("$mailBody");
 #$mailmsg->dataend();
 #$mailmsg->quit;
}
#
################################################################################
#
# Print Help screen
#
sub ShowHelp {
    print "\n";
    print
"\tUsage: perl $0 -p <pkg_name> -f <volume_set_file> [-d] [-w] [-t] [-m] [-h]\n\n";
    print
      "\tWhere:  -f <volume_set_file> is the file with source volume sets \n";
    print "\t       [-s]  Server to mount snapshots to\n";
    print "\t       [-m]  Specify to mount snapshots\n";
    print "\t       [-u]  Specify to unmount snapshots\n";
    print "\t       [-p]  Specify new package name for snapshots\n";
    print "\t       [-h]  To display this output.\n\n";
    print
"\tThis routine will create RO and optionally RW snapshots of volume sets\n";
    print "\tin the <volume_set_file>.\n";
    exit;
}
#
################################################################################

