#!/usr/local/bin/perl -w
use strict;
use GRID::Machine qw(is_operative);
use Data::Dumper;

my $host = 'casiano@orion.pcg.ull.es';

my $machine = GRID::Machine->new(host => $host, ssh => 'ssh -X');

print $machine->eval(q{ system('xclock') });

