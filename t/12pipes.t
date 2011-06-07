#!/usr/local/bin/perl -w
use strict;
use Test::More tests => 12;
BEGIN { use_ok('GRID::Machine', 'is_operative') };

my $host = $ENV{GRID_REMOTE_MACHINE} || '';

SKIP: {
    skip "Remote not operative", 11 unless is_operative('ssh', $host) and ($^O =~ /darwin|linux/);

    my $m = GRID::Machine->new( host => $host );

    my $i;
    my $f = $m->open("| sort -n > /tmp/sorted$$.txt");
    for($i=10; $i>=0;$i--) {
      $f->print("$i\n")
    }
    $f->close();

    my $g = $m->open("/tmp/sorted$$.txt");
    for($i=0; $i<=10; $i++) {
      my $found = <$g>;
      is($found, "$i\n", "$i in position");
    }

} # end SKIP block

