package LVM;
use Moose;
use Array::Unique;

has 'src_vgs' => (
    is            => 'rw',
    reader        => 'get_src_vgs',
    writer        => '_set_src_vgs',
    documentation => q{Source Volumegroups pulled from /proc/mounts},
);

has 'pkg_vgs' => (
    is            => 'rw',
    reader        => 'get_pkg_vgs',
    writer        => '_set_pkg_vgs',
    documentation => q{Package Volumegroups pulled from /proc/mounts},
);

has 'src_fstab_vgs' => (
    is            => 'rw',
    reader        => 'get_src_fstab_vgs',
    writer        => '_set_src_fstab_vgs',
    documentation => q{Source Volumegroups pulled from /etc/fstab},
);

has 'pkg_fstab_vgs' => (
    is            => 'rw',
    reader        => 'get_pkg_fstab_vgs',
    writer        => '_set_pkg_fstab_vgs',
    documentation => q{Package Volumegroups pulled from /etc/fstab},
);

has 'src_mount_points' => (
    is            => 'rw',
    reader        => 'get_src_mountpoints',
    writer        => '_set_src_mountpoints',
    documentation => q{Source Mount Points pulled from /proc/mounts},
);

has 'pkg_mount_points' => (
    is            => 'rw',
    reader        => 'get_pkg_mountpoints',
    writer        => '_set_pkg_mountpoints',
    documentation => q{Package Mount Points pulled from /proc/mounts},
);

has 'pkg_fstab_mount_points' => (
    is            => 'rw',
    reader        => 'get_pkg_fstab_mountpoints',
    writer        => '_set_pkg_fstab_mountpoints',
    documentation => q{Package Mount Points pulled from /etc/fstab},
);

has 'src_fstab_mount_points' => (
    is            => 'rw',
    reader        => 'get_src_fstab_mountpoints',
    writer        => '_set_src_fstab_mountpoints',
    documentation => q{Source Mount Points pulled from /etc/fstab},
);

has 'pkg_fstab_lvols' => (
    is            => 'rw',
    reader        => 'get_pkg_fstab_lvols',
    writer        => '_set_pkg_fstab_lvols',
    documentation => q{Package Logical Volumes pulled from /etc/fstab},
);

has 'src' => (
    is            => 'rw',
    reader        => 'get_src',
    writer        => 'set_src',
    documentation => q{Source Name},
);

has 'pkg' => (
    is            => 'rw',
    reader        => 'get_pkg',
    writer        => 'set_pkg',
    documentation => q{Package Name},
);

sub get_all_proc_mounts {
    my $self = shift;
    my $mount;
    my $vg;
    tie my @src_vgs, 'Array::Unique';
    tie my @pkg_vgs, 'Array::Unique';
    my @pkg_mounts;
    my @src_mounts;
    my $pkg = $self->get_pkg();
    my $src = $self->get_src();
    open( MOUNTS, "/proc/mounts" );

    while (<MOUNTS>) {
        if (/^\/dev.*(vg\d+)-lvol.*\s+(\/pkg\/$pkg\/\w+)\s+/) {
            $vg    = $1;
            $mount = $2;
            push( @pkg_mounts, $mount );
            push( @pkg_vgs,    $vg );
        }
    }
    close(MOUNTS);
    open( MOUNTS, "/proc/mounts" );
    while (<MOUNTS>) {
        if (/^\/dev.*(vg\d+)-lvol.*\s+(\/pkg\/$src\/\w+)\s+/) {
            $vg    = $1;
            $mount = $2;
            push( @src_mounts, $mount );
            push( @src_vgs,    $vg );
        }
    }
    $self->_set_src_mountpoints( \@src_mounts );
    $self->_set_pkg_mountpoints( \@pkg_mounts );
    $self->_set_src_vgs( \@src_vgs );
    $self->_set_pkg_vgs( \@pkg_vgs );
}

#sub unmount_src {
#    my $self   = shift;
#    my @mounts = @{ $self->get_src_mountpoints() };
#    foreach my $mount (@mounts) {
#        print("fuser -km $mount\n");
#        print("umount $mount\n");
#    }
#}
#
#sub unmount_pkg {
#    my $self   = shift;
#    my @mounts = @{ $self->get_pkg_mountpoints() };
#    foreach my $mount (@mounts) {
#        print("fuser -km $mount\n");
#        print("umount $mount\n");
#    }
#}
#
#sub remove_src_vgs {
#    my $self = shift;
#    my @vgs  = @{ $self->get_src_vgs() };
#    foreach my $vg (@vgs) {
#        print("vgchange -a n $vg\n");
#        print("vgremove -ff $vg\n");
#    }
#}
#
#sub remove_pkg_vgs {
#    my $self = shift;
#    my @vgs  = @{ $self->get_pkg_vgs() };
#    foreach my $vg (@vgs) {
#        print("vgchange -a n $vg\n");
#        print("vgremove -ff $vg\n");
#    }
#}

