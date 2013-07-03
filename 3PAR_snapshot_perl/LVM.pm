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
    is     => 'rw',
    reader => 'get_pkg_vgs',
    writer => '_set_pkg_vgs',
);

has 'pkg_disks' => (
    is     => 'rw',
    reader => 'get_pkg_disks',
    writer => '_set_pkg_disks',
);

has 'src_fstab_vgs' => (
    is     => 'rw',
    reader => 'get_src_fstab_vgs',
    writer => '_set_src_fstab_vgs',
);

has 'pkg_fstab_vgs' => (
    is     => 'rw',
    reader => 'get_pkg_fstab_vgs',
    writer => '_set_pkg_fstab_vgs',
);

has 'src_mount_points' => (
    is     => 'rw',
    reader => 'get_src_mountpoints',
    writer => '_set_src_mountpoints',
);

has 'pkg_fstab_mount_points' => (
    is     => 'rw',
    reader => 'get_pkg_fstab_mountpoints',
    writer => '_set_pkg_fstab_mountpoints',
);

has 'src_fstab_mount_points' => (
    is     => 'rw',
    reader => 'get_src_fstab_mountpoints',
    writer => '_set_src_fstab_mountpoints',
);

has 'pkg_mount_points' => (
    is     => 'rw',
    reader => 'get_pkg_mountpoints',
    writer => '_set_pkg_mountpoints',
);

has 'src' => (
    is     => 'rw',
    reader => 'get_src',
    writer => 'set_src',
);

has 'pkg' => (
    is     => 'rw',
    reader => 'get_pkg',
    writer => 'set_pkg',
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

sub parse_vgdisplay {
    my $self = shift;
    my $vg;
    my $disk;
    my @pkg_disks;
    my @pkg_vgs = @{ $self->get_pkg_fstab_vgs() };
}

sub parse_fstab {
    my $self = shift;
    my @src_mounts;
    my @pkg_mounts;
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
        if (/^\/.*(vg\d+)\/.*(\/pkg\/$pkg\/\w+)\s+/) {
            my $pkg_mount = $2;
            my $pkg_vg    = $1;
            push( @pkg_mounts, $pkg_mount );
            push( @pkg_vgs,    $pkg_vg );
        }
    }
    $self->_set_src_fstab_mountpoints( \@src_mounts );
    $self->_set_src_fstab_vgs( \@src_vgs );
    $self->_set_pkg_fstab_mountpoints( \@pkg_mounts );
    $self->_set_pkg_fstab_vgs( \@pkg_vgs );
}

no Moose;

__PACKAGE__->meta->make_immutable;
1;
