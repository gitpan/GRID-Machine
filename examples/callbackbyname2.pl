#!/usr/bin/perl -w
use strict;
use GRID::Machine;
use Sys::Hostname;

my $host = shift || $ENV{GRID_REMOTE_MACHINE};

sub test_callback {
  print 'Inside test_callback(). Host is '.&hostname."\n";
  
  return shift()+1;
} 

my $machine = GRID::Machine->new(host => $host, uses => [ 'Sys::Hostname' ]);

my $r = $machine->sub( remote => q{
    gprint hostname().": inside remote\n";

    return 1+test_callback(2);
} );
die $r->errmsg unless $r->ok;

$r = $machine->callback( 'test_callback' );
die $r->errmsg unless $r->ok;

$r = $machine->remote();
die $r->errmsg unless $r->noerr;

print "Result: ".$r->result."\n";