sub parse_fstab {
    my $self = shift;
    my @src_mounts;
    my @pkg_mounts;
    my @pkg_lvols;
    tie my @src_vgs, 'Array::Unique';
    tie my @pkg_vgs, 'Array::Unique';
    my $src = $self->get_src();
    my $pkg = $self->get_pkg();
    open( FSTAB, "/etc/fstab" );

    while (<FSTAB>) {
        if (/^\/.*(vg\d+)\/.*(\/pkg\/$src\/\w+)\s+/) {
            my $src_mount = $2;
            my $src_vg    = $1;
            push( @src_mounts, $src_mount );
            push( @src_vgs,    $src_vg );
        }
        if (/^(\/.*(vg\d+).*)\s+(\/pkg\/$pkg\/\w+)\s+/) {
            my $pkg_mount = $3;
            my $pkg_vg    = $2;
            my $pkg_lvol  = $1;
            push( @pkg_mounts, $pkg_mount );
            push( @pkg_vgs,    $pkg_vg );
            push( @pkg_lvols,  $pkg_lvol );
        }
    }
    $self->_set_src_fstab_mountpoints( \@src_mounts );
    $self->_set_src_fstab_vgs( \@src_vgs );
    $self->_set_pkg_fstab_mountpoints( \@pkg_mounts );
    $self->_set_pkg_fstab_vgs( \@pkg_vgs );
    $self->_set_pkg_fstab_lvols( \@pkg_lvols );
}

no Moose;

__PACKAGE__->meta->make_immutable;

package XP;
use Moose;
use Array::Unique;
no strict;

has 'horcm' => (
    is      => 'rw',
    reader  => 'get_horcm',
    writer  => 'set_horcm',
    default => '/etc/horcm1.conf',
    documentation =>
      q{Horcm File should not change unless you know what you are doing},
);

has 'src' => (
    is            => 'rw',
    reader        => 'get_src',
    writer        => 'set_src',
    documentation => q{Source Name},
);

has 'pkg' => (
    is            => 'rw',
    reader        => 'get_pkg',
    writer        => 'set_pkg',
    documentation => q{Package Name},
);

has 'pkg_disks' => (
    is            => 'rw',
    reader        => 'get_pkg_disks',
    writer        => '_set_pkg_disks',
    documentation => q{Package Disk Names},
);

has 'horcm_pairs' => (
    is            => 'rw',
    reader        => 'get_horcm_pairs',
    writer        => '_set_horcm_pairs',
    documentation => q{Horcm Pairs to Split and Sync},
);

has 'horcm_vgs' => (
    is            => 'rw',
    reader        => 'get_horcm_vgs',
    writer        => '_set_horcm_vgs',
    documentation => q{Package Volume Groups pulled from Horcm File},
);

has 'src_vgs' => (
    is     => 'rw',
    reader => 'get_src_vgs',
    writer => '_set_src_vgs',
);

has 'pkg_vgs' => (
    is     => 'rw',
    reader => 'get_pkg_vgs',
    writer => '_set_pkg_vgs',
);

has 'basevgname_hash' => (
    is            => 'rw',
    reader        => 'get_basevgname_hash',
    writer        => '_set_basevgname_hash',
    documentation => q{Hash with Disk Name},
);

has 'vgimportclone_cmds' => (
    is     => 'rw',
    reader => 'get_vgimportclone_cmds',
    writer => '_set_vgimportclone_cmds',
    documentation =>
      q{VG Import Commands. No other way to do this at the moment},
);

sub parse_horcm {
    my $self = shift;
    tie my @horcm_pairs, 'Array::Unique';
    tie my @pkgvgs,      'Array::Unique';
    tie my @srcvgs,      'Array::Unique';
    my $horcm_file = $self->get_horcm;
    my $src        = $self->get_src();
    my $pkg        = $self->get_pkg();
    my @pkg_disks;
    my @vgimportclone_cmds;
    open( HORCM, "$horcm_file" );

    while (<HORCM>) {
        if (/${src}_(vg\d+)_${pkg}_(vg\d+)\s+.*\s+(..):(..)/) {
            my $srcvg     = $1;
            my $pkgvg     = $2;
            my $cu        = $3;
            my $ldev      = $4;
            my $curr_disk = "/dev/mapper/xpdisk_${cu}${ldev}";
            push( @pkg_disks,         $curr_disk );
            push( @{ HoA->{$pkgvg} }, $curr_disk );
            push( @horcm_pairs,       "${src}_${srcvg}_${pkg}_${pkgvg}" );
            push( @pkgvgs,            $pkgvg );
            push( @srcvgs,            $srcvg );
        }
    }
    $self->_set_horcm_pairs( \@horcm_pairs );
    $self->_set_basevgname_hash( \%HoA );
    $self->_set_pkg_disks( \@pkg_disks );
    $self->_set_pkg_vgs( \@pkgvgs );
    $self->_set_src_vgs( \@srcvgs );
    foreach my $newvg ( keys %HoA ) {
        my @tmparray = @{ $HoA{$newvg} };
        tie @importarray, 'Array::Unique';
        foreach $local_elem (@tmparray) {
            push( @importarray, $local_elem );
        }
        $curr_vgimportclone_cmd =
          sprintf("/sbin/vgimportclone --basevgname $newvg @{importarray}\n");
        push( @vgimportclone_cmds, $curr_vgimportclone_cmd );
    }
    $self->_set_vgimportclone_cmds( \@vgimportclone_cmds );

}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
