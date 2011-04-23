use strict;
use warnings;
use File::Temp;
use File::Spec;

sub getcwd { return getcwd() }

sub getpid #gm ( filter => 'result')
{
  $$;
}

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
  my $program =<< 'EOPROG'; 
chdir "<<$dir>>" || die "Can't change to dir <<$dir>>\n";
%ENV = (<<$ENV>>);
$| = 1;
my $success = !system("<<$exec>>");
warn "GRID::Machine::Core::wrapexec warning!. Execution of '<<$exec>>' returned Status: '$?'. Success value from system call: '$success'\n" unless $success;
unlink('<<$scriptname>>');
exit(0);
EOPROG

  $exec =~ /^\s*(\S+)/; # mmm.. no options?
  my $execname = $1;
  # Executable can be in any place of the PATH search 
  my $where = `which $execname 2>&1`;

  # skip if program 'which' can't be found otherwise check that $execname exists
  unless ($?) {
    die "Error. Can't find executable for command '$execname'. Where: '$where'\n" unless  $execname && $where =~ /\S/;
  }

  # name without path
  my ($name) = $execname =~ m{([\w.]+)$};
  $name ||= '';

  my $ENV = "'".(join "',\n  '", %ENV)."'";

  # Create a temp perl script with pattern /tmp/gridmachine_driver_${name}XXXXX
  my $filename = "gridmachine_driver_${name}";
  my $tmp = File::Temp->new( TEMPLATE => $filename.'XXXXX', DIR => File::Spec->tmpdir(), UNLINK => 0);
  my $scriptname = $tmp->filename;

  $program =~ s/<<\$dir>>/$dir/g;
  $program =~ s/<<\$ENV>>/$ENV/g;
  $program =~ s/<<\$exec>>/$exec/g;
  $program =~ s/<<\$scriptname>>/$scriptname/g;

  print $tmp $program;

  #push @{SERVER->cleanfiles}, $scriptname; # unless shift();
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

  my $r = CORE::system($program, @_);
  SERVER->remotelog("system '$program @_' executed \$?= $?, \$\@ = '$@', ! = '$!'");
  $r;
  #return $?
}

sub qqx {
  my $wantarray = shift,
  my $sep = shift;
  my $program = shift;

  local $/ = $sep;
  return `$program` if $wantarray;
  scalar(`$program`);
}

sub fork 
#gm (filter => 'result', 
#gm  around => sub { my $self = shift; my $r = $self->call( 'fork', @_ ); $r->{machine} = $self; $r }
#gm ) 
{
  my $childcode = shift;
  my %args = (stdin => '/dev/null', stdout => '', stderr => '', result => '', args => [], @_);

  my ($stdin, $stdout, $stderr, $result) = @args{'stdin', 'stdout', 'stderr', 'result'};

  $| = 1;

  use File::Temp qw{tempfile};

  unless ($stdout) {
    my $stdoutfile;
    ($stdoutfile, $stdout) = tempfile(SERVER()->{tmpdir}.'/GMFORKXXXXXX', UNLINK => 0, SUFFIX =>'.out');
    close($stdoutfile);
  }

  unless ($stderr) {
    my $stderrfile;
    ($stderrfile, $stderr) = tempfile(SERVER()->{tmpdir}.'/GMFORKXXXXXX', UNLINK => 0, SUFFIX =>'.err');
    close($stderrfile);
  }

  unless ($result) {
    my $resultfile;
    ($resultfile, $result) = tempfile(SERVER()->{tmpdir}.'/GMFORKXXXXXX', UNLINK => 0, SUFFIX =>'.result');
    close($resultfile);
  }

  my $pid = fork;
  unless (defined($pid)) {
    SERVER->remotelog("Process $$: Can't fork '".substr($childcode,0,10)."'\n$@ $!"); 
    return undef;
  }

  if ($pid) { # father
    #gprint("Created child $pid\n");
    return bless { 
             pid    => $pid, 
             stdin  => $stdin, 
             stdout => $stdout, 
             stderr => $stderr, 
             result => $result 
           }, 'GRID::Machine::Process';
  }

  # child

  my $subref = eval <<"EOSUB";
use strict; 
sub { 
    use POSIX qw{setsid};
    setsid(); 
    open(STDIN, "< $stdin");
    open(STDOUT,"> $stdout");
    open(STDERR,"> $stderr");

  $childcode 
};
EOSUB
  SERVER->remotelog("Found errors while forking in code '".substr($childcode,0,10)."'\n$@\n") if $@;

    # admit a single argument of any kind
    my $ar =  $args{args};
    $ar = [ $ar ] unless reftype($ar) and (reftype($ar) eq 'ARRAY');

    my @r = $subref->(@$ar);

    close(STDERR);
    close(STDOUT);

    use Data::Dumper;
    local $Data::Dumper::Indent = 0;
    local $Data::Dumper::Deparse = 1;
    local $Data::Dumper::Purity = 1;
    local $Data::Dumper::Terse = 0;

    open(my $resfile, ">", $result);
    print $resfile Dumper([\@r, \$@]);
    close($resfile);

  exit(0);
}

