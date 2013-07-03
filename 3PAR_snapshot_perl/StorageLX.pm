=head1 OVERVIEW
As the name implies, StorageLX is designed to solve whatever needs a Moose script may
have in terms of storage interfaces.  However, the initial focus is on taking snapshots
for EVA.  It may be extended to support snapclones at some point.  These methods can 
distinguish between snapshots from another host or from the same host (the later must
be mounted uniquely from the source)

The flow of creating an EVA snapshot is as follows
 - Ensure that any past snapshot/snapshot volume is not active (else abort)(LVM)
 - If source volume is on same host, unmount source (LVM)
 - Query source volume to get multipath devices, and map devices to WWID (mpath->WWID)(LVM)
 - Lookup WWID against output of SSSU to map devices to EVA vdisks (WWID->vdisk)(EVA)
 - Using list of vdisks, create snapshot of each vdisk and present to host (EVA)
 - Perform scsi-rescan to discover the snapshot devices (LVM)
 - Lookup snap vdisks against output of SSSU to map vdisks to WWID (vdisk->WWID)(EVA)
 - Lookup WWID against multipath to get list of snap disk paths (WWID->mpath)(LVM)
 - If snapshot is on same host, adjust LVM to distinguish snap from original volume (LVM)
 - Mount snapshot and source volume (LVM)
 - If source volume is on same host, mount source volume (LVM)

Deleting an EVA snapshot is as follows
 - Query snap volume to get multipath devices, and map devices to WWID (mpath->WWID)(LVM)
 - Lookup WWID against SSSU output to get list of snap vdisks (WWID->vdisk)(EVA)
 - Unmount snapshot and deactivate/remove snapshot volume group (LVM)
 - Destroy multipath devices (LVM)
 - Using list of vdisks, unpresent/delete each snapshot vdisk (EVA)

=head1 About MOOSE
MOOSE is used to package methods and variables into objects.  These objects help to 
organize processes in a way that allows them to be used easily on the top level.
Note that methods/objects starting with "_" should be considered private, and not used 
outside the object.  All other methods/objects are available to the top level.
 - THING is a basic object with methods/objects common to all. This object is used to 
   build LVM2 and EVA (though inheritance).
 - LVM2 - specializes in managing storage (volume groups, multipath devices, and mounts).
 - EVA - interfaces with EVA via SSSU CLI (create/delete snapshots and queries).

=cut

package THING;
use Moose;
use Array::Unique;
use IPC::Cmd qw(can_run run run_forked);
$IPC::Cmd::USE_IPC_RUN = 1;
$IPC::Cmd::USE_IPC_OPEN3 = 0;
no strict;

has 'hostname' => (
    is     => 'ro',
    isa    => 'Str',
    reader => 'get_hostname',
    default   => sub { my $h=`hostname -s`; chomp $h; return $h },
    documentation => q{Hostname, defaults to this host},
    documentation => q{Handy for determining if source is on same host},
);

has '_cmd_result' => (
    is     => 'rw',
    isa    => 'Any',
    reader => '_get_cmd_result',
    writer => '_set_cmd_result',
    documentation => q{Output of command - used with _cmd},
);

has '_cmd_ret_code' => (
    is     => 'rw',
    isa    => 'Int',
    reader => '_get_cmd_ret_code',
    writer => '_set_cmd_ret_code',
    documentation => q{Return code of command - used with _cmd},
);

has 'cmd_verbose' => (
    is     => 'rw',
    isa    => 'Int',
    default   => 0,
    reader => 'get_cmd_verbose',
    writer => 'set_cmd_verbose',
    documentation => q{Value of 1 causes each command to print cmd and return/error},
);

has 'error' => (
    is     => 'rw',
    isa    => 'Int',
    reader => 'get_error',
    writer => '_set_error',
    documentation => q{Value of 1 meand fatal error},
);

has 'error_msg' => (
    is     => 'rw',
    isa    => 'Str',
    reader => 'get_error_msg',
    writer => '_set_error_msg',
    documentation => q{Error message connected with error},
);

sub BUILD {
    $ENV{'PATH'} .= ":/usr/lib64/qt-3.3/bin:/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:/root/bin:/opt/3PAR/inform_cli_3.1.1/bin";
}

sub clr_error {
    my $self = shift;

    $self->_set_error( 0 );
    $self->_set_error_msg( '' );
}

#sub _cmd {
#    my $self = shift;
#    my $cmd = shift;
#    my $result = `$cmd 2>&1`;
#    my $retval = ( $? >> 8 );
#    $self->_set_cmd_result( $result );
#    $self->_set_cmd_ret_code( $retval );
#    if( $self->get_cmd_verbose() ){
#        $self->log("CMD: $cmd");
#        $self->log("RES: $result");
#        $self->log("RET: $retval");
#    }
#    # documentation: Simple system command routine - override as needed
#    # documentation: Takes arg of string (command to run)
#}

sub _cmd {
    my $self = shift;
    my $cmd = shift;

    $cmd_stats = run_forked($cmd);

    my $result = ${$cmd_stats}{merged};
    my $retval = ${$cmd_stats}{exit_code};
    $self->_set_cmd_result( $result );
    $self->_set_cmd_ret_code( $retval );
    if( $self->get_cmd_verbose() ){
	$self->log("CMD: $cmd");
	$self->log("RES: $result");
	$self->log("RET: $retval");
    }
    # documentation: Simple system command routine - override as needed
    # documentation: Takes arg of string (command to run)
}

sub ck_cmd_error {
    my $self = shift;
    my $error_pattern = shift;
    my @pat;
    my $case_insensitve = 0;
    if( ! defined $error_pattern ){
	$error_pattern = "error";
	$case_insensitve = 1;
    }else{
	@pat = split( "/" , $error_pattern );
	if( ! $pat[0] ){
	    $error_pattern = $pat[1];		# /re-ex/
	    if( defined $pat[2] && $pat[2] eq "i" ){
		$case_insensitve = 1;		# /re-ex/i
	    }
	}else{
	    $error_pattern = $pat[0];		# "re-ex"
	}
    }

    my @res = split /^/,$self->_get_cmd_result();
    my $errors = 0;
    foreach my $line ( @res ){
        unless (  $self->get_cmd_verbose() ){
            print $line;
        }
	if( $case_insensitve){
	    if( $line =~ /$error_pattern/i ){
		$errors++;
		$self->_set_error( $errors );
		$self->_set_error_msg( $self->get_error_msg() . $line );  # append error
	    }
	}else{
            if( $line =~ /$error_pattern/ ){
                $errors++;
                $self->_set_error( $errors );
                $self->_set_error_msg( $self->get_error_msg() . $line );  # append error
            }  
	}
    }
    if( $errors ){
        return 1;
    }else{
        return 0;
    }
}

