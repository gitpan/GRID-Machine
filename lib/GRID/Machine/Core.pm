use strict;
use warnings;
use File::Temp;

sub getcwd { return getcwd() }

sub chdir  { 
 my $dir = shift || $ENV{HOME};
 return chdir($dir) 
}

sub unlink  { 
 my @files = @_;

 return unless @files;
 return unlink(@files) 
}

sub mark_as_clean {
  my %arg = @_;
  my $files = $arg{files} || [];
  my $dirs  = $arg{dirs} || [];

  if (@$files) {
    # make them absolute paths
    my @absfiles = map { abs_path($_) } @$files;
    push @{SERVER()->cleanfiles}, @absfiles;
  }
  if (@$dirs) {
    my @absdirs = map { abs_path($_) } @$dirs;
    push @{SERVER()->cleandirs}, @absdirs;
  }
}

sub wrapexec {
  my $exec = shift;

  my $dir = getcwd;

  $exec =~ /^(\S+)/;
  my $execname = $1;
  # Executable can be in any place of the PATH search 
  #die "Error. Can't find executable name\n" unless  $execname && -x $execname;

  my ($name) = $execname =~ m{([\w.]+)$};
  $name ||= '';

  my $ENV = "'".(join "',\n  '", %ENV)."'";

  my $filename = "gridmachine_driver_${name}";
  my $tmp = File::Temp->new( TEMPLATE => $filename.'XXXXX', DIR => '/tmp', UNLINK => 0);
  my $scriptname = $tmp->filename;

  print $tmp <<"EOF";
chdir "$dir" || die "Can't change to dir $dir\\n";
\%ENV = ($ENV);
\$| = 1;
exec("$exec") or die "Can't execute $exec\\n";
EOF

   push @{SERVER->cleanfiles}, $scriptname;
   close($tmp);
   return $scriptname;
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

