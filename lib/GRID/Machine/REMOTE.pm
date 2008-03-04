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
  $arg{results} =  [] unless defined($arg{results});
  $server->send_operation( "RETURNED", GRID::Machine::Result->new( %arg ));
}

{ # closure for getter-setters

  # List of legal attributes
  my @legal = qw(
    cleanup 
    clientpid
    command
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

    # create copy of STDOUT to use as command output (-dk-)
    open(my $CMDOUT, ">&STDOUT") or die;
    $CMDOUT->autoflush(1);

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
       print $CMDOUT $_[0];
    };

    my $prefix = $args{prefix} || "$ENV{HOME}/perl5lib";
    mkdir $prefix unless -r $prefix; 
    push @INC, $prefix;

    # die if $!

    my $handler = {

      #Indent  => 2,
      #Deparse => 1,

      sendstdout => $sendstdout,
      readfunc => $readfunc,
      writefunc => $writefunc,
      host  => $host,
      cleanup  => $cleanup,
      prefix   => $prefix,
      clientpid => $clientpid, 
      FILES     => [],

      stored_procedures => {},
    };

    $SERVER = bless $handler, $class;

    # Create it if it does not exist? (the directories I mean)
    # What if it is absolute?

    $args{log} = "rperl$clientpid.log" unless $args{log};
    my $log = "$ENV{HOME}/$args{log}";
    open my $logfile, "> $log" or do {
        $SERVER->send_error("Can't open $log for writing. $@");
        return $SERVER
    };
    $SERVER->{log} = $log;
    $SERVER->{logfile} = $logfile;

    # redirect STDOUT - once per remote session! (-dk-)
    open(STDOUT,"> $SERVER->{log}") or do {
        $SERVER->send_error("Can't redirect stdout. $@");
        return $SERVER
    };

    $args{err} = "rperl$clientpid.err" unless $args{err};
    my $err = "$ENV{HOME}/$args{err}";
    open my $errfile, "> $err" or do {
        $SERVER->send_error("Can't open $err for writing. $@");
        return $SERVER
    };
    $SERVER->{err} = $err;
    $SERVER->{errfile} = $errfile;

    # redirect STDERR - once per remote session! (-dk-)
    open(STDERR,"> $SERVER->{err}") or do {
        $SERVER->send_error("Can't redirect stderr. $@");
        return $SERVER
    };

    return $SERVER;
  }
} # end closure

sub QUIT {  
    my $server = shift;

    $server->send_operation( "RETURNED");
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

#sub EVAL {
#  my ($server, $code, $args) = @_;
#  
#  my $subref = eval "use strict; sub { $code }";
#
#  if( $@ ) {           # Error while compiling code
#     $server->send_error("Error while compiling eval. $@");
#     return;
#  }
#
#  my $results = $server->eval_and_read_stdfiles($subref, @$args) ;
#
#  if( $@ ) {
#     $code =~ m{(.*)};
#     $server->send_error( 
#       "Error running eval code $1. $@"
#     );
#     return;
#  }
#
#  $server->send_operation( "RETURNED", $results );
#  return;
#}

sub EVAL {
  my ($server, $code, $args) = @_;

  my $subref = eval "use strict; sub { $code }";

  if( $@ ) {           # Error while compiling code
     $server->send_error("Error while compiling eval. $@");
     return;
  }

  if ( defined($args) && !UNIVERSAL::isa($args, 'ARRAY')) {
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
