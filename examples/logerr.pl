#!/usr/local/bin/perl -w
use strict;
use GRID::Machine;

my $machine = GRID::Machine->new( host => $ENV{GRID_REMOTE_MACHINE} || shift);
print $machine->eval(q{ system('ls -l *.err *.log') })->stdout;
