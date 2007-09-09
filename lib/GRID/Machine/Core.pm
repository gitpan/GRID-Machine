use strict;
use warnings;

# Warning! There are some Perl functions that have some strange behavior:
# Example: mkdir fails when called via an array
#   DB<28> x @a
#   0  '/tmp/DIRECT'
#   1  18
#   DB<29> x mkdir(@a)
#   0  0
#  DB<31> !!ls -ltr /tmp/DIRECT
#  ls: /tmp/DIRECT: No existe el fichero o el directorio
#  (Command exited 1)
#     
# However a direct call succeeds:
#
#    DB<32> x mkdir('/tmp/DIRECT', 18)
#  0  1
#    DB<34> !!ls -ltrd /tmp/DIRECT
#  d---------  2 pp2 pp2 4096 2007-06-18 12:16 /tmp/DIRECT
# This does not seem to be my fault or GRID::Machine fault :-)

sub getcwd { return getcwd() }

sub chdir  { 
 my $dir = shift || $ENV{HOME};
 return chdir($dir) 
}

sub umask  { 
 my $umask = shift;
 return umask($umask) if defined($umask);
 return umask();
}

sub mkdir  { 
 my $dir = shift or die "mkdir needs an argument\n";
 my $mask = shift;
 return mkdir($dir) unless defined($mask);
 return mkdir($dir, $mask);
}

sub system {
  my $program = shift;

  CORE::system($program, @_);
  return $?
}

sub glob {
  my $spec = shift;

  return glob($spec);
}

sub tar {
  my $file = shift;
  my $options = shift;

  CORE::system('tar', $options, ,'-f', $file);
  return $?
}

sub uname {
  return POSIX::uname();
}

sub version {
  my $module = shift;
  my $out = `$^X -M$module -e 'print $module->VERSION'`;
}

sub installed {
  my $module = shift;

  !CORE::system("$^X -M$module -e 0");
}

LOCAL {
  for (qw(r w e x z s f d  t T B M A C)) {
    SERVER->sub( "_$_" => qq{
        my \$file = shift;

        return -$_ \$file;
      }
    );
  }
}

__END__

