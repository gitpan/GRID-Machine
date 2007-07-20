#!/usr/local/bin/perl -w
use strict;
use GRID::Machine;

my $machine = GRID::Machine->new(
                   host => shift() || $ENV{GRID_REMOTE_MACHINE}, 
                   uses => [ 'Sys::Hostname' ]
              );

my $r = $machine->sub( iguales => q{
#line 12 "alias.pl"
    my ($first, $sec) = @_;

    print hostname().": $first and $sec are ";

    if ($first == $sec) {
      print "the same\n";
      return 1;
    }
    print "Different\n";
    return 0;
  },
);
$r->ok or die $r->errmsg;

my $w = [ 1..3 ];
my $z = $w;
$r = $machine->iguales($w, $z);
print $r;
