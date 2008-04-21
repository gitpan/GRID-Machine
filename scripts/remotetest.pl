#!/usr/local/bin/perl -w
use strict;
use GRID::Machine;

####################################################################
# Usage      : $input = slurp_file($filename, 'trg');
# Purpose    : opens  "$filename.trg" and sets the scalar
# Parameters : file name and extension (not icluding the dot)
# Comments   : Is this O.S dependent?

sub slurp_file {
  my ($filename, $ext) = @_;

    die "Error in slurp_file opening file. Provide a filename!\n" 
  unless defined($filename) and length($filename) > 0;
  $ext = "" unless defined($ext);
  $filename .= ".$ext" unless (-r $filename) or ($filename =~ m{[.]$ext$});
  local $/ = undef;
  open my $FILE, $filename or die "Can't open file $filename"; 
  my $input = <$FILE>;
  close($FILE);
  return $input;
}


my $dist = shift or die "Usage:\n$0 distribution.tar.gz machine1 machine2 ... \n";

die "No distribution $dist found\n" unless -r $dist;

  die "Distribution does not follow standard name convention\n" 
unless $dist =~ m{([\w.-]+)\.tar\.gz$};
my $dir = $1;

die "Usage:\n$0 distribution.tar.gz machine1 machine2 ... \n" unless @ARGV;
for my $host (@ARGV) {

  my $m = eval { 
    GRID::Machine->new(host => $host, uses  => [ qw{File::Spec} ]) 
  };

  warn "Cant' create GRID::Machine connection with $host\n", next unless UNIVERSAL::isa($m, 'GRID::Machine');

  my $r = $m->eval(q{ 
      chdir(File::Spec->tmpdir) or die "Can't change to dir ".File::Spec->tmpdir."\n"; 
    }
  );

  my $preamble = $host.".preamble.pl";
  if (-r $preamble) {
    local $/ = undef;

    my $code = slurp_file($preamble);
    $r = $m->eval($code);
    warn("Error in $host preamble: $r"),next unless $r->ok;
  }

  warn($r),next unless $r->ok;

  $m->put([$dist]) or die "Can't copy distribution in $host\n";

  $r = $m->eval(q{
      my $dist = shift;

      eval('use Archive::Tar');
      if (Archive::Tar->can('new')) {
        # Archive::Tar is installed, use it
        my $tar = Archive::Tar->new;
        $tar->read($dist,1) or die "Archive::Tar error: Can't read distribution $dist\n";
        $tar->extract() or die "Archive::Tar error: Can't extract distribution $dist\n";
      }
      else {
        system('gunzip', $dist) or die "Can't gunzip $dist\n";
        my $tar = $dist =~ s/\.gz$//;
        system('tar', '-xf', $tar) or die "Can't untar $tar\n";
      }
    },
    $dist # arg for eval
  );

  warn($r), next unless $r->ok;

  $m->chdir($dir)->ok or do {
    warn "$host: Can't change to directory $dir\n";
    next;
  };

  print "************$host************\n";
  next unless $m->run('perl Makefile.PL');
  next unless $m->run('make');
  next unless $m->run('make test');
}

=head1 NAME

remotetest.pl - make tests on a remote machine


=head1 SYNOPSYS

  remotetest.pl MyInteresting-Dist-1.107.tar.gz machine1.domain machine2.domain

=head1 DESCRIPTION

The script C<remotetest.pl> copies a Perl distribution (see L<ExtUtils::MakeMaker>)
to each of the listed machines via C<scp>
and proceeeds to run C<make test> on a temporary directory. 
Check your distribution on diferent platforms avoiding the familiar excuse
I<It works on my machine>.

The script assumes that 
automatic authentification via ssh has been set up with each of the remote machines.

When conecting to C<machine1.domain> the program checks if a file
with name C<machine1.domain.premable.pl> exists. If so it will be 
loaded and evaluated before running the tests in C<machine1.domain>

=head2 Example

I have a file named C<beowulf.preamble.pl> in the ditribution directory:

pp2@nereida:~/LGRID_Machine$ cat -n beowulf.preamble.pl
     1  $ENV{GRID_REMOTE_MACHINE} = "orion";

Now when I run C<remotetest.pl> for a distribution in machine C<beowulf>
the environment variable C<GRID_REMOTE_MACHINE> will be set in beowulf prior
to the execution of the tests:

  pp2@nereida:~/LGRID_Machine$ scripts/remotetest.pl GRID-Machine-0.090.tar.gz beowulf
  ************beowulf************
  Writing Makefile for GRID::Machine
  Manifying blib/man3/GRID::Machine::Result.3pm
  Manifying blib/man3/GRID::Machine.3pm
  Manifying blib/man3/GRID::Machine::RIOHandle.3pm
  Manifying blib/man3/GRID::Machine::MakeAccessors.3pm
  Manifying blib/man3/GRID::Machine::REMOTE.3pm
  Manifying blib/man3/GRID::Machine::Message.3pm
  Manifying blib/man3/GRID::Machine::IOHandle.3pm
  Manifying blib/man3/GRID::Machine::Core.3pm
  PERL_DL_NONLAZY=1 /usr/bin/perl "-MExtUtils::Command::MM" "-e" "test_harness(0, 'blib/lib', 'blib/arch')" t/*.t
  t/01synopsis..............ok
  t/02pod...................ok
  t/03includes..............ok
  t/05podcoverage...........ok
  t/06callbacks.............ok
  t/07anonymouscallback2....ok
  t/08callbackbyname........ok
  t/09errandlinenumbers.....ok
  t/10manyevals.............ok
  t/11tworemoteinputs.......ok
  t/12pipes.................ok
  t/13pipes.................ok
  All tests successful.
  Files=12, Tests=209, 10 wallclock secs ( 3.46 cusr +  0.31 csys =  3.77 CPU)


=head1 AUTHOR

Casiano Rodriguez-Leon 

=head1 COPYRIGHT

(c) Copyright 2008 Casiano Rodriguez-Leon

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut

