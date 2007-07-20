#!/usr/local/bin/perl -w
use strict;
use GRID::Machine;

use Data::Dumper;

my $host = shift || 'casiano@beowulf.pcg.ull.es';

my $machine = GRID::Machine->new(host => $host, uses => [qw(PDL)]);

my $r = $machine->sub( 
  matrix => q{
    my ($f, $g) = @_;
    
    my $h = (pdl $f) x (pdl $g);

    print  "$h\n";
  },
);
$r->ok or die $r->errmsg;


my $f = [[1,2],[3,4]];
$r = $machine->matrix($f, $f);
die $r->errmsg unless $r->ok;

print "$r\n";
