package THREEPAR;
use Moose;

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

has 'pkg_disks' => (
    is     => 'rw',
    reader => 'get_pkg_disks',
    writer => '_set_pkg_disks',
);

has 'remove_vlun_cmds' => (
    is     => 'rw',
    reader => 'get_remove_vlun_cmds',
    writer => '_set_remove_vlun_cmds',
);

has 'conf_wwns' => (
    is     => 'rw',
    reader => 'get_conf_wwns',
    writer => '_set_conf_wwns',
);

has 'hostname' => (
    is     => 'rw',
    reader => 'get_hostname',
    writer => 'set_hostname',
);

has 'vv_wwids' => (
    is     => 'rw',
    reader => 'get_vv_wwids',
    writer => '_set_vv_wwids',
);

has 'host_vv_wwids' => (
    is     => 'rw',
    reader => 'get_host_vv_wwids',
    writer => '_set_host_vv_wwids',
);

has 'pkg_disks' => (
    is     => 'rw',
    reader => 'get_pkg_disks',
    writer => '_set_pkg_disks',
);

has 'src_disks' => (
    is     => 'rw',
    reader => 'get_src_disks',
    writer => '_set_src_disks',
);

has 'vg_map' => (
    is     => 'rw',
    reader => 'get_vg_map',
    writer => '_set_vg_map',
);

has 'pkg_filename' => (
    is     => 'rw',
    reader => 'get_pkg_filename',
    writer => 'set_pkg_filename',
);

has 'pkg_import_disks' => (
    is     => 'rw',
    reader => 'get_pkg_import_disks',
    writer => 'set_pkg_import_disks',
);

sub parse_showvv {
    my $self = shift;
    my %vv_wwids;
    my $vv_name;
    my $vv_wwid;
    my $lc_vv_wwid;
    my $hostname = $self->get_hostname();
    open( SHOWVV_D, "cli showvv -d -host $hostname | " );
    while (<SHOWVV_D>) {

        #if (/\d+\s+($hostname.+)\s+RW.*\s+--\s+(.+)\s+\d\d\d\d\-\d\d\-\d\d/) {
        if (/\d+\s+(brdbs5.+)\s+RW.*\s+--\s+(.+)\s+\d\d\d\d\-\d\d\-\d\d/) {
            chomp();
            $vv_name            = $1;
            $vv_wwid            = $2;
            $lc_vv_wwid         = lc($vv_wwid);
            $vv_wwids{$vv_name} = $lc_vv_wwid;
        }
    }
    $self->_set_vv_wwids( \%vv_wwids );
}

sub parse_showvlun {
    my $self = shift;
    my @pkg_disks;
    my @remove_vlun_cmds;
    my $remove_vlun_cmd;
    my $vlun_name;
    my $vlun_lunid;
    my $lc_vv_wwid;
    my $pkg      = $self->get_pkg();
    my $hostname = $self->get_hostname();
    open( SHOWVLUN, "cli showvlun -t -host $hostname | " );

    while (<SHOWVLUN>) {
        if (/\s+(\d+)\s+(${pkg}_\w+)\s+\w+\s+\-+\s+\-+\s+host/) {
            chomp();
            $vlun_lunid = $1;
            $vlun_name  = $2;
            chomp($vlun_lunid);
            chomp($vlun_name);
            push( @pkg_disks, $vlun_name );
            $remove_vlun_cmd =
              sprintf("cli removevlun -f  $vlun_name $vlun_lunid $hostname\n");
            $remove_vlun_cmd =~ s/\s+/ /g;
            push( @remove_vlun_cmds, $remove_vlun_cmd );
        }
    }
    $self->_set_pkg_disks( \@pkg_disks );
    $self->_set_remove_vlun_cmds( \@remove_vlun_cmds );
}

sub BUILD {
    my $self = shift;
    my %confName;
    my $conf_wwid;
    open( MULTIPATH_CONF, "/etc/multipath.conf" );
    while (<MULTIPATH_CONF>) {
        if (/^\s+wwid\s+(.+)/) {
            $conf_wwid = $1;
        }
        if (/^\s+alias\s+(.+)/) {
            my $alias = $1;
            chomp($alias);
            chomp($conf_wwid);
            $confName{$alias} = $conf_wwid;
        }
    }
    $self->_set_conf_wwns( \%confName );
}

sub conv_vv_wwids {
    my $self = shift;
    my $key;
    my $value;
    my %host_vv_wwids;
    %host_vv_wwids = %{ $self->get_conf_wwns() };
    foreach $key ( keys %host_vv_wwids ) {
        $value = $host_vv_wwids{$key};
        $value =~ s/350002ac/50002ac/g;
        $host_vv_wwids{$key} = $value;
    }
    $self->_set_host_vv_wwids( \%host_vv_wwids );
}

sub parse_showvvset {
    my $self = shift;
    my $server;
    my $filename = $self->get_pkg_filename();
    $server = $self->get_src();
    my @src_disks;
    open( SHOWVVSET_PIPE, "cli showvvset ${filename} | " );
    while (<SHOWVVSET_PIPE>) {
        if (/(($server)_(vg\d+)_(.+))/) {
            my $disk = $1;
            my $pkg  = $2;
            my $vg   = $3;
            my $rest = $4;
            chomp($disk);
            push( @src_disks, $disk );
        }
    }
    $self->_set_src_disks( \@src_disks );
}

sub parse_pkg_file {
    my $self = shift;
    my $vvset;
    my $pri_vg;
    my $snap_vg;
    my %vg_map;
    my $pkg_filename = $self->get_pkg_filename();
    open( PKG_FILE, "$pkg_filename" );
    while (<PKG_FILE>) {

        if (/(pkg.+)/) {
            $vvset = $1;
        }
        if (/(vg\d+):(vg\d+)/) {
            $pri_vg          = $1;
            $snap_vg         = $2;
            $vg_map{$pri_vg} = $snap_vg;
        }
    }
    $self->_set_vg_map( \%vg_map );
}

sub get_vgimport_cmds {
    my $self = shift;
    my %cmds;
    my $vg;
    my $import_vg;
    my $disk;
    tie my @clean_disks, 'Array::Unique';
    my @pkg_import_disks;
    @pkg_import_disks = @{ $self->get_pkg_import_disks() };

    foreach $disk (@pkg_import_disks) {
        push( @clean_disks, $disk );
    }
    foreach $disk (@clean_disks) {
        if ( $disk =~ /_(vg\d+)_/ ) {
            $vg = $1;
            if ( $cmds{$vg} ) {
                $cmds{$vg} = "$cmds{$vg} /dev/mapper/${disk}";
            }
            if ( !$cmds{$vg} ) {
                $cmds{$vg} =
                  "vgimportclone -i --basevgname $vg /dev/mapper/${disk}";
            }
        }
    }
    return %cmds;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