sub log {
    my $self = shift;
    my @msg = @_;
    my $msg = join "",@msg; # Supports either string or array of strings as input
    $msg=~s/\n*$//;  # Remove any pre-existing newlines, so newline in arg is optional
    print "$msg\n";
    # documentation: Simple print routine - override as needed
    # documentation: Takes args of either string or array of strings
    # documentation: Newline is optional
}


no Moose;
__PACKAGE__->meta->make_immutable;

package LVM2;
use Moose;
extends 'THING'; # inherits: hostname, _cmd, _cmd_ret_code, _cmd_result, log, error, error_msg

has 'src_hostname' => (
    is     => 'rw',
    isa    => 'Str',
    reader => 'get_src_hostname',
    writer => 'set_src_hostname',
    documentation => q{Source hostname provided as input},
);

has 'use_remote' => (
    is     => 'rw',
    isa    => 'Int',
    default   => 0,
    reader => 'get_use_remote',
    writer => 'set_use_remote',
    documentation => q{Directs LVM to use ssh to remote server for certain routines},
);

has 'fstab_mount_map' => (
    is     => 'rw',
    isa    => 'HashRef[HashRef[Str]]',
    reader => 'get_fstab_mount_map',
    writer => '_set_fstab_mount_map',
    documentation => q{HASH->HASH->STRING: Mount Points based on fstab},
    documentation => q{vg is first key, lvol is second key},
    documentation => q{Used to mount vg without need for fstab},
    documentation => q{double key supports (future) possibility of multiple vgs per package},
);

has 'fstab_options_map' => (
    is     => 'rw',
    isa    => 'HashRef[HashRef[Str]]',
    reader => 'get_fstab_options_map',
    writer => '_set_fstab_options_map',
    documentation => q{HASH->HASH->STRING: Mount options based on fstab},
    documentation => q{vg is first key, lvol is second key},
    documentation => q{Used to mount vg without need for fstab},
    documentation => q{double key supports (future) possibility of multiple vgs per package},
);

has 'mpath_wwid_map' => (
    is     => 'rw',
    isa    => 'HashRef[Str]',
    reader => 'get_mpath_wwid_map',
    writer => '_set_mpath_wwid_map',
    documentation => q{HASH->STRING: WWID based on mpath},
    documentation => q{mpath is key},
    documentation => q{Used to support process of mapping mpath to storage devices},
);

has 'mpath_scsi_devs_map' => (
    is     => 'rw',
    isa    => 'HashRef[ArrayRef]',
    reader => 'get_mpath_scsi_devs_map',
    writer => '_set_mpath_scsi_devs_map',
    documentation => q{HASH->ARRAY: list of scsi devs based on mpath},
    documentation => q{mpath is key},
    documentation => q{Used to support process of removing mpath devices},
);

has 'mpath_block_devs_map' => (
    is     => 'rw',
    isa    => 'HashRef[ArrayRef]',
    reader => 'get_mpath_block_devs_map',
    writer => '_set_mpath_block_devs_map',
    documentation => q{HASH->ARRAY: list of block devs based on mpath},
    documentation => q{mpath is key},
    documentation => q{Used to support process of removing mpath devices},
);

has 'wwid_mpath_map' => (
    is     => 'rw',
    isa    => 'HashRef[Str]',
    reader => 'get_wwid_mpath_map',
    writer => '_set_wwid_mpath_map',
    documentation => q{HASH->STRING: mpath based on wwid},
    documentation => q{wwid is key},
    documentation => q{Used to support process of adding snap mpath devices},
);

has 'lvm_conf_locked' => (
    is     => 'rw',
    isa    => 'Int',
    reader => 'get_lvm_conf_locked',
    writer => '_set_lvm_conf_locked',
    documentation => q{Used to support process of adjustingl LVM devices},
);

sub load_fstab_maps {
    my $self = shift;
    my $src_host = $self->get_src_hostname();
    my $use_remote = $self->get_use_remote();
    my %mounts;
    my %options;
    my $FSTAB;
    
    if( $use_remote ){
	$self->log( "load_fstab_maps: getting fstab from $src_host" );
	$self->_cmd( "ssh $src_host cat /etc/fstab" );
    }else{
	$self->log( "load_fstab_maps: getting fstab from localhost" );
	$self->_cmd( "cat /etc/fstab" );
    }
    my @res = split /^/,$self->_get_cmd_result();
    foreach my $line ( @res ){
	my $vg;
	my $lvol;
	next unless $line =~ /^\s*\//;
	my ($dev,$mount,$fs_type,$options,$m1,$m2) = split /\s+/,$line;
	my @dev = split "/",$dev;
	if ($dev[2] eq "mapper"){
	    ($vg,$lvol) = split "-",$dev[3];
	}else{
	    $vg = $dev[2];
	    $lvol = $dev[3];
	}
	$mounts{$vg}{$lvol} = $mount;
	$options{$vg}{$lvol} = "-t $fs_type -o $options";
    }
    $self->_set_fstab_mount_map( \%mounts );
    $self->_set_fstab_options_map( \%options );
    
    # documentation: Loads fstab_mount_map and fstab_options_map
    # documentation: May use ssh to src_host to get data
}

sub load_mpath_maps {
    my $self = shift;
    my $src_host = $self->get_src_hostname();
    my $use_remote = $self->get_use_remote();
    my %wwid;
    my %scsi_dev_array;
    my %block_dev_array;
    my %mpath;
    my $mp;

    if( $use_remote ){
        $self->log( "load_mpath_maps: getting mpath info from $src_host" );
        $self->_cmd( "ssh $src_host multipath -l" );
    }else{
        $self->log( "load_mpath_maps: getting mpath info from localhost" );
        $self->_cmd( "multipath -l" );
    }
    my @res = split /^/,$self->_get_cmd_result();
    foreach my $line ( @res ){
	if( $line=~/^(\w+) \((\w+)\)/ ){
	    $mp = $1;
	    my $ww = $2;
	    $wwid{$mp} = $ww;
	    $mpath{$ww} = $mp;
	}elsif( $line=~/(\d+:\d+:\d+:\d+)\s+(\w+)\s+/ ){
	    push @{ $scsi_dev_array{$mp} }, $1;
	    push @{ $block_dev_array{$mp} }, $2;
	}
    }
    $self->_set_mpath_wwid_map( \%wwid );
    $self->_set_mpath_scsi_devs_map( \%scsi_dev_array );
    $self->_set_mpath_block_devs_map( \%block_dev_array );
    $self->_set_wwid_mpath_map( \%mpath );

    # documentation: Loads mpath_wwid_map, mpath_scsi_devs_map and mpath_block_devs_map
    # documentation: May use ssh to src_host to get data
}

