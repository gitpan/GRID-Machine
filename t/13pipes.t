#!/usr/local/bin/perl -w
use strict;
use Test::More tests => 15;
BEGIN { use_ok('GRID::Machine', 'is_operative') };

my $test_exception_installed;
BEGIN {
  $test_exception_installed = 1;
  eval { require Test::Exception };
  $test_exception_installed = 0 if $@;
}

my $host = $ENV{GRID_REMOTE_MACHINE};

SKIP: {
    skip "Remote not operative", 14 unless 
      ($host and $test_exception_installed and is_operative('ssh', $host) and ( $^O eq 'linux'));

    my $m;
    Test::Exception::lives_ok { 
      $m = GRID::Machine->new(host => $host);
    } 'No fatals creating a GRID::Machine object';

    my $i;
    my $f;
    Test::Exception::lives_ok { $f = $m->open('| sort -n') } "No fatals opening not redirected output pipe";
    for($i=10; $i>=0;$i--) {
      Test::Exception::lives_ok { $f->print("$i\n") } "No fatals sending to pipe $i";
    }
    Test::Exception::lives_ok { $f->close() } 'No fatals closing pipe';

} # end SKIP block

