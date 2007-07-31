package GRID::Machine;
use strict;
use Data::Dumper;
#use POSIX;
use List::Util qw(first);
use Scalar::Util qw(blessed);
use Cwd;
use IO::File;
use File::Spec;

$| = 1;

sub send_error {
  my $server = shift;
  my $message = shift;

  $server->send_operation( 
    "DIED",
    GRID::Machine::Result->new( errmsg  => "$server->{host}: $message"),
  );
}

sub send_result {
  my $server = shift;
  my %arg = @_;

  $arg{stdout} =  '' unless defined($arg{stdout});
  $arg{stderr} =  '' unless defined($arg{stderr});
  $arg{errmsg} =  '' unless defined($arg{errmsg});
  $arg{results} =  [] unless defined($arg{errmsg});
  $server->send_operation( "RETURNED", GRID::Machine::Result->new( %arg ));
}

{ # closure for getter-setters

  # List of legal attributes
  my @legal = qw(
    log err 
    readfunc writefunc 
    cleanup sendstdout
    host command
    perl
    startdir startenv
    pushinc unshiftinc
    prefix
    Indent Deparse
    stored_procedures
  );
  my %legal = map { $_ => 1 } @legal;

  GRID::Machine::MakeAccessors::make_accessors(@legal);

  my $SERVER;

  sub SERVER {
    return $SERVER;
  }

  sub new {
    my $class = shift;
    my %args = @_;

    my $die = 0;
    my $a = "";
    $die  = "Illegal arg  $a\n" if $a = first { !exists $legal{$_} } keys(%args);


    # TRUE if remote stdout is sent back to local
    my $sendstdout = $args{sendstdout};

    # TRUE if temporary files will be deleted
    my $cleanup = $args{cleanup};
    $cleanup = 1 unless defined($cleanup);

    my $readfunc = sub {
       if( defined $_[1] ) {
          read( STDIN, $_[0], $_[1] );
       }
       else {
          $_[0] = <STDIN>;
          length $_[0];
       }
    };

    my $writefunc = sub {
       print STDOUT $_[0];
    };

    #my ($sysname, $nodename, $release, $version, $machine) = POSIX::uname();
    my $host = $args{host}; # ||  $nodename;

    my $startdir = $args{startdir};
    if ($startdir) {
      mkdir $startdir unless -x $startdir;
      chdir($startdir); # or create or die ...
    }

    # Set initial environment variables
    my %startenv = %{$args{startenv}};
    for (keys %startenv) {
      $ENV{$_} = $startenv{$_};
    }

    my $pushinc = $args{pushinc} || [];
    for (@$pushinc) {
      push @INC, $_;
    }

    my $unshiftinc = $args{unshiftinc} || [];
    for (@$unshiftinc) {
      unshift @INC, $_;
    }

    my $clientpid = $args{clientpid} || $$;

    # Create it if it does not exist? (the directories I mean)
    # What if it is absolute?
    my $log = "$ENV{HOME}/$args{log}" || "$ENV{HOME}/rperl$clientpid.log";
    open my $logfile, "> $log" or $die = 1;

    my $err = "$ENV{HOME}/$args{err}" || "$ENV{HOME}/rperl$clientpid.err";
    open my $errfile, "> $err" or $die = 1;

    my $prefix = $args{prefix} || "$ENV{HOME}/perl5lib";
    mkdir $prefix unless -r $prefix; 
    push @INC, $prefix;

    # die if $!

    my $handler = {

      Indent  => 2,
      Deparse => 1,

      sendstdout => $sendstdout,
      readfunc => $readfunc,
      writefunc => $writefunc,
      host  => $host,
      log      => $log,
      logfile  => $logfile,
      err      => $err,
      errfile  => $errfile,
      cleanup  => $cleanup,
      prefix   => $prefix,
      clientpid => $clientpid, 
      FILES     => [],

      stored_procedures => {},
    };

    $SERVER = bless $handler, $class;

    return $SERVER;
  }
} # end closure

sub QUIT {  
    my $server = shift;

    wait; # for filter
    $server->send_operation( "RETURNED");
    exit( 0 ) 
}

{
  local *SAVEOUT;
  local *SAVEERR;

  sub save_and_open_stdfiles {
    my $server = shift;

    my $log = $server->{log};
    my $err = $server->{err};
    open(SAVEOUT, ">&STDOUT") or return 0; # or die ...
    open(STDOUT,"> $log") or return 0;     # or die ..

    open(SAVEERR, ">&STDERR") or return 0; # or die ...
    open(STDERR,"> $err") or return 0;     # or die ..
    return 1;
  }

  sub read_and_reset_stdfiles {
    my $server = shift;

    open(STDOUT, ">&SAVEOUT");
    open(STDERR, ">&SAVEERR");

    my $sendstdout = $server->{sendstdout};

    my $log = $server->{log};
    my $err = $server->{err};
    my ($rstdout, $rstderr) = ("", "");
    if ($sendstdout) {
      local $/ = undef;
      my $file;
      open($file, $log) or return (); 
        $rstdout = <$file>;
      close($file);

      open($file, $err) or return (); 
        $rstderr = <$file>;
      close($file);
    }
    return ($rstdout, $rstderr);
  }

  sub redirect_and_eval {
    my $server = shift;
    my $subref = shift;

      $server->save_and_open_stdfiles 
    or return GRID::Machine::Result->new(errmsg => "Can't redirect stdout and stderr");

        my @results = eval { $subref->( @_ ) };

    my $err = $@;
    my @output = $server->read_and_reset_stdfiles;

      return GRID::Machine::Result->new(errmsg => "Can't recover stdout and stderr")
    unless @output;

    my ($rstdout, $rstderr) = @output;

    return GRID::Machine::Result->new(
      stdout => $rstdout, 
      errmsg  => $err, 
      stderr => $rstderr, 
      results => \@results
    );
  }
} # end of closure for SAVEOUT, SAVEERR

