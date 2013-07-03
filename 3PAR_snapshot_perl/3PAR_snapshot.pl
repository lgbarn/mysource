#!/usr/bin/perl

#############################################################
#
# Date: May 23, 2013
#
# Author: Luther Barnum
#
# Description: This script is used to perform a full snapshot of existing 
#   Lun by parsing configuration files. This script should normally be 
#   called by cron with options specifying source and destination.
#   This script is a reqrite of the previous Perl script.
# 
#
#############################################################
# Get options passed to program.

#use strict;
#use warnings;

use Getopt::Std;
use POSIX qw(ceil floor);
use Net::SMTP;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use Array::Unique;
use THREEPAR;
use Multipath;
use LVM;
use IPC::Cmd qw(can_run run run_forked);
use StorageLX;

# Here are the valid argument options and what they get set to.
# -e <exp_par>, -f <volume_set_name_file> ,-h,	sets the
# following varibles $opt_e, $opt_f, $opt_h, $opt_w, $opt_t, $opt_m, $opt_z

$opt_ok = getopts("edhwtms:p:f:");

if ( !$opt_ok ) { &ShowHelp; }

#if ($opt_f) { $filename = $opt_f; }

if ($opt_p) { $package = $opt_p; }

if ($opt_s) { $source = $opt_s; }

if (   ($opt_h)
    || ( $package eq "" )
    || ( $source  eq "" ) )
{
    &ShowHelp;
}

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
$path       = "/var/adm/";
$start_time = "$mon$mday$year-$hour$min";
$log_name   = "$package-$start_time.log";
$tmp        = ".tmp";

################################################################################
# >> Main program starts here
#
$logFile = "$path$log_name";
$tmpFile = "$path$tmp";

logger(
    "\n=====================================================================\n"
);
logger(">>>> Start $0 process for '$filename' at $hour:$min\n\n");

$full_filename = "/var/adm/$filename";

open( VOLUME_SET_FILE, $full_filename ) || die "can't open $full_filename:$!\n";

### Initialization Section ###
tie @vg_disks, 'Array::Unique';
$lvm = LVM->new();
$lvm->set_src($source);
$lvm->set_pkg($package);
$lvm->get_all_proc_mounts();
$lvm->parse_fstab();
$lvm2 = LVM2->new();
$mp   = Multipath->new();

$server = `uname -n`;
$server =~ s/\..*//g;

$pkg_map = "/etc/snapshots.conf";
### Parse Package Map file

tie @src_vgs, 'Array::Unique';
tie @pkg_vgs, 'Array::Unique';
########################################

### Step 1 Remove log files ###
#print("rm -f *.log");
################################
( $cmd, $result, $retval ) = cmd("/bin/sleep 1\n");

### Step 2 Unmount Source Filesystems ###
#if ($opt_e) {
#### Step 2 Unmount Source Filesystems ###
#    foreach my $mount ( @{ $lvm->get_src_mountpoints() } ) {
#        print("/sbin/fuser -km $mount\n");
#        print("/bin/umount $mount\n");
#    }
#    print("/bin/sleep 5\n");
###########################################
#    #
#}
#### Step 3 Unmount Package to be Refreshed ###
@pkg_vgs = @{ $lvm->get_pkg_fstab_vgs() };
if ($opt_d) {
    foreach my $mount ( @{ $lvm->get_pkg_mountpoints() } ) {
        ( $cmd, $result, $retval ) = cmd("/sbin/fuser -km $mount\n");
        ( $cmd, $result, $retval ) = cmd("/bin/umount $mount\n");
        ( $cmd, $result, $retval ) = cmd("/bin/grep $mount /proc\n");
        if ( !$retval ) {
            logger("/bin/umount $mount FAILED\n");
            die "/bin/umount $mount FAILED\n";
        }
    }
    foreach my $vg ( @{ $lvm->get_pkg_vgs() } ) {
        ( $cmd, $result, $retval ) = cmd("/sbin/vgchange -a n $vg\n");
        if ($retval) {
            logger("$cmd FAILED\n");
            die "$cmd FAILED\n";
        }
        ( $cmd, $result, $retval ) = cmd("/sbin/vgremove -ff $vg\n");
        if ($retval) {
            logger("$cmd FAILED\n");
            die "$cmd FAILED\n";
        }
        ( $cmd, $result, $retval ) = cmd("/bin/sleep 1\n");
    }
    foreach my $vg ( @{ $lvm->get_pkg_vgs() } ) {
        open( DMSETUP_INFO_PIPE, "dmsetup info | " );
        while (<DMSETUP_INFO_PIPE>) {
            if (/Name:\s+(${vg}-lvol.+)/) {
                $dm_lvol = $1;
                ( $cmd, $result, $retval ) = cmd("dmsetup remove $dm_lvol\n");
            }
        }
        close(DMSETUP_INFO_PIPE);
    }

}
#########################################