sub get_vg_lvol_names {
    my $self = shift;
    my $vg = shift;
    tie my @lvols, 'Array::Unique';

    $self->_cmd("vgdisplay -v $vg");
    my @res = split /^/,$self->_get_cmd_result();
    foreach my $line ( @res ){
	if( $line =~ m~LV Name\s+/dev/$vg/(\w+)$~ ){
	    push @lvols, $1;
	}
    }

    return @lvols;

    # documentation: Args: vg name
    # documentation: returns list of lvol names for that vg
}

sub get_vg_mpath_names {
    my $self = shift;
    my $vg = shift;
    my $src_host = $self->get_src_hostname();
    my $use_remote = $self->get_use_remote();
    tie my @mpaths, 'Array::Unique';

    if( $use_remote ){
        $self->log( "get_vg_mpath_names: getting vg info for $vg from $src_host" );
	$self->_cmd("ssh $src_host vgdisplay -v $vg");
    }else{
        $self->log( "get_vg_mpath_names: getting vg info for $vg from localhost" );
	$self->_cmd("vgdisplay -v $vg");
    }
    my @res = split /^/,$self->_get_cmd_result();
    foreach my $line ( @res ){
        if( $line =~ m~PV Name\s+/dev/mapper/([^\s]+)~ ){
            push @mpaths, $1;
        }
    }

    return @mpaths;

    # documentation: Args: vg name
    # documentation: returns list of (short) mpath names for that vg
    # documentation: May use ssh to src_host to get data
}

sub get_vg_mounts {
    my $self = shift;
    my $vg = shift;
    tie my @mounts, 'Array::Unique';

    $self->_cmd("grep /dev/mapper/${vg}- /proc/mounts");
    my @res = split /^/,$self->_get_cmd_result();
    foreach my $line ( @res ){
        if( $line =~ m~/dev/mapper/${vg}-[^\s]+\s+([^\s]+)\s~ ){
            push @mounts, $1;
        }
    }

    return @mounts;

    # documentation: Args: vg name
    # documentation: returns list of current mounts for that vg
}

sub activate_vg {
    my $self = shift;
    my $vg = shift;

    $self->clr_error();

    $self->_cmd("vgchange -a y $vg");
    if( $self->_get_cmd_result() =~ /now active/ ){
	my @lvols = $self->get_vg_lvol_names( $vg );
	foreach my $lvol ( @lvols ){
	    $self->_cmd("fsck -y /dev/$vg/$lvol");
	    unless (  $self->get_cmd_verbose() ){
		$self->log( $self->_get_cmd_result );
	    }
	    #$self->ck_cmd_error('/error/i');
            #if( $self->get_error() ){
            #    return 1;
            #}
	}
    }else{
	$self->_set_error(1);
	$self->_set_error_msg( "activate_vg: vgchange - " . $self->_get_cmd_result() );
    }

    # documentation: Args: vg name
    # documentation: returns list of current mounts for that vg
}

sub ck_vg_active {
    my $self = shift;
    my $vg = shift;
    my $src_host = $self->get_src_hostname();
    my $use_remote = $self->get_use_remote();

    if( $use_remote ){
        $self->log( "ck_vg_active: getting vg info for $vg from $src_host" );
	$self->_cmd("ssh $src_host vgdisplay $vg");
    }else{
        $self->log( "ck_vg_active: getting vg info for $vg from localhost" );
	$self->_cmd("vgdisplay $vg");
    }
    my @res = split /^/,$self->_get_cmd_result();
    foreach my $line ( @res ){
	if( $line =~ /VG Name\s+$vg$/ ){
	    return 1;
	}
    }
    return 0;  # not found

    # documentation: Args: vg name
    # documentation: vg is active if listed in vgdisplay
    # documentation: May use ssh to src_host to get data
}

sub remove_vg {
    my $self = shift;
    my $vg = shift;

    $self->clr_error();

    $self->_cmd("vgchange -a n $vg");
    if( $self->_get_cmd_result() =~ /  0 logical volume/ ){
	$self->_cmd("vgremove -f $vg");
	if( $self->_get_cmd_result() =~ /Volume group \"$vg\" successfully removed/ ){
	    $self->log( "remove_vg: Successfully removed $vg" );
	}else{
	    $self->_set_error(1);
	    $self->_set_error_msg( "remove_vg: vgremove - " . $self->get_cmd_error_msg() );
	}
    }else{
        $self->_set_error(1);
        $self->_set_error_msg( "remove_vg: vgchange - " . $self->get_cmd_error_msg() );
    }

    # documentation: Args: vg name
}

sub remove_mpaths {
    my $self = shift;
    my @mpaths = @_;

    $self->clr_error();

    foreach my $mpath ( @mpaths ){
	$self->_cmd("multipath -f $mpath");
	if( $self->_get_cmd_ret_code() ){
	    $self->log( "remove_mpaths: 1st try: " . $self->_get_cmd_result() );
	    $self->_cmd( "dmsetup remove $mpath" );
	    if( $self->_get_cmd_ret_code() ){
		$self->log("remove_mpaths: ABORT - error removing $mpath");
		$self->_set_error(1);
		$self->_set_error_msg("remove_mpaths: $mpath " .  $self->_get_cmd_result() );
		return;
	    }
	}else{
	    $self->log( "remove_mpaths: removed $mpath" );
	}
    }
    sleep 1;

    # documentation: Args: List of multipath names
}

sub remove_block_devs {
    my $self = shift;
    my @block_devs = @_;

    $self->clr_error();

    foreach my $block_dev ( @block_devs ){
	$self->_cmd( "blockdev --flushbufs /dev/$block_dev" );
        if( $self->_get_cmd_ret_code() ){
            $self->log("remove_block_devs: ABORT - error removing $block_dev");
            $self->_set_error(1);
            $self->_set_error_msg("remove_block_devs: $block_dev " .  $self->_get_cmd_result() );
            return;
        }else{
	    $self->log( "remove_block_devs: removed $block_dev" );
	}
    }
    sleep 1;

    # documentation: Args: List of multipath names
}

