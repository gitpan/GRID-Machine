#!/usr/local/bin/perl -w
use strict;
use Test::More tests => 3;
BEGIN { use_ok('GRID::Machine', qw(is_operative qc)) };

my $test_exception_installed;
BEGIN {
  $test_exception_installed = 1;
  eval { require Test::Exception };
  $test_exception_installed = 0 if $@;
}

my $machine;
sub syntaxerr {
  my $r;

  my $p = { name => 'Peter', familyname => [ 'Smith', 'Garcia'] };

  $r = $machine->eval( qc(q{ 
      $q = shift; 
      $q->{familyname} 
    }), $p
  );

  die "$r" unless $r->ok;
}

my $host = $ENV{GRID_REMOTE_MACHINE};

SKIP: {
    skip "Remote not operative or Test::Exception not installed", 2
  unless $test_exception_installed and $host and is_operative('ssh', $host);

########################################################################

  Test::Exception::lives_ok { 
    $machine = GRID::Machine->new(host => $host);
  } 'No fatals creating a GRID::Machine object';

########################################################################


Test::Exception::throws_ok { syntaxerr() } qr/Error while compiling eval.*20/, 'line number err'; # throws_ok

} # end SKIP block

