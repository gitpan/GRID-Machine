#!/usr/local/bin/perl -w
use strict;
use GRID::Machine;

my $machine = shift || 'orion.pcg.ull.es';
my $m = GRID::Machine->new( host => $machine );

for (qw(r w e x z s f d  t T B M A C)) {  
  $m->compile( "$_" => qq{
      my \$file = shift;
      
      return -$_ \$file;
    }
  );
}

my @files = $m->eval(q{ glob('*') })->Results;

for (@files) {
  print "$_ is a directory\n" if $m->call('d', "$_")->result;
}
