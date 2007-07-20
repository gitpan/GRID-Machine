#!/usr/local/bin/perl -w
use strict;
use GRID::Machine;

my $machine = GRID::Machine->new(host => 'casiano@beowulf.pcg.ull.es');

$machine->eval(q{
  our $h;
  $h = [4..9]; 
});

my $r = $machine->eval(q{
#line 14 "vars1.pl"
  $h = [map {$_*$_} @$h];
});

