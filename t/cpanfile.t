#!/usr/bin/env perl

use strict;
use warnings;
use File::Find;
use File::Spec;
use FindBin;
use Test::More;

my $root     = File::Spec->catdir( $FindBin::Bin, File::Spec->updir );
my $cpanfile = File::Spec->catfile( $root, 'cpanfile' );

plan skip_all => 'cpanfile is not part of the distribution' unless -f $cpanfile;

# the prerequisites of the cpanfile, per phase
my ( %runtime, %test, %develop );
{
  open my $fh, '<', $cpanfile or die "cannot read $cpanfile: $!";
  my $phase = 'runtime';
  while ( my $line = <$fh> ) {
    $phase = $1 if $line =~ /^\s*on\s+(\w+)\s*=>/;
    next unless $line =~ /^\s*requires\s+'([^']+)'/;
    if    ( $phase eq 'test' )    { $test{$1}    = 1 }
    elsif ( $phase eq 'develop' ) { $develop{$1} = 1 }
    else                          { $runtime{$1} = 1 }
  }
  close $fh;
}

# the distribution that carries a module, where it differs from the module
my %carries = (
  'Crypt::PK::RSA' => 'CryptX',
  'HTTP::Request'  => 'HTTP::Message',
  'HTTP::Response' => 'HTTP::Message',
  'Moo::Role'      => 'Moo',
  'URI::Escape'    => 'URI',
);

# a pragma, a module of the perl core and a module of this distribution need
# no declaration
my %skip = map { $_ => 1 } qw(
  Carp Digest::SHA Encode File::Find File::Spec FindBin MIME::Base64
  Scalar::Util Test::More lib overload parent strict utf8 warnings
);

# the files of the distribution, with the phase they belong to: the tests
# that the author needs for a release are a develop phase thing
my @files;
for my $dir (qw( lib t )) {
  my $path = File::Spec->catdir( $root, $dir );
  next unless -d $path;
  File::Find::find(
    {   no_chdir => 1,
        wanted   => sub {
          return unless -f $_ && /\.(?:pm|t)\z/;
          my $file = $File::Find::name;
          my $phase = $dir eq 'lib' ? 'runtime' : $file =~ m{/(?:author|release)-} ? 'develop' : 'test';
          push @files, [ $file, $phase ];
        },
    },
    $path,
  );
}

# the modules the code loads, per phase
my %used = ( runtime => {}, test => {}, develop => {} );
for my $file ( sort { $a->[0] cmp $b->[0] } @files ) {
  open my $fh, '<', $file->[0] or die "cannot read $file->[0]: $!";
  my $in_pod = 0;
  while ( my $line = <$fh> ) {
    if   ( $in_pod ) { $in_pod = 0 if $line =~ /^=cut/; next }
    elsif ( $line =~ /^=[a-zA-Z]/ ) { $in_pod = 1; next }
    next unless $line =~ /^\s*(?:use|require)\s+([A-Za-z][A-Za-z0-9_]*(?:::[A-Za-z0-9_]+)*)/;
    my $module = $1;
    next if $skip{$module};
    next if $module =~ /\AWWW::Authentik(?:::|\z)/;
    next if $module eq 'FakeAuthentik' || $module eq 'AuthentikExecutor';
    $used{ $file->[1] }{$module} = 1;
  }
  close $fh;
}

for my $module ( sort keys %{ $used{runtime} } ) {
  my $name = $carries{$module} // $module;
  ok( $runtime{$name}, "$module is a declared prerequisite" );
}

for my $module ( sort keys %{ $used{test} } ) {
  my $name = $carries{$module} // $module;
  ok( $runtime{$name} || $test{$name}, "$module is a declared prerequisite for the tests" );
}

for my $module ( sort keys %{ $used{develop} } ) {
  my $name = $carries{$module} // $module;
  ok( $runtime{$name} || $test{$name} || $develop{$name}, "$module is a declared prerequisite for the author tests" );
}

# the transport for https is not loaded by name, but without it every request
# over https fails
ok( $runtime{'LWP::Protocol::https'}, 'LWP::Protocol::https is a declared prerequisite' );

done_testing;
