#!/usr/bin/env perl 
use warnings;
use strict;

use Data::Dumper;

my $numtests;
BEGIN {
    $numtests = 6;
}

use Test::More tests => $numtests;
BEGIN { use_ok('GRID::Machine', 'is_operative') };

my $test_exception_installed;
BEGIN {
 $test_exception_installed = 1;
 eval { require Test::Exception };
 $test_exception_installed = 0 if $@;
}


my $host = $ENV{GRID_REMOTE_MACHINE};
SKIP: {
      skip "Remote not operative or Test::Exception not installed", $numtests-1
    unless $host and $test_exception_installed and is_operative('ssh', $host);

   my $m;
   Test::Exception::lives_ok {
     $m = GRID::Machine->new(
          host => $host,
          prefix => '/tmp/',
          log => '/tmp',
          err => '/tmp',
          startdir => '/tmp/',
          #debug => 12344,
          wait => 10,
    );
   } 'No fatals creating a GRID::Machine object';

    my $r = $m->system("hostname");
    is($r->stderr, '', 'no errors');

    $r = $m->system('pwd');
    like($r, qr{/tmp}, 'pwd is /tmp');

    $r = $m->system('ls -l ') ;
    like($r, qr{rperl\w+.err}, 'err file found in startdir');
    like($r, qr{rperl\w+.log}, 'err file found in startdir');
}



