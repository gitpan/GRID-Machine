package GRID::Machine::Request;
use List::Util qw(first);

my @legal = qw(type name code args);

# Meaning of attributes:
# type: 
#   type of operation: EVAL, QUIT, STORE, CALL
# name: 
#   string containing the name of the subroutine if CALL or STORE
# code:
#   string containing the code if  STORE or EVAL
# args:
#   dumped arguments of the call if  CALL or EVAL

my %legal = map { $_ => 1 } @legal;

sub new {
  my $class = shift || die "Error: Provide a class\n";
  my %args = @_;

  my $a = "";
  die "Illegal arg  $a\n" if $a = first { !exists $legal{$_} } keys(%args);

  bless \%args, $class;
}

sub Args {
  my $self = shift;

  return @{$self->{args}};
}

GRID::Machine::MakeAccessors::make_accessors(@legal);

1;