sub EVAL {
  my ($server, $code, $args) = @_;
  
  my $subref = eval "use strict; sub { $code }";

  if( $@ ) {           # Error while compiling code
     $server->send_error("Error while compiling eval. $@");
     return;
  }

  my $results = $server->redirect_and_eval($subref, @$args) ;

  if( $@ ) {
     $code =~ m{(.*)};
     $server->send_error( 
       "Error running eval code $1. $@"
     );
     return;
  }

  $server->send_operation( "RETURNED", $results );
  return;
}

sub STORE {
  my ($server, $name, $code) = splice @_,0,3;

  my %args = @_;
  my $politely = $args{politely} || 0; 
  delete($args{politely});

  my $subref = eval qq{ sub { use strict; $code } };
  if( $@ ) {
     $server->send_error("Error while compiling $name. $@");
     return;
  }

  if (($politely) && exists($server->{stored_procedures}{$name})) {
    $server->send_result( 
        errmsg  => "Warning! Attempt to overwrite sub '$name'. New version was not installed.",
        results => [ 0 ],
    );
  }
  else {
    # Store a Remote Subroutine Object
    $server->{stored_procedures}{$name} = GRID::Machine::RemoteSub->new(sub => $subref, %args);
    $server->send_result( 
        results => [ 1 ],
    );
  }
  return;
}

sub EXISTS {
  my $server = shift;
  my $name = shift;

  $server->send_operation("RETURNED", exists($server->{stored_procedures}{$name}));
}

sub CALL {
  my ($server, $name, $args) = @_;

  my $subref = $server->{stored_procedures}{$name}->{sub};
  if( !defined $subref ) {
     $server->send_error( "Error in RPC. No such stored procedure '$name'" );
     return;
  }

  if ( defined($args) && !UNIVERSAL::isa($args, 'ARRAY')) {
     $server->send_error( "Error in RPC. Args expected. Found instead: $args" );
     return;
  }

  my $results = redirect_and_eval($server, $subref, @$args );

  if( $@ ) {
     $server->send_error("Error running sub $name: $@");
     return;
  }

  my $filter = $server->{stored_procedures}{$name}->filter;
  $results = $results->$filter if $filter;
  $server->send_operation( "RETURNED", $results );
  return;
}

sub MODPUT {
  my $self = shift;
  
  my $pwd = getcwd();

  while (my ($name, $code) = splice @_,0,2) {

    my @a = split "::", $name;

    my $module = pop @a;
    my $dir = File::Spec->catfile($self->prefix, @a);

    if (defined($dir)) {
      mkdir($dir) unless -e $dir;
    
      chdir($dir) or $self->send_error("Error chdir $dir $@"), return; 
    }

    open my $f, "> $module.pm" or $self->send_error("Error can't create file $module.pm $@"), return; 
    print $f $code or $self->send_error("Error can't save file $module.pm $@"), return;
    close($f) or $self->send_error("Error can't close file $module.pm $@"), return;

    chdir($pwd);

  }
  $self->send_result( 
    #DEBUGGING stdout=> "pwd: ".getcwd()." dir: $dir, module: $module\n", 
    results => [1] 
  );
  return;
}

sub OPEN {
  my ($server, $descriptor) = splice @_,0,2;

  my $file = IO::File->new();
  unless (defined($descriptor) and $file->open($descriptor)) {
     $server->send_error("Error while opening $descriptor. $@");
     return;
  }

  my $files = $server->{FILES};
  push @{$files}, $file; # Watch memory usage

  $server->send_result( 
      results => [ $#$files ],
  );
  return;
}

sub DESTROY {
  my $self = shift;

  unlink $self->{log} if -w  $self->{log} and $self->{cleanup};
  unlink $self->{err} if -w  $self->{err} and $self->{cleanup};
}

#########  Remote main() #########
sub main() {
  my $server = shift;

  # Create filter process
  # Check $server is a GRID::Machine

  while( 1 ) {
     my ( $operation, @args ) = $server->read_operation( );

     if ($server->can($operation)) {
       $server->$operation(@args);
       next;
     }

     $server->send_error( "Unknown operation $operation\nARGS: @args\n" );
  }
}

package GRID::Machine::RemoteSub;

{
  my @legal = qw( sub filter );
  my %legal = map { $_ => 1 } @legal;

  GRID::Machine::MakeAccessors::make_accessors(@legal);

  sub new {
    my $class = shift;

    bless { @_ }, $class;
  }
}

1;
