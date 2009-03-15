#!/usr/bin/perl
use warnings;
use strict;
use Scalar::Util qw{looks_like_number};

use IO::Select;
use GRID::Machine;
use Time::HiRes qw(time gettimeofday tv_interval);
use List::Util qw(sum);
use File::Basename qw(fileparse);
use Getopt::Long;

use constant BUFFERSIZE => 2048;

my %machine; # Hash of GRID::Machine objects
my %map_id_machine; # Hash that contains a machine name given an id of a process

my $config = 'MachineConfig.pm';
my $np;

my $A  = "data/A100x100.dat";
my $B  = "data/B100x100.dat";
my $resultfile = '';
my $clean = 0; # clean the matrix dir in the remote machines

GetOptions(
  'config=s' => \$config, # Module containing the definition of %machine and %map_id_machine
  'np=i'     => \$np,
  'a=s'      => \$A,
  'b=s'      => \$B,
  'clean'    => \$clean,
  'result=s' => \$resultfile,
) or die "bad usage\n";

our (%debug,  %max_num_proc);
require $config;

my @machine = sort { $max_num_proc{$b} <=> $max_num_proc{$a} } keys  %max_num_proc; # qw{europa beowulf orion};
my $nummachines = @machine;
$np ||= $nummachines; # number of processes

die "Cant find matrix file $A\n" unless -r $A;
die "Cant find matrix file $B\n" unless -r $B;

# Reads the dimensions of the matrix
open DAT, $A or die "The file $A can't be opened to read\n";
my $line = <DAT>;
my ($A_rows, $A_cols) = split(/\s+/, $line);
close DAT;

open DAT, $B or die "The file $B can't be opened to read\n";
$line = <DAT>;
my ($B_rows, $B_cols) = split(/\s+/, $line);
close DAT;

# Checks the dimensions of the matrix
die "Dimensions error. Matrix A: $A_rows x $A_cols, Matrix B: $B_rows x $B_cols.\n" if ($A_cols != $B_rows);

# Checks that the number of processes doesn't exceed
# the number of rows of the matrix A
die "Too many processes. $np processes for $A_rows rows\n" if ($np > $A_rows);

# Checks that the number of processes doesn't exceed the
# maximum number of processes supported by all machines
my $max_processes = sum values %max_num_proc;
die "Too many processes. The list of actual machines only supports a maximum of $max_processes processes\n" if ($np > $max_processes);

my $lp = $np - 1;
my @pid;  # List of process pids
my @proc; # List of handles
my %id;   # Gives the ID for a given handle

my $readset = IO::Select->new();

my ($filename_A, $path_A) = fileparse($A);
my ($filename_B, $path_B) = fileparse($B);

my $i = 0;
for (@machine) {
	my $m = GRID::Machine->new(host => $_, debug => $debug{$_}, );

	$m->copyandmake(
	  dir        => 'matrix',
	  makeargs   => 'matrix',
	  files      => [ 'matrix.c', 'Makefile', $A, $B ],
	  cleanfiles => $clean,
	  cleandirs  => $clean, # remove the whole directory at the end
	  keepdir    => 1,
	) unless $m->_r("matrix/matrix.c")->result && $m->_stat("matrix/matrix.c")->results->[9] >= (stat("matrix.c"))[9] &&
           $m->_r("matrix/$filename_A")->result && $m->_r("matrix/$filename_B")->result;

	$m->chdir("matrix/");

	die "Can't execute 'matrix'\n" unless $m->_x("matrix")->result;

	$machine{$_} = $m;
	last unless ++$i < $np;
}

my $t0 = [gettimeofday];

my $counter = 0;

for (@machine) {
  for my $actual_proc (0 .. $max_num_proc{$_} - 1) {
	  my $m = $machine{$_};
	  ($proc[$counter], $pid[$counter]) = $m->open("./matrix $counter $np $filename_A $filename_B|");
    $proc[$counter]->blocking(0);  # Non-blocking reading
    $map_id_machine{$counter} = $_;
	  $readset->add($proc[$counter]);
	  my $address = 0+$proc[$counter];
	  $id{$address} = $counter;
    last if (++$counter > $lp);
  }
  last if ($counter > $lp);
}

my @ready;
my $count = 0;
my $result = [];

local $/ = undef;
while ($count < $np) {
  push @ready, $readset->can_read unless @ready;

	my $handle = shift @ready; 

  my $me = $id{0+$handle};

  my ($r, $auxline, $bytes);

  while ((!defined($bytes)) || ($bytes)) {
    $bytes = sysread($handle, $auxline, BUFFERSIZE);
    $r .= $auxline if ((defined($bytes)) && ($bytes));
  }

  $result->[$me] = eval $r;
  die "Wrong result from process $me in machine $map_id_machine{$me}\n" unless defined($result->[$me]);
  print "Process $me: machine = $map_id_machine{$me} received result\n";

  $readset->remove($handle) if eof($handle);

  close $handle;

	$count++;
}

# Place result rows in their final location
my @r = map { @$_ } @$result;

my $elapsed = tv_interval($t0);
print "Elapsed Time: $elapsed seconds\n";


if ($resultfile) { 
  print "sending result to $resultfile\n";
  open my $f, "> $resultfile";
  print $f "@$_\n" for @r;
  close($f);
}
elsif (@r < 11) { # Send to STDOUT
  print "@$_\n" for @r;
}

# close machines
$machine{$_}->DESTROY for (@machine);
