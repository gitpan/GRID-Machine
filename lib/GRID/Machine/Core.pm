use strict;
use warnings;

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

sub qqx {
  my $wantarray = shift,
  my $sep = shift;
  my $program = shift;

  local $/ = $sep;
  return `$program` if $wantarray;
  scalar(`$program`);
}

sub _fork {
  my $childcode = shift;

  my $pid = fork;
  die "Can't fork\n" unless defined($pid);
  return $pid if ($pid);

  # child

  my $subref = eval "use strict; sub { $childcode }";
  $subref->(@_);
  exit(0);
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

