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

# Here are the valid argument options and what they get set to.
# -e <exp_par>, -f <volume_set_name_file> ,-h,	sets the
# following varibles $opt_e, $opt_f, $opt_h, $opt_w, $opt_t, $opt_m, $opt_z

$opt_ok = getopts("dhwtmp:");

if (!$opt_ok) { &ShowHelp; }

#if ($opt_e) { $expire=$opt_e; }

if ($opt_f) { $filename=$opt_f; }

if ($opt_p) { $package=$opt_p; }

#if (($opt_h) || ($package eq "") || ($filename eq ""))  { &ShowHelp; }

#################< Change/set these constants as needed >######################
#
($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime(time);

$mon  = $mon+1;
$year = $year-100;

if (length($hour) eq 1) {$hour = "0$hour";}
if (length($min)  eq 1) {$min  = "0$min";}
if (length($mday) eq 1) {$mday = "0$mday";}
if (length($mon)  eq 1) {$mon  = "0$mon";}

@DAY = ("Sun","Mon","Tue","Wed","Thu","Fri","Sat");
$aday = $DAY[$wday];

#################< Change/set these variables as needed >#######################
#
$path="/root/lgbarn/snapshots/";
$start_time = "$mon$mday$year-$hour$min";
$log_name = "$0-$filename-$start_time.log";
$tmp=".tmp";

################################################################################
# >> Main program starts here
#
$logFile="$path$log_name";
$tmpFile="$path$tmp";

logger("\n=====================================================================\n");
logger(">>>> Start $0 process for '$filename' at $hour:$min\n\n");

$full_filename = "/root/lgbarn/snapshots/$filename";

open (VOLUME_SET_FILE, $full_filename) || die "can't open $full_filename:$!\n"; 

($result,$retval) = cmd("cli showvv -d -p -type vcopy -copyof ${package}*");
@useResult = split(/[\r\n]/, $result);
foreach $line (@useResult) {
  if ($line =~ /\d+\s+(.+)\s+RW/) {
    $lun = $1;
    ($result,$retval) = cmd("cli createvlun ${lun} auto ${server}\n");
    print("cli createvlun ${lun} auto ${server}\n");
    $vg=$lun;
    $vg=~s/.*(vg\d+).*/\1/g;
    $allVgs{$vg} =  "$allVgs{$vg}:$lun";
  }
}



($result,$retval) = cmd("cli showvv -d");
@useResult = split(/[\r\n]/, $result);
foreach $line (@useResult) {
  if ($line=~/\d+\s+(.*)\s+RW.*\s+(.+)\s+\d+-\d+-\d+\s+/) {
    $name = $1;
    $vv_wwn = "3" . lc($2);
    chomp($name);
    chomp($vv_wwn);
    $name=~s/\s+//g;
    $vvName{$name} = $vv_wwn;
    #print "$name\t,$vv_wwn\n";
  }
}

($result,$retval) = cmd("multipath -l");
@useResult = split(/[\r\n]/, $result);
foreach $line (@useResult) {
  if ($line=~/(.+)\s+\((.+)\)/) {
    $name = $1;
    $dm_wwn = lc($2);
    chomp($name);
    chomp($dm_wwn);
    $dmName{$name} = $dm_wwn;
    #print "$name\t,$dm_wwn\n";
  }
}

($result,$retval) = cmd("cat /etc/multipath.conf");
@useResult = split(/[\r\n]/, $result);
foreach $line (@useResult) {
  if ($line=~/^\s+wwid\s+(.+)/) {
    $conf_wwid=$1;
  }
  if ($line=~/^\s+alias\s+(.+)/) {
    $alias=$1;
    chomp($alias);
    chomp($conf_wwid);
    $confName{$alias} = $conf_wwid;
  }
}



foreach $key (keys %vvName) {
  if (($confName{$key}) && ($confName{$key} ne $vvName{$key})) {
    $newWwn = $confName{$key};
    $newWwn=~s/^3//g;
    ($result,$retval) = cmd("cli setvv -wwn $newWwn $key\n");
  }
}



($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime(time);

$mon  = $mon+1;
$year = $year-100;

if (length($hour) eq 1) {$hour = "0$hour";}
if (length($min)  eq 1) {$min  = "0$min";}
if (length($mday) eq 1) {$mday = "0$mday";}
if (length($mon)  eq 1) {$mon  = "0$mon";}

@DAY = ("Sun","Mon","Tue","Wed","Thu","Fri","Sat");
$aday = $DAY[$wday];

logger("\n>>>> End   $0 process for '$filename' Max RC $max_retval at $hour:$min\n");
logger("=====================================================================\n");

if ($opt_m || $max_retval) { &SendMail; }

exit $max_retval;

# >> Main program ends here
################################################################################
sub cmd {
        my $cmd = shift;
        logger("$cmd\n");
        my $result=`$cmd 2>&1`; 
        logger("$result\n");
        my $retval = ($? >> 8);
        logger("return code $retval\n\n");
        $max_retval = max $max_retval,$retval;
        return $result,$retval;
}

sub logger {
        my $logmessage = shift;
        open my $log, ">>", "$logFile" or die "Could not open $logFile: $!";
        print $log $logmessage;
}

sub SendMail
{
#
	my $mailServer    = 'smtp.ams360.local';
	my $mailSender    = 'dfw-infrastructure@vertafore.com';
	my $mailRecipient = 'dfw-infrastructure@vertafore.com';
        my $mailcc        = 'john.smith@AOL.com';
	my $mailSubject   = "'$log_name'";

        local $/=undef;       
        open  (LGFH, "$logFile" );
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
sub ShowHelp
{
   print "\n";
   print "\tUsage: perl $0 -p <pkg_name> -f <volume_set_file> [-d] [-w] [-t] [-m] [-h]\n\n";
   print "\tWhere:  -f <volume_set_file> is the file with source volume sets \n";
   print "\t       [-w]  To create RW snapshots in addition to RO snapshots\n";
   print "\t       [-t]  To turn on trace\n";
   print "\t       [-m]  To turn on email notification of the log entiries\n";
   print "\t       [-p]  Specify new package name for snapshots\n";
   print "\t       [-h]  To display this output.\n\n";
   print "\tThis routine will create RO and optionally RW snapshots of volume sets\n";
   print "\tin the <volume_set_file>.\n";
   exit;
}
#
################################################################################

