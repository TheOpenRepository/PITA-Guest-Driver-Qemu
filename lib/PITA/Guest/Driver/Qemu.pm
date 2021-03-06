package PITA::Guest::Driver::Qemu;

=pod

=head1 NAME

PITA::Guest::Driver::Qemu - PITA Guest Driver for Qemu images

=head1 DESCRIPTION

TO BE COMPLETED

=cut

use 5.005;
use strict;
use base 'PITA::Guest::Driver::Image';
use version                  ();
use Carp                     ();
use URI                      ();
use File::Temp               ();
use File::Which              ();
use File::Remove             ();
use Params::Util             ();
use Filesys::MakeISO         ();

use vars qw{$VERSION};
BEGIN {
	$VERSION = '0.40';
}





#####################################################################
# Constructor and Accessors

sub new {
	my $class = shift;
	my $self  = $class->SUPER::new(@_);

	# Locate the qemu binary
	unless ( $self->qemu_bin ) {
		$self->{qemu_bin} = $self->qemu_default;
	}
	unless ( $self->qemu_bin ) {
		Carp::croak("Cannot locate qemu, requires explicit param");
	}
	unless ( -x $self->qemu_bin ) {
		Carp::croak("Insufficient permissions to run qemu");
	}

	# Find the install qemu version
	my $qemu_bin = $self->qemu_bin;
	my @lines    = `$qemu_bin -h`;
	unless ( $lines[0] =~ /version ([\d\.]+),/ ) {
		Carp::croak("Failed to locate Qemu version");
	}
	$self->{qemu_version} = version->new("$1");

	# Check the qemu version
	unless ( $self->qemu_version >= version->new('0.7.0') ) {
		Carp::croak("Currently only supports qemu 0.7.0 or newer");
	}

	# Get a temporary file to build the ISO image to
	unless ( $self->injector_iso ) {
		(undef, $self->{injector_iso}) = File::Temp::tempfile( SUFFIX => '.iso' );
	}
	unless ( $self->injector_iso ) {
		Carp::croak("Failed to find or create a temporary file for the injector iso");
	}

	return $self;
}

sub injector_iso {
	$_[0]->{injector_iso};
}

sub qemu_bin {
	$_[0]->{qemu_bin};	
}

sub qemu_version {
	$_[0]->{qemu_version};
}

# Attempt to independantly locate the qemu executable
sub qemu_default {
	my $self = shift;
	my $bin  = File::Which::which('qemu');
	return $bin if defined $bin;

	# Additional default locations to search on Windows
	if ( $^O eq 'MSWin32' and $ENV{PROGRAMFILES} ) {
		# Look for the Strawberry version
		$bin = 'C:\\strawberry\\qemu\\qemu.exe';
		return $bin if -f $bin;

		# Look for the QemuManager version
		my $bin = File::Spec->catfile(
			$ENV{PROGRAMFILES},
			'QemuManager',
			'qemu',
			'qemu.exe'
		);
		return $bin if -f $bin;
	}

	return undef;
}





#####################################################################
# PITA::Guest::Driver::Qemu Methods

# Generate the basic qemu launch command
sub qemu_command {
	my $self = shift;
	my @cmd  = ( $self->qemu_bin );

	# Set the memory level
	push @cmd, '-m' => $self->memory;

	# Run in snapshot mode?
	if ( $self->snapshot ) {
		push @cmd, '-snapshot';
	}

	# Run headless
	push @cmd, '-nographic';

	# Set the main hard drive
	push @cmd, '-hda' => $self->image;

	# Set the injector directory
	push @cmd, '-cdrom' => $self->injector_iso;

	return \@cmd;
}

# sub support_server_new {
	# my $self = shift;
	# $DB::single = 1;
	# require PITA::POE::SupportServer;
	# PITA::POE::SupportServer->new(
		# execute               => $self->qemu_command,
		# http_local_addr       => $self->support_server_addr,
		# http_local_port       => $self->support_server_port,
		# http_mirrors          => {},
		# http_result           => $self->support_server_results,
		# http_startup_timeout  => 30,
		# http_activity_timeout => 60,
		# http_shutdown_timeout => 30,
	# ) or die "Failed to create support server";
# }

sub support_server_new {
	my $self   = shift;
	my $server = PITA::Guest::Server::Process->new(
		Program     => $self->qemu_command,
		Hostname    => $self->support_server_addr,
		Port        => $self->support_server_port,
		Mirrors     => { },
		# http_result => $self->support_server_results,
		# http_startup_timeout  => 30,
		# http_activity_timeout => 60,
		# http_shutdown_timeout => 30,
	) or die "Failed to create support server";

	return $server;
}




#####################################################################
# PITA::Guest::Driver::Image Methods

# Qemu uses a standard networking setup
sub support_server_addr {
	$_[0]->support_server
		? shift->SUPER::support_server_addr
		: '127.0.0.1';
}

sub support_server_uri {
	URI->new( "http://10.0.2.2:51234/" );
}

# Build the injector directory as normal,
# then compile into an ISO image.
sub prepare_task {
	my $self = shift;
	$self->SUPER::prepare_task(@_);

	# Use Filesys::MakeISO to build the ISO file
	my $mkisofs = Filesys::MakeISO->new;
	$mkisofs->dir($self->injector_dir);
	$mkisofs->image($self->injector_iso);
	$mkisofs->joliet(1);
	$mkisofs->rock_ridge(1);
	unless ( $mkisofs->make_iso ) {
		Carp::croak("Failed to create injector ISO image");
	}

	1;
}

# When we clean the injectors, truncate (but don't delete) the iso file
sub clean_injector {
	my $self = shift;
	$self->SUPER::clean_injector(@_);

	# Truncate the iso file
	unless ( open( ISO, '>', $self->injector_iso ) ) {
		Carp::croak("Failed to truncate injector_iso file");
	}
	unless ( print ISO '' ) {
		Carp::croak("Failed to truncate injector_iso file");
	}
	unless ( close ISO ) {
		Carp::croak("Failed to truncate injector_iso file");
	}

	1;
}





#####################################################################
# PITA::Guest::Driver Methods

sub DESTROY {
	$_[0]->SUPER::DESTROY();
	if ( $_[0]->{injector_iso} and -f $_[0]->{injector_iso} ) {
		File::Remove::remove( $_[0]->{injector_iso} );
	}
}

1;

=pod

=head1 SUPPORT

Bugs should be reported via the CPAN bug tracker at

L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=PITA-Host-Driver-Qemu>

For other issues, contact the author.

=head1 AUTHOR

Adam Kennedy <adamk@cpan.org>

=head1 COPYRIGHT

Copyright (c) 2005 - 2006 Adam Kennedy.

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the
LICENSE file included with this module.

=cut
