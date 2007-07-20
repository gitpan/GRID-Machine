#!/usr/local/bin/perl -w
use strict;
use GRID::Machine;

my $dist = shift or die "Usage:\n$0 distribution.tar.gz machine1 machine2 ... \n";

die "No distribution $dist found\n" unless -r $dist;

  die "Distribution does not follow standard name convention\n" 
unless $dist =~ m{([\w.-]+)\.tar\.gz$};
my $dir = $1;

die "Usage:\n$0 distribution.tar.gz machine1 machine2 ... \n" unless @ARGV;
for my $host (@ARGV) {
  my $m = GRID::Machine->new(host => $host, startdir => '/tmp');

  $m->put([$dist]);

  $m->tar($dist, '-xz')->ok or do {
    warn "$host: Can't extract files from $dist\n";
    next;
  };

  $m->chdir($dir)->ok or do {
    warn "$host: Can't change to directory $dir\n";
    next;
  };

  print "************$host************\n";
  next unless $m->run('perl Makefile.PL');
  next unless $m->run('make');
  next unless $m->run('make test');
}
