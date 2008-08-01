package GRID::Machine;
use strict;
use Data::Dumper;
use List::Util qw(first);
use Scalar::Util qw(blessed reftype);
use Cwd qw{getcwd abs_path};
use IO::File;
use File::Spec;
use File::Path;

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
  $arg{results} =  [] unless defined($arg{results});
  $server->send_operation( "RETURNED", GRID::Machine::Result->new( %arg ));
}

{ # closure for getter-setters

  # List of legal attributes
  my @legal = qw(
    cleanfiles
    cleandirs
    cleanup 
    clientpid
    command
    debug
    Deparse
    err 
    errfile 
    host 
    Indent 
    log 
    logfile 
    perl
    prefix
    pushinc 
    readfunc 
    sendstdout
    startdir 
    startenv
    stored_procedures
    unshiftinc
    writefunc 
  );
  my %legal = map { $_ => 1 } @legal;

  GRID::Machine::MakeAccessors::make_accessors(@legal);

  my $SERVER;

  sub SERVER {
    return $SERVER;
  }

  sub setloganderr {
    my ($log, $args, $file) = @_;

    $args->{$log} = "rperl$args->{clientpid}_$$.$log" unless $args->{$log};
    my $logname = "$ENV{HOME}/$args->{$log}";
    my $logfile = IO::File->new("> $logname");
    unless ($logfile) {
        $SERVER->send_error("Can't open $logname for writing. $@");
        return $SERVER
    }
    
    $logfile->autoflush(1);

    $SERVER->{$log} = $logname;
    $SERVER->{$log."file"} = $logfile;

  }

  sub new {
    my $class = shift;
    my %args = @_;

    # Dummy variable $legal. Just to make the perl compiler conscious of the closure ...
    my $legal = \%legal; 
    my $die = 0;
    my $a = first { !exists $legal{$_} } keys(%args);
    die("Error in remote new: Illegal arg  $a. Legal args: @legal\n") if $a;


    # TRUE if remote stdout is sent back to local
    my $sendstdout = $args{sendstdout};

    # TRUE if temporary files will be deleted
    my $cleanup = $args{cleanup};
    $cleanup = 1 unless defined($cleanup);

    my $host = $args{host} || $ENV{HOSTNAME}; 
    unless ($host) {
      eval q{
        require Sys::Hostname;
      };
      $host = $@? 'unknown' : Sys::Hostname::hostname();
    }

    my $startdir = $args{startdir};
    if ($startdir) {
      mkdir $startdir unless -x $startdir;
      chdir($startdir) or die "$host: can't change to dir $startdir\n"; 
    }

    # Set initial environment variables
    # No need to check is a HASH ref since it was already checked in the local side
    # (See GRID/Machine.pm)
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

    my $prefix = $args{prefix} || "$ENV{HOME}/perl5lib";
    unless (-r $prefix) { 
      mkdir $prefix unless -r $prefix; 
      die "$host: can't create directory $prefix\n" unless (-d $prefix) && (-r $prefix);
    }
    push @INC, $prefix;

    # create copy of STDOUT to use as command output (-dk-)
    open(my $CMDIN, "<&STDIN") or die "$host: Can't create copy of STDIN\n";

    my $readfunc = sub {
       if( defined $_[1] ) {
          read( STDIN, $_[0], $_[1] );
       }
       else {
          $_[0] = <STDIN>;
          die "Premature EOF received" unless defined($_[0]);
          length $_[0];
       }
    };

    # create copy of STDOUT to use as command output (-dk-)
    open(my $CMDOUT, ">&STDOUT") or die "$host: Can't create copy of STDOUT\n";
    $CMDOUT->autoflush(1);

    my $writefunc = sub {
       syswrite $CMDOUT, $_[0];
    };

    my $debug = $args{debug} || 0;

    my $handler = {
      sendstdout => $sendstdout,
      readfunc => $readfunc,
      writefunc => $writefunc,
      host  => $host,
      cleanup  => $cleanup,
      prefix   => $prefix,
      clientpid => $clientpid, 

      # Used to store remote files (see GRID::Machine::RIOHandle)
      FILES     => [],

      # List of absolute names of temporary files
      cleanfiles => [],
      # List of absolute names of temporary directories
      cleandirs => [],

      # Used to store remote subroutines. A remote sub is a GRID::Machine::RemoteSub object
      stored_procedures => {},
      debug => $debug,
    };

    $SERVER = bless $handler, $class;

    # Create it if it does not exist? (the directories I mean)
    # What if it is absolute?

    setloganderr('log', \%args, 'stdout');
    # redirect STDOUT - once per remote session! (-dk-)
    open(STDOUT,"> $SERVER->{log}") or do {
        $SERVER->send_error("Can't redirect STDOUT. $@");
        return $SERVER
    };

    setloganderr('err', \%args, 'stderr');

    return $SERVER;
  }
} # end closure

# Methods in uppercase are PROTOCOL methods
sub QUIT {  
    my $server = shift;

    $server->DESTROY;
    $server->send_operation( "RETURNED");

    # It is not being called upon termination!
    exit( 0 ) 
}