sub remove_scsi_devs {
    my $self = shift;
    my @scsi_devs = @_;

    $self->clr_error();

    foreach my $scsi_dev ( @scsi_devs ){
	$self->_cmd("echo 1 > /sys/class/scsi_device/$scsi_dev/device/delete");
	if( $self->_get_cmd_ret_code() ){
	    $self->log("remove_scsi_devs: ABORT - error removing $scsi_dev");
	    $self->_set_error(1);
            $self->_set_error_msg("remove_scsi_devs: $scsi_dev " .  $self->_get_cmd_result() );
	    return;
        }else{
	    $self->log( "remove_scsi_devs: removed $scsi_dev" );
	}
    }
    sleep 1;

    # documentation: Args: List of multipath names
}

sub unmount {
    my $self   = shift;
    my @mounts   = @_;

    $self->clr_error();

    foreach my $mount (@mounts) {
	my $attempt = "umount $mount || ( fuser -km $mount && umount $mount )";
	$self->_cmd( $attempt ); 
	my $attempt_res = $self->_get_cmd_result();
	my $attempt_ret = $self->_get_cmd_ret_code();
	sleep 3;
	$self->_cmd( "grep -c \"$mount \" /proc/mounts" );
	if( $self->_get_cmd_result() > 0 ){
	    $self->log("ERROR: could not successfully unmount $mount");
	    unless (  $self->get_cmd_verbose() ){
		$self->log("CMD: $attempt" );
		$self->log("RES: $attempt_res");
		$self->log("RET: $attempt_ret");
		$self->log("CMD:grep -c $mount /proc/mounts");
		$self->log("RES: ",$self->_get_cmd_result() );
		$self->log("RET: ",$self->_get_cmd_ret_code() );
	    }
	    $self->_set_error(1);
	    $self->_set_error_msg("ERROR: could not successfully unmount $mount");
	    return 1;
	}else{
	    $self->log("unmount: Successful - $mount");
	}
    }

    # documentation: Args: list of mount points
    # documentation: performs unmount on each mount. Returns error if unmount fails
}

sub ck_mounts {
    my $self   = shift;
    my @mounts   = @_;

    $self->clr_error();

    foreach my $mount (@mounts) {
	$self->_cmd( "grep -c $mount /proc/mounts" );
	unless( $self->_get_cmd_result() > 0 ){
	    $self->log("ck_mounts: $mount is not mounted");
	    $self->_set_error(1);
	    $self->_set_error_msg("$mount is not mounted");
	    return 1;
	}
    }

    # documentation: Args: list of mount points
    # documentation: performs unmount on each mount. Returns error if unmount fails
}

sub set_lvm_lock {
    my $self = shift;
    my $time = time;
    my $timeout = 0.00694;  # currently set to 10 min
    my $lock_file="/etc/lvm/StorageLX-$time-LVM.lock";
    my $locks = 0;
    my $i;
    my $LVM;
    my $file;

    ## try repeated attempts to lock until success or failure
    for ($i=1;$i<=20;$i++){
	$locks = 0;
	$self->_cmd( "touch $lock_file" );
	sleep 1;
	opendir( $LVM, "/etc/lvm" );
	while( $file=readdir($LVM) ){
	    if( $file=~/-LVM.lock$/ ){
		my $age = -M "/etc/lvm/$file";
		if( $age > $timeout ){
		    print "Remove previous lock: $file\n";
		    $self->_cmd( "rm /etc/lvm/$file" );
		}else{
		    $locks++;
		}
            }
	}
	closedir $LVM;
	if( $locks eq 1 ){
	    $self->_set_lvm_conf_locked(1); 		# Lock is set
	    return $lock_file;
	}elsif( $locks gt 1 ){
            print "Waiting on lock\n";
            $self->_cmd( "rm $lock_file" );		# Wait - Try again
            sleep int(rand(60));
	}else{
	    $self->log("set_lvm_lock: FAILED to set lock");
            $self->_set_lvm_conf_locked(0); 		# Lock is NOT set
	    $self->_cmd( "rm $lock_file" );
	    return 0;
	}
    }

    # documentation: Obtains lock for other commands that modify lvm.conf
}

sub clear_lvm_lock {
    my $self = shift;
    my $lock_file = shift;

    $self->_cmd( "rm $lock_file" );
    $self->_set_lvm_conf_locked(0);
}

sub add_mpaths_to_lvm {
    my $self = shift;
    my @new_mpaths = @_;
    my $lvm_conf="/etc/lvm/lvm.conf";
    my $lvm_conf_new="/etc/lvm/lvm.conf-locked";
    my $lvm_conf_bak="/etc/lvm/lvm.conf-".time;  # Create backup
    my $old;
    my $new;

    unless( @new_mpaths ){
	$self->_set_error( 1 );
	$self->_set_error_msg( "List of mpaths is blank");
	return;
    }

    my $lock_file = $self->set_lvm_lock();
    if( ! $self->get_lvm_conf_locked() ){
	$self->_set_error( 1 );
	$self->_set_error_msg( $self->_get_cmd_result );
	return;
    }

    $self->_cmd( "/bin/cp -p $lvm_conf $lvm_conf_bak" );
    if( $self->_get_cmd_ret_code() ){
	$self->_set_error( 1 );
	$self->_set_error_msg( $self->_get_cmd_result );
	return;
    }

    open( my $ORIG, $lvm_conf );
    open( my $NEW, ">$lvm_conf_new" );
    tie my @newfilters, 'Array::Unique';
    while( my $line=<$ORIG>){
	if ( $line =~ /^\s*filter\s*=\s*\[([^\]]+)/){
	    $old = $line;
	    my @filters=split ",",$1;
	    foreach my $filter (@filters){
		unless($filter=~/\"r/){
		    $filter =~ s/\s*//g;
		    push @newfilters,$filter;
	    	}
	    }
	    foreach my $mpath (@new_mpaths){
		push @newfilters,"\"a|/dev/mapper/$mpath|\"";;
	    }
	    $new = join ", " , @newfilters;
	    print $NEW "filter = [ $new, \"r|.*|\" ]\n";
	}else{
	    print $NEW $line;
	}
    }
    close $NEW;
    close $ORIG;

    $self->_cmd( "diff $lvm_conf $lvm_conf_new" );
    if( $self->_get_cmd_result() ){
        $self->log("add_mpaths_to_lvm: OLD:\n$old");
        $self->log("add_mpaths_to_lvm: NEW:\nfilter = [ $new, \"r|.*|\" ]\n");
        $self->_cmd( "diff $lvm_conf $lvm_conf_new|grep -c -v filter" );
        my $result = int ( $self->_get_cmd_result() );
        if ( $result == 2){
            $self->log("add_mpaths_to_lvm: Adding mpaths to lvm.conf");
            $self->_cmd( "/bin/mv $lvm_conf_new $lvm_conf" );
        }else{
            $self->log("add_mpaths_to_lvm: FAILED to add devices to $lvm_conf_new");
            $self->_set_error(1);
            $self->_set_error_msg("add_mpaths_to_lvm: FAILED to add devices");
        }
    }else{
        $self->log("add_mpaths_to_lvm: No change to lvm.conf");
	$self->_cmd("rm -f $lvm_conf_bak $lvm_conf_new");
    }

    $self->clear_lvm_lock( $lock_file );

    # documentation: Adds mpaths to lvm.conf filters, thus making them active
}

