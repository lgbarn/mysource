package Multipath;
use Moose;
use Array::Unique;
has 'cfg_file' => (
    is            => 'rw',
    default       => '/etc/multipath.conf',
    reader        => 'get_cfg_file',
    writer        => 'set_cfg_file',
    documentation => q{Points to default /etc/multipath.conf},
);

has 'cfg_file_contents' => (
    is            => 'rw',
    reader        => '_get_cfg_file_contents',
    writer        => '_set_cfg_file_contents',
    documentation => q{Initial multipath.conf contents},
);

has 'final_cfg_file_contents' => (
    is            => 'rw',
    reader        => 'get_final_cfg_file_contents',
    writer        => '_set_final_cfg_file_contents',
    documentation => q{Final contents of file after being compiled},
);

has 'alias_dup' => (
    is            => 'rw',
    reader        => 'get_alias_dup',
    writer        => '_set_alias_dup',
    documentation => q{This just holds the status for alias duplicates},
);

has 'wwid_dup' => (
    is            => 'rw',
    reader        => 'get_wwid_dup',
    writer        => '_set_wwid_dup',
    documentation => q{This just holds the status for wwid duplicates},
);

has 'multipaths' => (
    is            => 'rw',
    reader        => 'get_multipaths',
    writer        => 'set_multipaths',
    trigger       => \&_compile_new_multipaths,
    documentation => q{Array holding multipath aliases to be compiled},
);

has 'final_multipaths' => (
    is      => 'rw',
    reader  => '_get_final_multipaths',
    writer  => '_set_final_multipaths',
    trigger => \&_create_new_file,
    documentation =>
      q{multipaths section that will be compiled into finale file},
);

sub BUILD {

    my $self     = shift;
    my $cfg_file = $self->get_cfg_file();
    my $alias;
    my @contents;
    my %multipaths;
    my %wwid_seen;
    my $wwid_dup = 0;
    my %alias_seen;
    my $alias_dup = 0;
    my $multipath_file_contents;
    my $multipath_section_contents;
    my $wwid;
    open( FILE, "< $cfg_file" );

    while ( defined( $_ = <FILE> ) ) {
        chomp();
        push( @contents, $_ ) if /multipath\s+{/ ... /}/s;
        s/#.*//g;
        chomp();
        if ( /multipath\s+{/ ... /}/ ) {
            if (/alias\s+(\w+)/) {
                $alias = $1;
            }
            if (/wwid\s+(\w+)/) {
                $wwid = $1;
            }
            if (/}/) {
                $multipaths{$alias} = $wwid;
                $alias_seen{$alias}++;
                $wwid_seen{$wwid}++;
                if ( $alias_seen{$alias} > 1 ) {
                    $alias_dup = 1;
                }
                if ( $wwid_seen{$wwid} > 1 ) {
                    $wwid_dup = 1;
                }
            }
        }
    }
    open( FILE, "< $cfg_file" );
    @contents = <FILE>;
    chomp(@contents);
    $multipath_file_contents = join( "\n", @contents );
    $self->_set_cfg_file_contents($multipath_file_contents);
    $self->set_multipaths( \%multipaths );
    $self->_set_alias_dup($alias_dup);
    $self->_set_wwid_dup($wwid_dup);

}

sub get_wwid_from_alias {
    my $self  = shift;
    my $alias = shift;
    my $wwid;
    my %multipaths;
    %multipaths = %{ $self->get_multipaths() };
    $wwid       = $multipaths{$alias};
    return $wwid;
}

sub set_wwid_to_alias {
    my $self  = shift;
    my $alias = shift;
    my $wwid  = shift;
    my $error = 0;
    my $path;
    my $value;
    my %multipaths;
    %multipaths = %{ $self->get_multipaths() };

    foreach $value ( values %multipaths ) {
        if ( $wwid eq $value ) {
            $error = 1;
        }
    }
    if ( $error == 0 ) {
        $multipaths{$alias} = $wwid;
        $self->set_multipaths( \%multipaths );
    }
    return $error;
}

sub _compile_new_multipaths {
    my $self = shift;
    my @new_multipaths;
    my $alias;
    my $final_multipaths;
    my %multipaths = %{ $self->get_multipaths() };
    push( @new_multipaths, "multipaths {" );
    foreach $alias ( sort keys %multipaths ) {
        push( @new_multipaths, "       multipath {" );
        push( @new_multipaths,
            "               wwid                    $multipaths{$alias}" );
        push( @new_multipaths,
            "               alias                   $alias" );
        push( @new_multipaths, "       }" );
    }
    push( @new_multipaths, "}" );
    $final_multipaths = join( "\n", @new_multipaths );
    $self->_set_final_multipaths($final_multipaths);
}

sub _create_new_file {
    my $self = shift;
    my $curr_file;
    $curr_file = $self->_get_cfg_file_contents();
    my $final_multipaths = $self->_get_final_multipaths();
    $curr_file =~ s/multipaths\s+{.*}/$final_multipaths/gms;
    $self->_set_final_cfg_file_contents($curr_file);
}

sub check_dups {
    my $self = shift;
    my %multipaths;
    my $ret;
    my $alias_dup;
    my $wwid_dup;
    %multipaths = %{ $self->get_multipaths() };
    $alias_dup = $self->get_alias_dup();
    $wwid_dup = $self->get_wwid_dup();
    $wwid_dup = $wwid_dup * 2;
    $ret = $alias_dup + $wwid_dup;
    return $ret;
}

no Moose;

__PACKAGE__->meta->make_immutable;

1;