#################################################

### Step 4 Remove Snapshot Devices from System ###

if ($opt_d) {
    open( PKG_MAP, "< $pkg_map" );
    while (<PKG_MAP>) {
        s/#.*//g;
        if (/disk:((\w+)_(vg\w+)_\w+):(($package)_(vg\w+)_\w+)/) {
            $src_dsk = $1;
            $src_pkg = $2;
            $src_vg  = $3;
            $dst_dsk = $4;
            $dst_pkg = $5;
            $dst_vg  = $6;
            push( @pkg_disks, "${dst_dsk}" );
        }
    }
    foreach $device (@pkg_disks) {
        logger( "multipath -l $device \n" );
        @multipath = `multipath -l ${device}`;
        foreach (@multipath) {
            if (/(\d+:\d+:\d+:\d+)\s+(\w+)\s+/) {
                $scsiDevice  = $1;
                $blockDevice = $2;
                ( $cmd, $result, $retval ) =
                  cmd("blockdev --flushbufs /dev/$blockDevice\n");
                ( $cmd, $result, $retval ) = cmd("sleep 2\n");
                ( $cmd, $result, $retval ) = cmd(
"echo 1 > /sys/class/scsi_device/$scsiDevice/device/delete\n"
                );
                ( $cmd, $result, $retval ) = cmd("sleep 1\n");
            }
        }
        close(MULTIPATH);
        ( $cmd, $result, $retval ) = cmd("sleep 1\n");
        ( $cmd, $result, $retval ) = cmd("multipath -f ${device}\n");
    }
}
####################################################

### Step 5 Unexport Luns from 3PAR ###

if ($opt_d) {
    open( PKG_MAP, "< $pkg_map" );
    while (<PKG_MAP>) {
        s/#.*//g;
        if (/disk:((\w+)_(vg\w+)_\w+):(($package)_(vg\w+)_\w+)/) {
            $src_dsk = $1;
            $src_pkg = $2;
            $src_vg  = $3;
            $dst_dsk = $4;
            $dst_pkg = $5;
            $dst_vg  = $6;
            push( @snap_list, "${dst_dsk}" );
        }
    }
    open( SHOWVLUN_PIPE, "cli showvlun -t -host $server |" );
    while (<SHOWVLUN_PIPE>) {
        if (/\s+(\d+)\s+(\w+).*\s+host/) {
            chomp();
            $vlun_lunid = $1;
            $vlun_name  = $2;
            chomp($vlun_lunid);
            chomp($vlun_name);
            push( @pkg_disks, $vlun_name );
            $remove_vlun_cmd =
              sprintf("cli removevlun -f  $vlun_name $vlun_lunid $server\n");
            $remove_vlun_cmd =~ s/\s+/ /g;
            $remove_vlun_cmds{$vlun_name} = $remove_vlun_cmd;
        }
    }

    foreach $vlun (@snap_list) {
        ( $cmd, $result, $retval ) = cmd("$remove_vlun_cmds{$vlun}\n");
        ( $cmd, $result, $retval ) = cmd("sleep 5\n");
    }

    open( PKG_MAP, "< $pkg_map" );
    while (<PKG_MAP>) {
        s/#.*//g;
        if (/disk:((\w+)_(vg\w+)_\w+):(($package)_(vg\w+)_\w+)/) {
            $src_dsk = $1;
            $src_pkg = $2;
            $src_vg  = $3;
            $dst_dsk = $4;
            $dst_pkg = $5;
            $dst_vg  = $6;
            push( @snap_list, "${dst_dsk} ${dst_dsk}.ro" );
        }
    }
    $snap_disks = join( " ", @snap_list );
    ( $cmd, $result, $retval ) =
      cmd("cli removevv -f -snaponly -cascade $snap_disks\n");

}