sub restrict_lvm_to_active_vgs {
    my $self = shift;
    my $lvm_conf="/etc/lvm/lvm.conf";
    my $lvm_conf_new="/etc/lvm/lvm.conf-locked";
    my $lvm_conf_bak="/etc/lvm/lvm.conf-".time;  # Create backup
    my @new_mpaths;
    my $old;
    my $new;

    my $lock_file = $self->set_lvm_lock();
    if( ! $self->get_lvm_conf_locked() ){
	$self->_set_error( 1 );
	$self->_set_error_msg( $self->_get_cmd_result );
	return;
    }

    $self->_cmd( "/bin/cp -p $lvm_conf $lvm_conf_bak" );
    if( $self->_get_cmd_ret_code() ){
	$self->_set_error( 1 );
	$self->_set_error_msg( $self->_get_cmd_result );
	return;
    }

    $self->_cmd( "vgdisplay -v" );
    my @res = split /^/,$self->_get_cmd_result();
    foreach my $line ( @res ){
	if( $line =~ /has been left open/ ){
	   $self->_set_error( 1 );
	    $self->_set_error_msg( $self->_get_cmd_result );
	    return;
	} 
	if( $line =~ m~^\s*PV Name\s+/dev/mapper/([^\s]+)~ ){
            push @new_mpaths, $1;
        }
    }

    open( my $ORIG, $lvm_conf );
    open( my $NEW, ">$lvm_conf_new" );
    tie my @newfilters, 'Array::Unique';
    while( my $line=<$ORIG>){
	if ( $line =~ /^\s*filter\s*=\s*\[\s*([^\]]+)\s*/){
	    $old = $line;
	    my @filters=split ",",$1;
	    foreach my $filter (@filters){
		if($filter=~ m~/dev/sda\$|/dev/sda\d\$~ ){
		    $filter =~ s/\s*//g;
		    push @newfilters,$filter;
	    	}
	    }
	    push @newfilters,('"a|/dev/sda$|"', '"a|/dev/sda1$|"', '"a|/dev/sda2$|"', '"a|/dev/sda3$|"');
	    foreach my $mpath (@new_mpaths){
		push @newfilters,"\"a|/dev/mapper/$mpath|\"";;
	    }
	    $new = join ", " , @newfilters;
	    print $NEW "filter = [ $new, \"r|.*|\" ]\n";
	}else{
	    print $NEW $line;
	}
    }
    close $NEW;
    close $ORIG;

    # check to ensure that the new conf is valid
    $self->_cmd( "diff $lvm_conf $lvm_conf_new" );
    if( $self->_get_cmd_result() ){
	$self->log("restrict_lvm_to_active_vgs: OLD:\n$old");
	$self->log("restrict_lvm_to_active_vgs: NEW:\nfilter = [ $new, \"r|.*|\" ]\n");
	$self->_cmd( "diff $lvm_conf $lvm_conf_new|grep -c -v filter" );
	my $result = int ( $self->_get_cmd_result() );
	if ( $result == 2){
	    $self->log("restrict_lvm_to_active_vgs: Applying new filter to lvm.conf");
	    $self->_cmd( "/bin/mv $lvm_conf_new $lvm_conf" );
	}else{
	    $self->log("restrict_lvm_to_active_vgs: FAILED to add devices to $lvm_conf_new");
	    $self->_set_error(1);
	    $self->_set_error_msg("restrict_lvm_to_active_vgs: FAILED");
	}
    }else{
	$self->log("restrict_lvm_to_active_vgs: No change to lvm.conf");
	$self->_cmd("rm -f $lvm_conf_bak $lvm_conf_new");
    }

    $self->clear_lvm_lock( $lock_file );

    # documentation: Adds mpaths to lvm.conf filters, thus making them active
}

sub create_local_lvm {
    my $self = shift;
    my @new_mpaths = @_;
    my $lvm_conf="/etc/lvm/lvm.conf";
    my $lvm_conf_new="lvm.conf";  ## THIS IS LOCAL
    my $mpath;

    if( $ENV{'PWD'} =~ m~/etc/lvm~ ){
	$self->log( "create_local_lvm: FAILED since local directory is /etc/lvm");
        $self->_set_error(1);
        $self->_set_error_msg("FAILED since local directory is /etc/lvm");
    }

    ## No need for lock or backup with local lvm.conf

    open( my $ORIG, $lvm_conf );
    open( my $NEW, ">$lvm_conf_new" );
    tie my @newfilters, 'Array::Unique';
    while( my $line=<$ORIG>){
	if ( $line =~ /^\s*filter\s*=\s*\[([^\]]+)/){
	    my @filters=split ",",$1;
	    foreach my $filter (@filters){
		unless($filter=~/mapper|\"r/){
		    $filter =~ s/\s*//g;
		    push @newfilters,$filter;		# Strip out mapper devs
		}
	    }
	    foreach $mpath (@new_mpaths){
		push @newfilters,"\"a|/dev/mapper/$mpath|\"";;
	    }
	    my $new = join ", " , @newfilters;
	    $self->log("create_local_lvm: NEW: $new, \"r|.*|\" ]");
	    print $NEW "filter = [ $new, \"r|.*|\" ]\n";
	}else{
	    print $NEW $line;
	}
    }
    close $NEW;
    close $ORIG;

    # check to ensure that the new conf is valid
    $self->_cmd( "diff $lvm_conf $lvm_conf_new|grep -c -v filter" );
    my $result = int ( $self->_get_cmd_result() );
    if ( $result == 2){
	$self->log("create_local_lvm: Added mpaths to lvm.conf");
    }else{
	$self->log("create_local_lvm: FAILED to add devices to $lvm_conf_new");
	$self->_set_error(1);
	$self->_set_error_msg("create_local_lvm: FAILED to add devices to $lvm_conf_new");
    }

    # documentation: Adds mpaths to lvm.conf filters, thus making them active
}

