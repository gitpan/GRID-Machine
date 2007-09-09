package GRID::Machine::MakeAccessors;
use strict;
use warnings;

=head1 NAME 

GRID::Machine::MakeAccessors - Home Made "Make accessors" for a Class

=head1 METHODS

=head2 sub make_accessors

   make_accessors($package, @legalattributes)

Builds getter-setters for each attribute

=cut

sub make_accessors { # Install getter-setters 
  my $package = caller;

  no strict 'refs';
  for my $sub (@_) {
    *{$package."::$sub"} = sub {
      my $self = shift;

      $self->{$sub} = shift() if @_;
      return $self->{$sub};
    };
  }
}

1;
