package GRID::Machine::IOHandle;
use strict;

## Class methods

use overload '<>' => \&diamond;

# diamond works only in scalar context
sub diamond {
  my $self = shift;
  my $m = $self->{server};

  my $r = $m->diamond($self->{index}, @_);
  die $r unless $r->ok;
  return $r->result;
};

sub print {
  my $self = shift;
  my $m = $self->{server};

  $m->print($self->{index}, @_);

}

sub printf {
  my $self = shift;
  my $m = $self->{server};

  $m->printf($self->{index}, @_);

}

sub flush {
  my $self = shift;
  my $m = $self->{server};

  $m->flush($self->{index}, @_)->result;
}

sub autoflush {
  my $self = shift;
  my $m = $self->{server};

  $m->autoflush($self->{index}, @_)->result;
}

sub blocking {
  my $self = shift;
  my $m = $self->{server};

  $m->blocking($self->{index}, @_)->result;
}

sub close {
  my $self = shift;
  my $m = $self->{server};

  $m->close($self->{index}, @_)->result;
}

sub getc {
  my $self = shift;
  my $m = $self->{server};

  my $r = $m->getc($self->{index}, @_);
  die $r unless $r->ok;
  return $r->result;
}

sub getline {
  my $self = shift;
  my $m = $self->{server};

  my $r = $m->getline($self->{index}, @_);
  die $r unless $r->ok;
  return $r->result;
}

sub getlines {
  my $self = shift;
  my $m = $self->{server};

  my $r = $m->getlines($self->{index}, @_);
  die $r unless $r->ok;
  return $r->Results;
}

sub read {
  my $self = shift;
  my $m = $self->{server};

  my $r = $m->read($self->{index}, @_);
  die $r unless $r->ok;
  return $r->result;
}

sub sysread {
  my $self = shift;
  my $m = $self->{server};

  my $r = $m->sysread($self->{index}, @_);
  die $r unless $r->ok;
  return $r->result;
}

sub stat {
  my $self = shift;
  my $m = $self->{server};

  my $r = $m->stat($self->{index}, @_);
  die $r unless $r->ok;
  return $r->Results;
}

1;

__END__

=head1 NAME

GRID::Machine::IOHandle - supply object methods for I/O handles

=head1 SYNOPSIS

  use GRID::Machine;

  my $machine = shift || 'remote.machine';
  my $m = GRID::Machine->new( host => $machine );

  my $f = $m->open('> tutu.txt'); # Creates a GRID::Machine::IOHandle object
  $f->print("Hola Mundo!\n");
  $f->print("Hello World!\n");
  $f->printf("%s %d %4d\n","Bona Sera Signorina", 44, 77);
  $f->close();

  $f = $m->open('tutu.txt');
  my $x = <$f>;
  print "\n******diamond scalar********\n$x\n";
  $f->close();

  $f = $m->open('tutu.txt');
  my $old = $m->input_record_separator(undef);
  $x = <$f>;
  print "\n******diamond scalar context and \$/ = undef********\n$x\n";
  $f->close();
  $old = $m->input_record_separator($old);

=head1 DESCRIPTION

C<GRID::Machine::IOHandle> object very much resembles C<IO::Handle> objects. The difference
being that the object refers to a remote C<IO::Handle> object.

=head1 METHODS

See L<perlfunc> for complete descriptions of each of the following
supported C<GRID::Machine::IOHandle> methods, which are just front ends for the
corresponding built-in functions:

    $io->close
    $io->getc
    $io->print ( ARGS )
    $io->printf ( FMT, [ARGS] )
    $io->stat

See L<perlvar> for complete descriptions of each of the following
supported C<GRID::Machine::IOHandle> methods.  All of them return the previous
value of the attribute and takes an optional single argument that when
given will set the value.  If no argument is given the previous value
is unchanged (except for $io->autoflush will actually turn ON
autoflush by default).

    $io->autoflush ( [BOOL] )                         $|

The following methods are not supported on a per-filehandle basis.

    GRID::Machine::IOHandle->format_line_break_characters( [STR] ) $:
    GRID::Machine::IOHandle->format_formfeed( [STR])               $^L
    GRID::Machine::IOHandle->output_field_separator( [STR] )       $,
    GRID::Machine::IOHandle->output_record_separator( [STR] )      $\

    GRID::Machine::IOHandle->input_record_separator( [STR] )       $/

Follows an example that uses methods C<open>, C<close>, C<print>, C<printf> and C<getc>:

  $ cat getc.pl
  #!/usr/local/bin/perl -w
  use strict;
  use GRID::Machine;

  my $machine = shift || 'remote.machine';
  my $m = GRID::Machine->new( host => $machine );

  my $f = $m->open('> tutu.txt');
  $f->print("Hola Mundo!\n");
  $f->print("Hello World!\n");
  $f->printf("%s %d %4d\n","Bona Sera Signorina", 44, 77);
  $f->close();

  $f = $m->open('tutu.txt');
  my $x;
  {
    $x = $f->getc();
    last unless defined($x);
    print $x;
    redo;
  }
  $f->close();

Furthermore, for doing normal I/O you might need these:


=over 4

=item $io->getline

This works like <$io> on the remote machine,
described in L<perlop/"I/O Operators">
except that it's more readable and can be safely called in a
list context but still returns just one line.  

=item $io->getlines

This works like <$io> when called in a list context to read all
the remaining lines in a file, except that it's more readable.
It will also croak() if accidentally called in a scalar context.

=item The diamond operatos

You can read from a remote file
using <$io>, but it only works on scalar context. See the L<SYNOPSIS>
example.


=item $io->flush

C<flush> causes perl to flush any buffered data at the perlio api level.
Any unread data in the buffer will be discarded, and any unwritten data
will be written to the underlying file descriptor. Returns "0 but true"
on success, C<undef> on error.

=item $io->blocking ( [ BOOL ] )

If called with an argument C<blocking> will turn on non-blocking IO if
C<BOOL> is false, and turn it off if C<BOOL> is true.

C<blocking> will return the value of the previous setting, or the
current setting if C<BOOL> is not given. 

If an error occurs C<blocking> will return undef and C<$!> will be set.

=back

=head1 SEE ALSO

L<perlfunc>, 
L<perlop/"I/O Operators">,
L<IO::File>

=head1 AUTHOR

Casiano Rodriguez Leon E<lt>casiano@ull.esE<gt>

=head1 ACKNOWLEDGMENTS

This work has been supported by CEE (FEDER) and the Spanish Ministry of
I<Educación y Ciencia> through I<Plan Nacional I+D+I> number TIN2005-08818-C04-04
(ULL::OPLINK project L<http://www.oplink.ull.es/>).
Support from Gobierno de Canarias was through GC02210601
(I<Grupos Consolidados>).
The University of La Laguna has also supported my work in many ways
and for many years.

Thanks also to Juana, Coro, my students at La Laguna and to the Perl Community.

=head1 LICENCE AND COPYRIGHT

Copyright (c) 2007 Casiano Rodriguez-Leon (casiano@ull.es). All rights reserved.

These modules are free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

=cut
