#!/usr/local/bin/perl -w
use strict;
use GRID::Machine qw(is_operative);
use Data::Dumper;

my $host = 'casiano@beowulf.pcg.ull.es';

my $machine = GRID::Machine->new(
   host => $host, 
   command => ['ssh', '-X', $host, 'perl'], 
);

system('xhost +');
print $machine->eval(q{ 
  print "$ENV{DISPLAY}\n";
  system('xclock ');
});