sub read_stdfiles {
  my $server = shift;

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

sub eval_and_read_stdfiles {
  my $server = shift;
  my $subref = shift;

      my @results = eval { $subref->( @_ ) };

  my $err = $@;
  my @output = $server->read_stdfiles;

    # handling 'GRID::Machine::QUIT' when waiting for 'RESULT' from callback (-dk-)
    if ($err =~ /^EXIT/) { undef $@; exit 0 }

    return GRID::Machine::Result->new(
      errmsg => "Can't recover stdout and stderr",
      results => \@results,
    )
  unless @output;

  my ($rstdout, $rstderr) = @output;

  return GRID::Machine::Result->new(
    stdout => $rstdout, 
    errmsg  => $err, 
    stderr => $rstderr, 
    results => \@results
  );
}

sub EVAL {
  my ($server, $code, $args) = @_;

  my $subref = eval "use strict; sub { $code }";

  if( $@ ) {           # Error while compiling code
     $server->send_error("Error while compiling eval. $@");
     return;
  }

  if ( defined($args) && (reftype($args) ne 'ARRAY')) {
     $server->send_error( "Error in eval. Args expected. Found instead: $args" );
     return;
  }

  # -dk- look for anonymous callback(s)
  my $results = eval_and_read_stdfiles(
      $server, 
      $subref, 
      map( UNIVERSAL::isa($_, 'GRID::Machine::_RemoteStub') ?  make_callback($server, $_->{id}) : $_, @$args ) 
  );

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

  my $subref = eval qq{ sub { use strict;0; #$name\n$code } };
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
  #$DB::single = 1 if $server->{debug}; # warn!
  return;
}

# -dk-
sub make_callback {
   my ($server, $name) = splice @_,0,2;

   return sub {
      $server->send_operation('CALLBACK', $name, @_);

      while (1) {
         my ($op, @args) = $server->read_operation();

         # what we actually expected - 'RESULT'
         if ($op eq 'RESULT') {
           return wantarray ? @args : $args[0];
         }

         # special case - 'QUIT'
         if ($op eq 'GRID::Machine::QUIT') {
            $server->send_operation("RETURNED");
            # we're inside eval so have to pass 'exit' up
            die "EXIT"
         }

         if ($server->can($op)) {
            $server->$op(@args);
            next
         }

         die "RESULT expected, '$op' received...\n"
      }
   }
}

# -dk-
sub CALLBACK {
   my ($server, $name) = splice @_,0,2;

   # Don't overwrite existing methods
   my $class = ref($server);
   if ($class->can($name)) {
      $server->send_error("Machine $server->{host} already has a method $name");
      return;
   };

   my $callback = make_callback($server, $name);
   {
     no strict 'refs';
     *{$class."::$name"} = $callback;
   }

   $server->send_result( results => [ 0+$callback ] );
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

  # -dk- look for anonymous callback(s)
  my $results = eval_and_read_stdfiles($server, $subref, map(
      UNIVERSAL::isa($_, 'GRID::Machine::_RemoteStub') ? make_callback($server, $_->{id}) : $_,
  @$args ) );

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
      # Bug fixed by Alex White. Thanks Alex!
      mkpath($dir) unless -e $dir;
    
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

# Sends a message for inmediate print to the local machine
# Goes in reverse: The remote makes the request the local 
# serves the request
sub gprint {
   SERVER->send_operation('GRID::Machine::GPRINT', @_);
   return 1;
}


# Sends a message for inmediate printf to the local machine
# Goes in reverse: The remote makes the request, the local 
# serves the request
sub gprintf {
   SERVER->send_operation('GRID::Machine::GPRINTF', @_);
   return 1;
}

sub OPEN {
  my ($server, $descriptor) = splice @_,0,2;

  my $file = IO::File->new();

  # Check if is an ouput pipe, i.e. s.t. like:  my $f = $m->open('| sort -n'); 
  # In such case, redirect STDOUT to null
  if ($descriptor =~ m{^\s*\|(.*)}) {
    my $command = $1;
    my $nulldevice = File::Spec->devnull;
    $descriptor = "| ($command) > $nulldevice";
  }
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

  my $cleanfiles = $self->cleanfiles;
  if (reftype($cleanfiles) eq 'ARRAY') {
    while (@{$cleanfiles}) { 
      $_ = shift @{$cleanfiles};
      unlink $_;
    }
  }

  my $cleandirs = $self->cleandirs;
  if (reftype($cleandirs) eq 'ARRAY') {
    while (@{$cleandirs}) { 
      $_ = shift @{$cleandirs};
      rmtree $_;
    }
  }
}

#########  Remote main() #########
sub main() {
  my $server = shift;

  # Create filter process
  # Check $server is a GRID::Machine

  {
  package main;
  while( 1 ) {
     my ( $operation, @args ) = $server->read_operation( );

     if ($server->can($operation)) {
       $server->$operation(@args);

       # Outermost CALL Should Reset Redirects (-dk-)
       next unless ($operation eq 'GRID::Machine::CALL' || $operation eq 'GRID::Machine::EVAL');
       if ($server->{log}) {
         close STDOUT;
         $server->{log} and open(STDOUT,"> $server->{log}") or do {
           $server->send_error("Can't redirect stdout. $@");
           last
         }
       }
       if ($server->{err}) {
         close STDERR;
         $server->{err} and open(STDERR,"> $server->{err}") or do {
           $server->send_error("Can't redirect stderr. $@");
           last
         }
       }

       next;
     }

     $server->send_error( "Unknown operation $operation\nARGS: @args\n" );
  }
  } # package
}

# GRID::Machine::DEBUG_LOAD_FINISHED 
# signals that the initial bootstraping has finished
sub DEBUG_LOAD_FINISHED {
  my $self = shift;

  $DB::single = 1 if $self->{debug};
}


1;

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