sub adjust_lvm {
    my $self = shift;
    my $src_vg = shift;
    my $dest_vg = shift;
    my @mpaths   = @_;
    my $lvm_dir_orig;
    if( defined $ENV{'LVM_SYSTEM_DIR'} ){
	$lvm_dir_orig = $ENV{'LVM_SYSTEM_DIR'};
    }
    my $mp;

    $self->clr_error();

    ## Create local lvm.conf and set environment to use that
    $self->create_local_lvm(@mpaths);
    if( $self->get_error() ){
	$self->log("ABORT adjust_lvm since create_local_lvm returned error");
	return;
    }
    my $pwd = `pwd`;
    chomp $pwd;
    $ENV{'LVM_SYSTEM_DIR'} = $pwd;

    foreach my $mp ( @mpaths ){
	my $mp_path = "/dev/mapper/$mp";
	if( -l $mp_path ){
	## Here's the command 
	    $self->_cmd("pvchange --uuid /dev/mapper/$mp --config 'global{activation=0}'");
	    $self->ck_cmd_error('/^\s*ERROR:/');
	    if( $self->get_error() ){
		return;
	    }
	}else{
            $self->_set_error(1);
            $self->_set_error_msg("adjust_lvm: Missing $mp_path");
            return;
	}
    }
    $self->_cmd("vgchange --uuid $src_vg --config 'global{activation=0}'");
    $self->ck_cmd_error('/error/i');
    if( $self->get_error() ){
	return;
    }

    $self->_cmd("vgrename $src_vg $dest_vg --config 'global{activation=0}'");
    $self->ck_cmd_error('/error/i');
    if( $self->get_error() ){
	return;
    }

    ## Restore lvm to normal
    if( $lvm_dir_orig ){
	$ENV{'LVM_SYSTEM_DIR'} = $lvm_dir_orig;
    }else{
	undef $ENV{'LVM_SYSTEM_DIR'};
    }

    ## Now that new snap devices are fixed up, they can be added to global LVM
    $self->add_mpaths_to_lvm(@mpaths);

    # documentation: Args: Array of mpaths
    # documentation: Adjusts devices to avoid conflict with source vg devices
}

no Moose;

__PACKAGE__->meta->make_immutable;

package EVA;
use Moose;
extends 'THING';

has 'cv_server' => (
    is     => 'ro',
    isa    => 'Str',
    reader => 'get_cv_server',
    documentation => q{The Command View server name for the EVA},
);

has 'cv_user' => (
    is     => 'ro',
    isa    => 'Str',
    reader => 'get_cv_user',
    default   => 'sssuAdmin',
    documentation => q{User name to connect to cv_server},
);

has 'eva_array' => (
    is     => 'rw',
    isa    => 'Str',
    reader => 'get_eva_array',
    writer => 'set_eva_array',
    documentation => q{EVA Array name used by Command View},
);

has 'snap_starting_lun' => (
    is     => 'rw',
    isa    => 'Int',
    default   => 0,
    reader => 'get_snap_starting_lun',
    writer => 'set_snap_starting_lun',
    documentation => q{The starting LUN ID used for snapshots},
);

has 'snap_prefix' => (
    is     => 'rw',
    isa    => 'Str',
    default   => 'snap_',
    reader => 'get_snap_prefix',
    writer => 'set_snap_prefix',
    documentation => q{The prefix used to build each vdisk snap},
);

has 'sssu_bin' => (
    is     => 'ro',
    isa    => 'Str',
    reader => 'get_sssu_bin',
    default   => '/usr/local/bin/sssu',
    documentation => q{The path to sssu utility},
);

has 'sssu_dir' => (
    is     => 'ro',
    isa    => 'Str',
    reader => 'get_sssu_dir',
    default   => 'SSSU',
    documentation => q{The path to SSSU scripts directory (relative by default)},
);

sub BUILD {
    my $self = shift;
# Sanity Checks
    my $cv_server = $self->get_cv_server();
    my $eva_array = $self->get_eva_array();
    my $sssu_bin = $self->get_sssu_bin();
    my $SSSU_dir = $self->get_sssu_dir();
    my $pw_file = "$ENV{'HOME'}/sssu.pw";
    my $usage = 'e.g. $eva = EVA->new( cv_server =>"slstm1", eva_array=>"sleva8400" );';
    die "EVA object requires cv_server\n$usage\n" unless defined $cv_server;
    die "EVA object requires eva_array\n$usage\n" unless defined $eva_array;
    die "EVA object requires $sssu_bin\n$usage\n" unless -f $sssu_bin;
    die "EVA requires local or specified SSSU_dir\n" unless -d $SSSU_dir;
    die "SSSU requires password file of $pw_file\n" unless -f $pw_file;
}

has 'wwid_full_vdisk_map' => (
    is     => 'rw',
    isa    => 'HashRef[Str]',
    reader => 'get_wwid_full_vdisk_map',
    writer => '_set_wwid_full_vdisk_map',
    documentation => q{HASH->STRING: vdisk based on WWID},
    documentation => q{WWID is key},
    documentation => q{Used to support process of mapping mpath to storage devices},
);

has 'snap_vdisk_wwid_map' => (
    is     => 'rw',
    isa    => 'HashRef[Str]',
    reader => 'get_snap_vdisk_wwid_map',
    writer => '_set_snap_vdisk_wwid_map',
    documentation => q{HASH->STRING: vdisk based on vdisk},
    documentation => q{WWID is key},
    documentation => q{Used to support process of mapping vdisk to storage devices},
);

