#!/usr/local/bin/perl -w
use strict;
sub findVersion {
  my $pv = `perl -v`;
  my ($v) = $pv =~ /v(\d+\.\d+)\.\d+/;

  $v ? $v : 0;
}
use Test::More tests => 9;
BEGIN { use_ok('GRID::Machine', 'is_operative') };

my $test_exception_installed;
BEGIN {
  $test_exception_installed = 1;
  eval { require Test::Exception };
  $test_exception_installed = 0 if $@;
}

my $host = '';

my $machine;
SKIP: {
    skip "Remote not operative or Test::Exception not installed", 8
  unless (findVersion() > 5.6) && $test_exception_installed and is_operative('', $host);

########################################################################

  Test::Exception::lives_ok { 
    $machine = GRID::Machine->new(host => $host);
  } 'No fatals creating a GRID::Machine object';

########################################################################

  unshift @INC, "t/";
  $machine->include("Include");

  for my $method (qw(one two three)) {
    can_ok($machine, $method);
    is($machine->$method()->stdout, "$method\n", "and works");
  }

  ok(!$machine->can('four'), "DATA filehandle is correctly skipped");

} # end SKIP block
