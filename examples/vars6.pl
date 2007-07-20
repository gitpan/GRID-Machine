#!/usr/local/bin/perl -w
use strict;
use GRID::Machine;

my $machine = GRID::Machine->new(host => 'casiano@beowulf.pcg.ull.es');

my $r = $machine->eval(q{
#line 9  "vars3.pl"
  my $h = 1;

  use vars '$dumph';
  $dumph = sub {
    print "$h";
    $h++;
  };

  $dumph->();
});

print "$r\n";

$r = $machine->eval(q{
#line 24  "vars3.pl"
  $dumph->();
});

print "$r\n";