has 'snap_wwid_lun_map' => (
    is     => 'rw',
    isa    => 'HashRef[Int]',
    reader => 'get_snap_wwid_lun_map',
    writer => '_set_snap_wwid_lun_map',
    documentation => q{HASH->INT: LUN ID based on vdisk},
    documentation => q{WWID is key},
    documentation => q{Used to support process of mapping vdisk to storage devices},
);

has 'snap_wwid_vdisk_map' => (
    is     => 'rw',
    isa    => 'HashRef[Str]',
    reader => 'get_snap_wwid_vdisk_map',
    writer => '_set_snap_wwid_vdisk_map',
    documentation => q{HASH->INT: LUN ID based on vdisk},
    documentation => q{WWID is key},
    documentation => q{Used to support process of mapping vdisk to storage devices},
);

has 'sssu_locked' => (
    is     => 'rw',
    isa    => 'Int',
    default   => 0,
    reader => '_get_sssu_locked',
    writer => '_set_sssu_locked',
    documentation => q{Used to serialize sssu commands},
);

sub set_sssu_lock {
    my $self = shift;
    my $time = time;
    my $timeout = 0.00694;  # currently set to 10 min
    my $SSSU_dir = $self->get_sssu_dir();
    my $lock_file="$SSSU_dir/StorageLX-$time-SSSU.lock";
    my $locks = 0;
    my $SSSU;
    my $i;
    my $file;

    ## try repeated attempts to lock until success or failure
    for ($i=1;$i<=20;$i++){
	$locks = 0;
        $self->_cmd( "touch $lock_file" );
        sleep 1;
        opendir( $SSSU, $SSSU_dir );
        while( $file=readdir($SSSU) ){
            if( $file=~/-SSSU.lock$/ ){
                my $age = -M "$SSSU_dir/$file";
                if( $age > $timeout ){
                    $self->log( "set_sssu_lock: Remove previous lock: $file" );
                    $self->_cmd( "rm $SSSU_dir/$file" );
                }else{
                    $locks++;
                }
            }
        }
        closedir $SSSU;

        if( $locks eq 1 ){
            $self->_set_sssu_locked(1);             # Lock is set
            return $lock_file;
        }elsif( $locks gt 1 ){
            $self->log(  "set_sssu_lock: Waiting on lock" );
            $self->_cmd( "rm $lock_file" );             # Wait - Try again
            sleep int(rand(30));
        }else{
            $self->log("set_sssu_lock: FAILED to set lock");
            $self->_set_sssu_locked(0);             # Lock is NOT set
            $self->_cmd( "rm $lock_file" );
            return 0;
        }
    }

    # documentation: Obtains lock for sssu commands
}

sub clear_sssu_lock {
    my $self = shift;
    my $lock_file = shift;

    $self->_cmd( "rm $lock_file" );
    $self->_set_sssu_locked(0);
}

sub load_wwid_full_vdisk_map {
    my $self = shift;
    my $sssu = $self->get_sssu_bin();
    my $SSSU_dir = $self->get_sssu_dir();
    my $cv_server = $self->get_cv_server();
    my $cv_user = $self->get_cv_user();
    my $eva_array = $self->get_eva_array();
    my %vdisk;
    my $wwid;
    my $vd;

    my $lock_file = $self->set_sssu_lock();
    if( ! $self->_get_sssu_locked() ){
        $self->_set_error( 1 );
        $self->_set_error_msg( $self->_get_cmd_result );
        return;
    }

    my $script="$SSSU_dir/show_all_vdisk_full.$eva_array";
    $self->log("load_wwid_full_vdisk_map: Creating $script");
    open my $SSSU_SCRIPT,">$script";
    print $SSSU_SCRIPT qq~SET OPTION COMMAND_DELAY=1
SET OPTION RETRIES=1
SELECT MANAGER $cv_server USERNAME=$cv_user
SELECT SYSTEM \"$eva_array\"
ls vdisk full
~;
    close $SSSU_SCRIPT;
    $self->log("load_wwid_full_vdisk_map: probing EVA");
    $self->_cmd("$sssu \"file $script\"");
    my @res = split /^/,$self->_get_cmd_result();
    foreach my $line ( @res ){
	if($line =~ /^\s+objectname [.]+: \\Virtual Disks.+\\([^\\]+)\\ACTIVE/){
	    $vd = $1;
	    $self->log("load_wwid_full_vdisk_map: $vd");
	}elsif($line =~ /^\s+wwlunid [.]+: ([\w-]+)/){
	    my $eva_wwid = $1;
	    my @wwid = split "-",$eva_wwid;
	    my $wwid = lc (join "",@wwid);
	    $wwid = "3" . $wwid;
	    $vdisk{$wwid} = $vd;
	}
    }
    $self->_set_wwid_full_vdisk_map( \%vdisk );

    $self->clear_sssu_lock( $lock_file );

    # documentation: Loads wwid_vdisk_full_map
    # documentation: NOTE: multipath adds "3" to front of WWID, so I adjust to match
}

sub load_snap_vdisk_maps {
    my $self = shift;
    my $sssu = $self->get_sssu_bin();
    my $SSSU_dir = $self->get_sssu_dir();
    my $cv_server = $self->get_cv_server();
    my $cv_user = $self->get_cv_user();
    my $eva_array = $self->get_eva_array();
    my %wwid;
    my %lun;
    my %vdisk;
    my $snap_vdisk;
    my $mp_wwid;

    my $lock_file = $self->set_sssu_lock();
    if( ! $self->_get_sssu_locked() ){
        $self->_set_error( 1 );
        $self->_set_error_msg( $self->_get_cmd_result );
        return;
    }

    my $script="$SSSU_dir/snap_show_all.$eva_array";
    $self->log("load_snap_vdisk_maps: Creating $script");
    open my $SSSU_SCRIPT,">$script";
    print $SSSU_SCRIPT qq~SET OPTION COMMAND_DELAY=1
SET OPTION RETRIES=1
SELECT MANAGER $cv_server USERNAME=$cv_user
SELECT SYSTEM \"$eva_array\"
ls snap full
~;
    close $SSSU_SCRIPT;
    $self->log("load_snap_vdisk_maps: probing EVA");
    $self->_cmd("$sssu \"file $script\"");
    my @res = split /^/,$self->_get_cmd_result();
    foreach my $line ( @res ){
	if($line =~ /^\s+objectname [.]+: \\Virtual Disks.+\\([^\\]+)\s/){
	    $snap_vdisk = $1;
            $self->log("load_snap_vdisk_maps: $snap_vdisk");
	}elsif($line =~ /^\s+wwlunid [.]+: ([\w-]+)/){
	    my $eva_wwid = $1;
	    my @eva_wwid = split "-",$eva_wwid;
	    $mp_wwid = "3" . lc (join "",@eva_wwid);
	    $wwid{$snap_vdisk} = $mp_wwid;
	    $vdisk{$mp_wwid} = $snap_vdisk;
	}elsif($line =~ /^\s+lunnumber [.]+: (\d+)/){
	    $lun{$mp_wwid} = int ( $1 );
	}
    }
    $self->_set_snap_vdisk_wwid_map( \%wwid );
    $self->_set_snap_wwid_vdisk_map( \%vdisk );
    $self->_set_snap_wwid_lun_map( \%lun );

    $self->clear_sssu_lock( $lock_file );

    # documentation: Loads wwid_vdisk_snap_map
    # documentation: NOTE: multipath adds "3" to front of WWID, so I adjust to match
}

