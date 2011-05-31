#!/usr/local/bin/perl -w
use strict;

our (
$nt, 
$nt2,
$nt3,
$nt4,
$nt5,
$nt6,
$nt7,
$nt8,
$nt9,
);

BEGIN {
$nt  = 2;
$nt2 = 1;
$nt3 = 1;
$nt4 = 1;
$nt5 = 1;
$nt6 = 1;
$nt7 = 1;
$nt8 = 1;
$nt9 = 1;
};

use Test::More tests => $nt+$nt2+$nt3+$nt4+$nt5+$nt6+$nt7+$nt8+$nt9;

BEGIN { 
  use_ok('GRID::Machine', 'is_operative');
  use_ok('GRID::Machine::Group');
};

my $test_exception_installed;
BEGIN {
  $test_exception_installed = 1;
  eval { require Test::Exception };
  $test_exception_installed = 0 if $@;
}

my @MACHINE_NAMES = split /\s+/, $ENV{MACHINES} || '';

SKIP: {
  skip "t/pi.pl not found", $nt2 unless (@MACHINE_NAMES && $ENV{DEVELOPER} && -x "t/pi.pl");

  my $r = qx{perl -I./lib/ t/pi.pl 2>&1};
  
  my $expected = qr{
Pi\s+=\s+ 3.14\d*.\s+N\s+=\s+1000\s+Time\s+=\s+\d+.?\d*
}x;

  like($r, $expected,'Computing pi in parallel. Implicit construction');
}

SKIP: {
  skip "t/pi2.pl not found", $nt3 unless (@MACHINE_NAMES && $ENV{DEVELOPER} && -x "t/pi2.pl");

  my $r = qx{perl -I./lib/ t/pi2.pl 2>&1};
  
  my $expected = qr{
^\s* 3.14\d*.\s*$
}x;

  like($r, $expected,'Computing pi in parallel. Explicit construction');
}


SKIP: {
  skip "t/pi3.pl not found", $nt4 unless (@MACHINE_NAMES && $ENV{DEVELOPER} && -r "t/pi3.pl");

  my $r = qx{perl -I./lib/ t/pi3.pl 2>&1};
  
  my $expected = qr{
^\s* 3.14\d*.\s*$
}x;

  like($r, $expected,'Computing pi in parallel. Lazy arguments');
}

my $host = $ENV{GRID_REMOTE_MACHINE}; 
my $operative = 0;
$operative = is_operative('ssh', $host,'perldoc -l Inline::C') if ($host && $ENV{DEVELOPER});;
SKIP: {
  ##  mmm requires Inline::C installed in the remote machine
  skip "t/pi4.pl not found", $nt5 unless ($host && $ENV{DEVELOPER} && -r "t/pi4.pl" && $operative);

  my $r = qx{perl -I./lib/ t/pi4.pl 2>&1};
  
  my $expected = qr{
^\s* 3.14\d*.\s*$
}x;

  like($r, $expected,"Computing pi in $host. Using Inline::C with a single machine");
}


for (@MACHINE_NAMES) {
   $operative &&= is_operative('ssh', $_,'perldoc -l Inline::C');
   last unless $operative;
}

SKIP: {
  skip "t/pi5.pl not found", $nt6 unless (@MACHINE_NAMES && $ENV{DEVELOPER} && -r "t/pi5.pl" && $operative);

  my $r = qx{perl -I./lib/ t/pi5.pl 2>&1};
  
  my $expected = qr{
^\s* 3.1415\d*.\s*$
}x;

  like($r, $expected,'Computing pi in parallel. Inline:C Multiple machines');
}

SKIP: {
  skip "t/pi6.pl not found", $nt7 unless (@MACHINE_NAMES && $ENV{DEVELOPER} && -r "t/pi6.pl" && $operative);

  my $r = qx{perl -I./lib/ t/pi6.pl 2>&1};
  
  my $expected = qr{
^\s* 3.1415\d*.\s*$
}x;

  like($r, $expected,'Computing pi in parallel. Inline:C & makemethod Multiple machines');
}


SKIP: {
  skip "t/pi7.pl not found", $nt8 unless (@MACHINE_NAMES && $ENV{DEVELOPER} && -r "t/pi7.pl" && $operative);

  my $r = qx{perl -I./lib/ t/pi7.pl 2>&1};
  
  my $expected = qr{
^\s* 3.1415\d*.\s*$
}x;

  like($r, $expected,'Computing pi in parallel. Inline:C & eval on Multiple machines');
}


SKIP: {
  skip "t/waitpi.pl not found", $nt9 unless ($host && $ENV{DEVELOPER} && -r "t/waitpi.pl" && $operative);

  my $r = qx{perl -I./lib/ t/waitpi.pl 2>&1};
  
  my $expected = qr{
^pi\s*=\s*3.1415\d*.\s*$
}x;

  like($r, $expected,'forking. waitall');
}