sub waitpid #gm (filter => 'result')
{
  my $process = shift;

  $process = $process->result if ($process->isa('GRID::Machine::Result'));

  SERVER->remotelog(Dumper($process));
  #gprint("Synchronizing with $process->{pid} args = <@_>\n");

  my ($status, $deceased);;
  do {
    $deceased = waitpid($process->{pid}, @_ ? @_ : 0);
    $status = $?;

    #gprint("Synchronized: Pid of the deceased process: $deceased\n");
    #gprint("there are processes still running\n") if (!$deceased);

    #SERVER->remotelog("deceased = $deceased");

    #if (kill 0, -$process->{pid}) { gprint("Not answer to 0 signal from process $process->{pid}\n") }
    #else { gprint("Strange: the process $process->{pid} is still alive\n"); }

  } while (kill 0, -$process->{pid});

  # if deceased is 0
  # TODO: study flock, may be this way we can synchronize!!
  local $/ = undef;
  open my $fo, $process->{stdout}; # check exists, die, etc.
    my $stdout = <$fo>;
  close($fo);
  CORE::unlink $process->{stdout};

  #gprint("stderr file is: $process->{stderr}\n");
  open my $fe, $process->{stderr}; # or do { SERVER->remotelog("can't open file <$process->{stderr}> $@") }; # check exists, die, etc.
    my $stderr = <$fe>;
  #gprint("stderr is: $stderr\n");
  close($fe);
  CORE::unlink $process->{stderr};

  open my $fr, $process->{result} or do { SERVER->remotelog("can't open file <$process->{stderr}> $@") }; # check exists, die, etc.
    #sleep 1;
    my $result = <$fr>;
    #gprint("result as read from file $process->{result} is  <$result>\n");;
  close($fr);
  CORE::unlink $process->{result};

  $result .= '$VAR1';
  my $val  = eval "no strict; $result";
  #SERVER->remotelog("Errors: '$@'. Result from the asynchronous call: '@$val'");
  
  return bless {
    stdout  => $stdout, 
    stderr  => $stderr, 
    results => $val->[0], 
    status  => $status,    # as in $?
    waitpid => $deceased,  # returned by waitpid
    descriptor => SERVER()->host().':'.$$.':'.$process->{pid},
    machineID  => SERVER()->logic_id,
    errmsg  => ${$val->[1]},  # as $@
  }, 'GRID::Machine::Process::Result';
}

sub kill { #gm (filter => 'result')
  my $signal = shift;

  CORE::kill $signal, @_;
}

sub poll { #gm (filter => 'result')
  CORE::kill 0, @_;
}


sub slurp {
  my $filename = shift;

  local $/ = undef;

  open(my $f, "<", $filename) or die "Can't find file '$filename'\n";

  return scalar(<$f>);
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
  use POSIX;
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

sub _stat {
  my $filehandle = shift;
 
  return stat($filehandle) if defined($filehandle);
  return stat();
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