sub create_snap {
    my $self = shift;
    my $source_vg = shift;
    my @vdisks = @_;
    my @dest_vdisks = ();
    my $hostname = $self->get_hostname();
    my $sssu = $self->get_sssu_bin();
    my $SSSU_dir = $self->get_sssu_dir();
    my $lun = $self->get_snap_starting_lun();  # default is 0
    my $snap_prefix = $self->get_snap_prefix();  # default is "snap_"
    my $cv_server = $self->get_cv_server();
    my $cv_user = $self->get_cv_user();
    my $eva_array = $self->get_eva_array();

    $self->clr_error();
    my $lock_file = $self->set_sssu_lock();
    if( ! $self->_get_sssu_locked() ){
        $self->_set_error( 1 );
        $self->_set_error_msg( $self->_get_cmd_result );
        return;
    }

    my $script="$SSSU_dir/$snap_prefix${source_vg}_create.$hostname";
    $self->log("create_snap: Creating $script");
    open my $SSSU_SCRIPT,">$script";
    print $SSSU_SCRIPT qq~SET OPTION COMMAND_DELAY=1
SET OPTION RETRIES=1
SELECT MANAGER $cv_server USERNAME=$cv_user
SELECT SYSTEM \"$eva_array\"
~;
    foreach my $vdisk (@vdisks){
	$self->log("create_snap: add $snap_prefix$vdisk");
	push @dest_vdisks,"$snap_prefix$vdisk";
	print $SSSU_SCRIPT "add snapshot $snap_prefix$vdisk allocation=demand vdisk=$vdisk\n";
	print $SSSU_SCRIPT "add lun $lun host=$hostname vdisk=$snap_prefix$vdisk\n";
	if ( $lun > 0 ){
	    $lun++;
	}
    }
    close $SSSU_SCRIPT;
    $self->_cmd("$sssu \"file $script\"");
    $self->ck_cmd_error('/Error:/');

    $self->clear_sssu_lock( $lock_file );

    return @dest_vdisks;

    # documentation: Creates script to perform snapshot and runs it
    # documentation: NOTE: if get_snap_starting_lun returns null, then EVA picks LUN
}

sub delete_snap {
    my $self = shift;
    my $vg = shift;
    my @luns = @{ $_[0] };
    my @vdisks = @{ $_[1] };
    my $hostname = $self->get_hostname();
    my $host_path = $self->get_host_path( $hostname );
    my $sssu = $self->get_sssu_bin();
    my $SSSU_dir = $self->get_sssu_dir();
    my $cv_server = $self->get_cv_server();
    my $cv_user = $self->get_cv_user();
    my $eva_array = $self->get_eva_array();

    $self->clr_error();
    my $lock_file = $self->set_sssu_lock();
    if( ! $self->_get_sssu_locked() ){
        $self->_set_error( 1 );
        $self->_set_error_msg( $self->_get_cmd_result );
        return;
    }

    my $script="$SSSU_dir/${vg}_delete.$hostname";
    $self->log("delete_snap: Creating $script");
    open my $SSSU_SCRIPT,">$script";
    print $SSSU_SCRIPT qq~SET OPTION COMMAND_DELAY=1
SET OPTION RETRIES=1
SELECT MANAGER $cv_server USERNAME=$cv_user
SELECT SYSTEM \"$eva_array\"
~;
    foreach my $lun (@luns){
	$self->log("delete_snap: del lun $lun");
	print $SSSU_SCRIPT "del lun $host_path\\$lun\n";
    }
    foreach my $vdisk (@vdisks){
	$self->log("delete_snap: del $vdisk");
	print $SSSU_SCRIPT "del vdisk $vdisk\n";
    }
    close $SSSU_SCRIPT;
    $self->_cmd("$sssu \"file $script\"");
    $self->ck_cmd_error('/Error:/');

    $self->clear_sssu_lock( $lock_file );

    # documentation: Creates script to perform snapshot and runs it
    # documentation: NOTE: if get_snap_starting_lun returns null, then EVA picks LUN
}

sub get_host_path {
    my $self = shift;
    my $host = shift;
    my $sssu = $self->get_sssu_bin();
    my $SSSU_dir = $self->get_sssu_dir();
    my $cv_server = $self->get_cv_server();
    my $cv_user = $self->get_cv_user();
    my $eva_array = $self->get_eva_array();
    my $host_path;

    $self->clr_error();
    my $lock_file = $self->set_sssu_lock();
    if( ! $self->_get_sssu_locked() ){
        $self->_set_error( 1 );
        $self->_set_error_msg( $self->_get_cmd_result );
        return;
    }

    my $script="$SSSU_dir/ls_host.$eva_array";
    $self->log("get_host_path: Creating $script");
    open my $SSSU_SCRIPT,">$script";
    print $SSSU_SCRIPT qq~SET OPTION COMMAND_DELAY=1
SET OPTION RETRIES=1
SELECT MANAGER $cv_server USERNAME=$cv_user
SELECT SYSTEM \"$eva_array\"
ls host $host
~;
    close $SSSU_SCRIPT;
    $self->_cmd("$sssu \"file $script\"");
    my @res = split /^/,$self->_get_cmd_result();
    foreach my $line ( @res ){
        if($line =~ /^\s+objectname [.]+: ([^\s]+)/){
            $host_path = $1;
            $self->log("get_host_path: $host_path");
        }
    }

    $self->clear_sssu_lock( $lock_file );

    return $host_path;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