####################################################

### Step 6 Perform Snapshot ###
# Process each volume set

if ($opt_e) {
    open( PKG_MAP, "< $pkg_map" );
    while (<PKG_MAP>) {
        s/#.*//g;
        if (/disk:((\w+)_(vg\w+)_\w+):(($package)_(vg\w+)_\w+)/) {
            $src_dsk = $1;
            $src_pkg = $2;
            $src_vg  = $3;
            $dst_dsk = $4;
            $dst_pkg = $5;
            $dst_vg  = $6;
            push( @src_disks,         $src_dsk );
            push( @pkg_disks,         $dst_dsk );
            push( @src_vgs,           $src_vg );
            push( @pkg_vgs,           $dst_vg );
            push( @snapshot_ro_pairs, "${src_dsk}:${dst_dsk}.ro" );
            push( @snapshot_rw_pairs, "${dst_dsk}.ro:${dst_dsk}" );
        }
    }
    $rw_pairs = join( " ", @snapshot_rw_pairs );
    $ro_pairs = join( " ", @snapshot_ro_pairs );
    ( $cmd, $result, $retval ) = cmd("cli creategroupsv -ro $ro_pairs\n");
    ( $cmd, $result, $retval ) = cmd("cli creategroupsv $rw_pairs\n");
}
####################################################

### Set WWN for Snapshot Devices and export to server###

if ($opt_e) {
    open( PKG_MAP, "< $pkg_map" );
    while (<PKG_MAP>) {
        s/#.*//g;
        if (/disk:((\w+)_(vg\w+)_\w+):(($package)_(vg\w+)_\w+)/) {
            $src_dsk = $1;
            $src_pkg = $2;
            $src_vg  = $3;
            $dst_dsk = $4;
            $dst_pkg = $5;
            $dst_vg  = $6;
            push( @rw_disks, "${dst_dsk}" );
        }
    }
    foreach $vlun (@rw_disks) {
        $wwid = $mp->get_wwid_from_alias("$vlun");
        $wwid =~ s/35000/5000/g;
        ( $cmd, $result, $retval ) = cmd("cli setvv -wwn $wwid $vlun\n");
        ( $cmd, $result, $retval ) = cmd("sleep 1\n");
        ( $cmd, $result, $retval ) = cmd("cli createvlun $vlun auto $server");
        ( $cmd, $result, $retval ) = cmd("sleep 1\n");
    }
##### Start Lock of LVM #####
    $lvm2->restrict_lvm_to_active_vgs();
    chdir("/tmp/lvmtmp");
}
########################################################

####################################

### Step 9 Rescan Server for devices ###
( $cmd, $result, $retval ) = cmd("rescan-scsi-bus.sh -l\n");
( $cmd, $result, $retval ) = cmd("sleep 15\n");
( $cmd, $result, $retval ) = cmd("multipath -F\n");
( $cmd, $result, $retval ) = cmd("sleep 15\n");
( $cmd, $result, $retval ) = cmd("multipathd -r\n");
( $cmd, $result, $retval ) = cmd("sleep 15\n");
( $cmd, $result, $retval ) = cmd("multipath -F\n");
( $cmd, $result, $retval ) = cmd("sleep 15\n");
( $cmd, $result, $retval ) = cmd("multipath -v2\n");
( $cmd, $result, $retval ) = cmd("sleep 15\n");
#############################################

### Step 10 Import Snapshot Volumes and Activate###

if ($opt_e) {
    tie @disks,   'Array::Unique';
    tie @mpaths,  'Array::Unique';
    tie @dst_vgs, 'Array::Unique';
    open( PKG_MAP, "< $pkg_map" );
    while (<PKG_MAP>) {
        s/#.*//g;
        if (/disk:((\w+)_(vg\w+)_\w+):(($package)_(vg\w+)_\w+)/) {
            $src_dsk = $1;
            $src_pkg = $2;
            $src_vg  = $3;
            $dst_dsk = $4;
            $dst_pkg = $5;
            $dst_vg  = $6;
            push( @mpaths,  "/dev/mapper/${dst_dsk}" );
            push( @disks,   "${dst_dsk}" );
            push( @dst_vgs, "${dst_vg}" );
        }
    }
    $lvm2->create_local_lvm(@mpaths);
    $lvm2->add_mpaths_to_lvm(@disks);

    foreach $vg (@dst_vgs) {

        #@vgdisks     = [];
        #@new_vgdisks = [];
        tie @vgdisks,     'Array::Unique';
        tie @new_vgdisks, 'Array::Unique';
        @vgdisks = grep( /$vg/, @disks );
        foreach $disk (@vgdisks) {
            $disk =~ s,^,/dev/mapper/,g;
            push( @new_vgdisks, $disk );
        }
        $disks_to_import = join( " ", @new_vgdisks );
        ( $cmd, $result, $retval ) =
          cmd("vgimportclone --basevgname $vg $disks_to_import\n");
        if ($retval) {
            logger("$cmd  FAILED\n");
            die "$cmd FAILED\n";
        }

        #( $cmd, $result, $retval ) = cmd("vgchk $vg\n");
        #if ($retval) {
        #    logger("$cmd  FAILED\n");
        #    die "$cmd FAILED\n";
        #}
    }

    ( $cmd, $result, $retval ) = cmd("rm -rf /tmp/lvmtemp");
    $lvm2->add_mpaths_to_lvm(@mpaths);
    delete $ENV{'LVM_SYSTEM_DIR'};

    foreach $vg (@dst_vgs) {
        ( $cmd, $result, $retval ) = cmd("vgchange -a y $vg\n");
        if ($retval) {
            logger("$cmd  FAILED\n");
            die "$cmd FAILED\n";
        }
        ( $cmd, $result, $retval ) = cmd("vgcfgbackup $vg\n");
        if ($retval) {
            logger("$cmd FAILED\n");
            die "$cmd FAILED\n";
        }
    }
}

########################################

### Step 12 Mount Snapshot ##

if ($opt_e) {
    foreach my $mount ( @{ $lvm->get_pkg_fstab_mountpoints() } ) {
        ( $cmd, $result, $retval ) = cmd("mount $mount\n");
    }

########################################

}

########################################

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

logger(
    "\n>>>> End   $0 process for '$filename' Max RC $max_retval at $hour:$min\n"
);
logger(
    "=====================================================================\n");

if ( $opt_m || $max_retval ) { &SendMail; }

exit $max_retval;

# >> Main program ends here
################################################################################
sub cmd {
    my $local_cmd = shift;
    logger("$local_cmd\n");
    $cmd_stats = run_forked($local_cmd) || die "$local_cmd failed: $?\n";
    my $result = ${$cmd_stats}{merged};
    logger("$result\n");
    my $retval = ${$cmd_stats}{exit_code};
    logger("return code $retval\n\n");
    return $local_cmd, $result, $retval;
}

sub logger {
    my $logmessage = shift;
    open my $log, ">>", "$logFile" or die "Could not open $logFile: $!";
    print $log $logmessage;
}

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
    print "\t       [-w]  To create RW snapshots in addition to RO snapshots\n";
    print "\t       [-t]  To turn on trace\n";
    print "\t       [-m]  To turn on email notification of the log entiries\n";
    print "\t       [-p]  Specify new package name for snapshots\n";
    print "\t       [-s]  Specify source name for snapshots\n";
    print "\t       [-h]  To display this output.\n\n";
    print
"\tThis routine will create RO and optionally RW snapshots of volume sets\n";
    print "\tin the <volume_set_file>.\n";
    exit;
}
#
################################################################################

