#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  Based on the idea of IPC::PerlSSH by Paul Evans, 2006,2007 -- leonerd@leonerd.org.uk
#  (C) Casiano Rodriguez-Leon 2007 -- casiano@ull.es

package GRID::Machine;
use strict;
use Scalar::Util qw(blessed reftype);
use List::Util qw(first);
use Module::Which;
use IPC::Open2;
use Carp;
use File::Spec;
use IO::File;
use base qw(Exporter);
use GRID::Machine::IOHandle;
require Cwd;
no Cwd;
our @EXPORT_OK = qw(is_operative read_modules qc slurp_file);

# We need to include the common shared perl library
use GRID::Machine::MakeAccessors; # Order is important. This must be the first!
use GRID::Machine::Message;
use GRID::Machine::Result;

our $VERSION = "0.096";

####################################################################
# Usage      : my $REMOTE_LIBRARY = read_modules(@Remote_modules);
# Purpose    : Concatenates the contents of the files associated with
#              the file descriptors
# Returns    : The string with the cotnents of all those files
# Throws     : exception if a module can not be found

sub read_modules {

  my $m = "";
  for my $descriptor (@_) {
    my %modules = %{which($descriptor)};

    for my $module (keys(%modules)) {
      my $path = which($module)->{$module}{path}; 

      unless (defined($path) and -r $path) {
        die "Can't find module $module\n";
      }

      $m .= "#line 1 \"$path\"\n";
      local $/ = undef;
      open my $FILE, "< $path";
        $m .= <$FILE>;
      close($FILE);
    }
  }

  return $m;
}

#  ssh [-1246AaCfgKkMNnqsTtVvXxY] [-b bind_address] [-c cipher_spec] 
#                         [-D  [bind_address:]port] [-e escape_char]
#           [-F configfile] [-i identity_file] [-L  [bind_address:]port:host:hostport] 
#           [-l login_name] [-m mac_spec]
#           [-O ctl_cmd] [-o option] [-p port] [-R  [bind_address:]port:host:hostport] i
#           [-S ctl_path] [-w tunnel:tunnel]
#           [user@]hostname [command]
#
sub find_host {
  my $command = shift;

  my %option;

  die "Error in GRID::Machine findhost. No command provided\n" unless $command;
  $command =~ s{^(\S+)\s*}{};
  $option{ssh} = $1;
  while ($command =~ s{^\s*(-\w)\s+(\S*)}{}g) {
    $option{$1} = $2;
  }
  $command =~ s{^\s*([\w+.\@]+)}{};
  $option{host} = $1;
  return \%option;
}

# Inheritance: not considered
{ # closure for attributes

  my @legal = qw(
    cleanup 
    command
    debug
    err 
    host 
    includes
    log 
    perl
    perloptions
    prefix 
    pushinc unshiftinc
    readfunc 
    remotelibs
    scp 
    sendstdout
    ssh 
    sshoptions 
    startdir startenv 
    uses
    wait 
    writefunc 
  );
  my %legal = map { $_ => 1 } @legal;

  GRID::Machine::MakeAccessors::make_accessors(@legal);

  sub RemoteProgram {
    my ($USES,
        $REMOTE_LIBRARY,
        $class, 
        $host, 
        $log, 
        $err, 
        $startdir, 
        $startenv, 
        $pushinc, 
        $unshiftinc, 
        $sendstdout, 
        $cleanup, 
        $prefix,
        $portdebug,
       ) 
    = @_;

   return << "EOREMOTE";
#line 1 "$host"
package GRID::Machine;
use strict;
use warnings;

$USES

$REMOTE_LIBRARY

my \$rperl = $class->new(
  host => '$host',
  log  => '$log',
  err  => '$err',
  clientpid => $$,
  startdir => '$startdir',
  startenv => { qw{ @$startenv } },
  pushinc => [ qw{ @$pushinc } ], 
  unshiftinc => [ qw{ @$unshiftinc } ],
  sendstdout => $sendstdout,
  cleanup => $cleanup,
  prefix  => '$prefix', # Where to install modules
  debug => $portdebug,
);
\$rperl->main();
__END__
EOREMOTE
  } # end of sub RemoteProgram 

  sub new {
     my $class = shift;
     my %opts = @_;

     my $a = "";
     die __PACKAGE__."::new: Illegal arg <$a>\n" if $a = first { !exists $legal{$_} } keys(%opts);


     my $portdebug = $opts{debug} || 0;
     my $sendstdout = 1;
     $sendstdout = $opts{sendstdout} if exists($opts{sendstdout});
     ###########################################################################
     # We have a "shared library" of common functions between this end and the
     # remote end
     
     # The user can specify some libs that will be loaded at boot time
     my $remotelibs = $opts{remotelibs} || [];

     my @Remote_modules = qw(
       GRID::Machine::MakeAccessors
       GRID::Machine::Message 
       GRID::Machine::Result
       GRID::Machine::REMOTE
     );

     push @Remote_modules, $_ for @$remotelibs;

     my $REMOTE_LIBRARY = read_modules(@Remote_modules);

     my $host = "";
     my ( $readfunc, $writefunc ) = ( $opts{readfunc}, $opts{writefunc} );

     my $log = $opts{log} || '';
     my $err = $opts{err} || '';
     my $wait = $opts{wait} || 15;
     my $cleanup = $opts{cleanup};
     my $ssh = $opts{ssh} || 'ssh';
     my $sshoptions = $opts{sshoptions} || '';
     my $perloptions = $opts{perloptions} || '';
     my $scp = $opts{scp} || 'scp -q -p';
     my $prefix = $opts{prefix} || 'perl5lib/';

     $cleanup = 1 unless defined($cleanup);

     my $pid; 

     my $port = 22;
     my $identity = '';
     my $user = '';
     my $options;

     if( !defined $readfunc || !defined $writefunc ) {
        my @command;
        if( exists $opts{command} ) {
           my $c = $opts{command};
           my $options = find_host($c); # $ENV{HOSTNAME} || "REMOTE";
           $host = $options->{host};
           $port = $options->{-p};
           $identity = $options->{-i};
           $user = $options->{-l};
           $scp .= " -i $identity" if $identity;
           $scp .= " -P $port" if $port;
           $host = $user.'@'.$host if $user && $host !~ /\@/;
           @command = (reftype($c) && (reftype($c) eq "ARRAY")) ? @$c : ( "$c" );
        }
        else {
           $host = $opts{host} or
              die __PACKAGE__."->new() requires a host, a command or a Readfunc/Writefunc pair";


           my @sshoptions;
           if ($host =~ s/:(\d+$)//) {
              $port = $1;
              @sshoptions = ('-p', $port);
           }
           if (reftype($sshoptions) && (reftype($sshoptions) eq 'ARRAY')) {
             push @sshoptions, @$sshoptions;
           }
           elsif ($sshoptions) {
             push @sshoptions, split /\s+/, $sshoptions;
           }

             die "Can't execute perl in $host using ssh connection with automatic authentication\n"
           unless is_operative("$ssh @sshoptions", $host, "perl -v", $wait);

           my %sshoptions = @sshoptions;

           $scp .= " -P $sshoptions{'-p'}" if $sshoptions{-p};
           $scp .= " -i $sshoptions{'-i'}" if $sshoptions{-i};
           $host = $sshoptions{'-l'}.'@'.$host if $sshoptions{'-l'} && $host !~ /\@/;

           my @perloptions;

           if (reftype($perloptions) && (reftype($perloptions) eq 'ARRAY')) {
             push @perloptions, @$perloptions;
           }
           elsif ($perloptions) {
             push @perloptions, split /\s+/, $perloptions;
           }

           if ($portdebug && $portdebug =~ /^\d+$/) {
             my $perl = qq{PERLDB_OPTS="RemotePort=$host:$portdebug" }.($opts{perl} || 'perl -d');
             @command = ( "$ssh @sshoptions $host $perl @perloptions" );
             print "Debugging with '@command'\n".
                   "Remember to run 'netcat -v -l -p $portdebug' in $host\n\n";
           }
           else {
             @command = ( $ssh, @sshoptions, $host, $opts{perl} || "perl", @perloptions );
           }
        }
        
        my ( $readpipe, $writepipe );
        $pid = open2( $readpipe, $writepipe, @command );

        $readfunc = sub {
           if( defined $_[1] ) {
              read( $readpipe, $_[0], $_[1] );
           }
           else {
              $_[0] = <$readpipe>;
              die "Premature EOF received" unless defined($_[0]);
              length( $_[0] );
           }
        };

        $writefunc = sub {
           syswrite $writepipe, $_[0];
        };
     }

     my $startdir = $opts{startdir} || '';

     my $startenv = $opts{startenv} || [];

     my $pushinc = $opts{pushinc} || [];
     die "Arg 'pushinc' of new must be an ARRAY ref\n" unless reftype($pushinc) eq 'ARRAY';

     my $unshiftinc = $opts{unshiftinc} || [];
     die "Arg 'unshiftinc' of new must be an ARRAY ref\n" unless reftype($unshiftinc) eq 'ARRAY';

     my $uses = $opts{uses} || [];
     die "Arg 'uses' of new must be an ARRAY ref\n" unless reftype($uses) eq 'ARRAY';
     my $USES = '';
     $USES .= "use $_;\n" for @$uses;

     # Now stream it the "firmware"
     my $remoteprogram = RemoteProgram( # Watch the order!!!. TODO: use named parameters
         $USES,
         $REMOTE_LIBRARY,
         $class,
         $host, 
         $log, 
         $err, 
         $startdir, 
         $startenv, 
         $pushinc, 
         $unshiftinc, 
         $sendstdout, 
         $cleanup, 
         $prefix,
         $portdebug,
     ); 
     #print "$remoteprogram\n" if $portdebug;

     $writefunc->( $remoteprogram );

     my $self = {
        host       => $host,
        port       => $port,
        identity   => $identity,
        readfunc   => $readfunc,
        writefunc  => $writefunc,
        pid        => $pid,
        sendstdout => $sendstdout,
        ssh        => $ssh,
        scp        => $scp,
        wait       => $wait,
        prefix     => $prefix,
     };

     my $machineclass = "$class"."::".(0+$self);

     bless $self, $machineclass;

     my $misa;
     {
       no strict 'refs';
       $misa = \@{"${machineclass}::ISA"};
     }

         unshift @{$misa}, 'GRID::Machine'
     unless first { $_ eq 'GRID::Machine' } @{$misa};

     # Allow the user to include their own
     $self->include('GRID::Machine::Core');
     $self->include('GRID::Machine::RIOHandle');

     my $includes = $opts{includes} || [];
     die "Arg 'includes' of new must be an ARRAY ref\n" unless reftype($includes) eq 'ARRAY';
     $self->include($_) for @$includes;

     $self->send_operation("GRID::Machine::DEBUG_LOAD_FINISHED") if $portdebug;

     return $self;
  }
} # end of closure

sub _get_result {
  my $self = shift;

  my ($type, @result);
  { 
    ($type, @result) = $self->read_operation();
    if ($type eq 'GRID::Machine::GPRINT') {
      print @result;
      redo;
    }
    elsif ($type eq 'GRID::Machine::GPRINTF') {;
      printf @result;
      redo;
    }
  }
  my $result = shift @result;
  $result->type($type) if blessed($result) and $result->isa('GRID::Machine::Result');
  
  return $result; # void context
}

sub eval {
   my $self = shift;
   my ( $code, @args ) = @_;

#   my ($package, $filename, $line) = caller;
#   $code = <<"EOCODE";
#package $package;
##line $line "$filename"
#$code
#EOCODE
   $self->send_operation( "GRID::Machine::EVAL", $code, \@args );

   return $self->_get_result();
}

sub compile {
   my $self = shift;
   my $name = shift;

   die "Illegal name. Full names aren't allowed\n" unless $name =~ m{^[a-zA-Z_]\w*$};

   $self->send_operation( "GRID::Machine::STORE", $name, @_ );

   return $self->_get_result( );
}

sub exists {
   my $self = shift;
   my $name = shift;

   $self->send_operation( "GRID::Machine::EXISTS", $name );

   my ($type, $result) = $self->read_operation();
   return $result if $type eq "RETURNED";
   return;
}

sub sub {
   my $self = shift;
   my $name = shift;

   my $ok = $self->compile( $name, @_);

   return $ok if (blessed($ok) && $ok->type eq 'DIED');

   # Don't overwrite existing methods 
   my $class = ref($self);
   if ($class->can($name)) {
     warn "Machine "
          .$self->host
          ." already has a method $name.";
     return $ok;
   };

   # Install it as a singleton method of the GRID::Machine object
   no strict 'refs'; 
   *{$class."::$name"} = sub { 
     my $self = shift;

     $self->call( $name, @_ ) 
   };

   return $ok;
}

# -dk- modified by Casiano
#  $m->callback( 'tutu' );
#  $m->callback( tutu => sub { ... } );
#  $m->callback( sub { ... } );
sub callback {
   my $self = shift;
   my $name = shift;
   my $cref = shift;


   if (UNIVERSAL::isa($name, 'CODE')) {
     my $id = 0+$name; 
     $self->{callbacks}->{$id} = $name;
     return bless { id => $id }, 'GRID::Machine::_RemoteStub';
   }

   die "Error: Illegal name for callback: $name\n" unless $name =~ m{^[a-zA-Z_:][\w:]*$};

   if (UNIVERSAL::isa($cref, 'CODE')) {
     $self->{callbacks}->{$name} = $cref;
   }
   else {
     my $fullname;
     if ($name =~ /^.*::(\w+)$/) {
       $fullname = $name;
       $name = $1;
     }
     else {
       $fullname = caller()."::$name";
     }

     {
       no strict 'refs';
       $self->{callbacks}->{$name} = *{$fullname}{CODE};
     }

       die "Error building callback $fullname: Not a CODE ref\n" 
     unless UNIVERSAL::isa($self->{callbacks}->{$name}, 'CODE');
   }
   $self->send_operation( "GRID::Machine::CALLBACK", $name);

   return $self->_get_result( );
}

##############################################################################
# Support for reading and sending modules
# May be I have to send this code to a separated module

sub _slurp_perl_code {
  my ($input, $lineno) = @_;
  my($level,$from,$code);

  $from=pos($$input);

  $level=1;
  while($$input=~/([{}])/gc) {
          substr($$input,pos($$input)-1,1) eq '\\' #Quoted
      and next;
          $level += ($1 eq '{' ? 1 : -1)
      or last;
  }
      $level
  and die "Unmatched { opened at line $lineno";
  $code = substr($$input,$from,pos($$input)-$from-1);
  return $code;
}

####################################################################
# Usage      : $input = slurp_file($filename, 'trg');
# Purpose    : opens  "$filename.trg" and sets the scalar
# Parameters : file name and extension (not icluding the dot)
# Comments   : Is this O.S dependent?

sub slurp_file {
  my ($filename, $ext) = @_;

    croak "Error in slurp_file opening file. Provide a filename!\n" 
  unless defined($filename) and length($filename) > 0;
  $ext = "" unless defined($ext);
  $filename .= ".$ext" unless (-r $filename) or ($filename =~ m{[.]$ext$});
  local $/ = undef;
  open my $FILE, $filename or croak "Can't open file $filename"; 
  my $input = <$FILE>;
  close($FILE);
  return $input;
}

# Reads a module and install all the subroutines in such module
# as methods of the GRID::machine object

# TODO: linenumbers
{
  my $self;

  sub SERVER {
    return $self;
  }

  sub include {
    $self = shift;
    my $desc = shift; 
    my %args = @_;

    my $exclude = $args{exclude} || [];
    my %exclude;

    if (reftype($exclude) eq 'ARRAY') {
      %exclude = map { $_ => 1 } @$exclude;
    }
    elsif (defined($exclude)) {
      die "Error: the 'exclude' parameter must be an ARRAY ref\n";
    }

    my $alias = $args{alias} || {};
    die "Error: the 'alias' parameter must be a HASH ref\n" unless UNIVERSAL::isa($alias, 'HASH');
    my %alias = %$alias;
    
    my %modules = %{which($desc)};

    for my $m (keys(%modules)) {
      my $file = which($m)->{$m}{path}; 

      unless (defined($file) and -r $file) {
        die "Can't find module $m\n";
      }

      my $input = slurp_file($file, 'pm');

      while ($input=~ m(
                          (?:\bsub\s+([a-zA-Z_]\w*)\s*{) # 1 False } (for vi)
                         |(__DATA__)                     # 2
                         |(__END__)                      # 3
                         |(\n=(?:head[1-4]|pod|over|begin|for)) # 4 pod
                         |(\#.*)                                # 5
                         |("(?:\\.|[^"])*") # 6 "double quoted string"
                         |('(?:\\.|[^'])*') # 7 'single quoted string'
                         #  to be done: <<"HERE DOCS"
                         #  q, qq, etc.
                         |(?:use\s+(.*)) # 8 use Something qw(chuchu chim);
                         |(LOCAL\s+{) # 9 False } # Execute code in the local side
                       )gx) 
      { 
        my ($name, $data, $end, $pod, $comment, $dq, $sq, $use, $local) 
         = ($1,    $2,    $3,   $4,   $5,       $6,  $7,  $8, $9);
        # Finish if found __DATA__ or  __END__
        last if defined($data) or defined($end); 

        if (defined($pod)) { # POD found: skip it
          next if ($input=~ m{\n\n=cut\n}gc);
          last; # Not explicit '=cut' therefore everything is documentation
        }

        next if defined($comment) or defined($dq) or defined($sq);

        if (defined($use)) {
          $self->eval("use $use")->ok or die "Can't use lib '$use' in ".$self->host."\n"; 
          next;
        }

        if (defined($local)) {
          # execute this code on the local side
          my $code = _slurp_perl_code(\$input, 0);
          eval($code);
          die "Error executing LOCAL: $@\n" if $@;
          next;
        }

        # sub found: install it
        my $code = _slurp_perl_code(\$input, 0);
        my $alias = $name;
        $alias = $alias{$name} if defined($alias{$name});
        unless ($exclude{$name}) {
          my $r = $self->sub($alias, $code);
          $r->ok or die "Can't compile sub '$alias' in ".$self->host.":\n$r\n";
        }
      }
    }
  }
} # closure

#######################################################################3

sub call
{
   my $self = shift;
   #my ( $name, @args ) = @_;
   my $name = shift;

   # id-list of anonymous inline callback stubs (-dk-)
   my @ids;
   foreach my $a (@_) {
      push @ids, $a->{id} if UNIVERSAL::isa($a, 'GRID::Machine::_RemoteStub')
   }
   $self->send_operation( "GRID::Machine::CALL", $name, \@_ );

   my $result = $self->_get_result_or_callback(@ids); # -dk-

   # cleanup (-dk-) See examples/anonymouscallback2.pl
   #foreach my $id (@ids) {
   #   delete $self->{callbacks}->{$id}
   #}

   return $result;
}

# -dk-
sub _get_result_or_callback {
  my $self = shift;

  my ($type, @list);
  {
    @list = $self->read_operation();
    $type = shift @list;
    if ($type eq 'GRID::Machine::GPRINT') {
      print @list;

      redo;
    }
    if ($type eq 'GRID::Machine::GPRINTF') {;
      printf @list;

      redo;
    }
    if ($type eq 'CALLBACK') {
      my $name = shift @list;
      # FIXME: eval callback to catch and propagate exceptions
      $self->send_operation('RESULT', $self->{callbacks}->{$name}->(@list));
      redo;
    }
  }
  my $result = shift @list;
  $result->type($type) if blessed($result) and $result->isa('GRID::Machine::Result');

  return $result; # void context
}

# True if machine accepts automatic ssh connections 
# Eric version. Thanks Eric!
sub is_operative {
  my $ssh = shift;
  my $host = shift;
  my $command = shift || 'perl -v';
  my $seconds = shift || 15;

    my $operative;

    my $devnull = File::Spec->devnull();
    eval {
        local $SIG{ALRM} = sub { die "Alarm exceeded $seconds seconds"; };
        alarm($seconds);

          my ( $savestdout, $savestdin);
          open($savestdout, ">& STDOUT"); # factorize!
          open(STDOUT,">", $devnull);

          open($savestdin, "<& STDIN");
          open(STDIN,">", $devnull);

            $operative = !system("$ssh $host $command");

          open(STDOUT, ">&", $savestdout);
          open(STDIN, "<&", $savestdin);

        alarm(0);
    };

    if($@) {
        return 0;
    }
    return $operative;
}

sub put {
  my $self = shift;
  my $files = shift;
  die "Error in put: provide source files\n" unless UNIVERSAL::isa($files, "ARRAY") && @$files;
  my @files = @{$files};

  my $dest = shift || $self->getcwd()->result;

  # Check if $dest is a relative path
  unless (File::Spec->file_name_is_absolute($dest)) {
    $dest = File::Spec->catpath('', $self->getcwd()->result, $dest);
  }

  # Warning: bug. "host" may be is not defined!!!!!!!!!!
  my $host = $self->host;
  die "put error: host is not defined\n" unless defined($host);

  my $scp = $self->{scp};
  die "put error: scp is not defined\n" unless defined($scp);

  # Check if @files exist in the local system
  # Check if they exist in the remote system. If so what permits they have?
  system("$scp @files $host:$dest") and die "GRID::Machine::put Error: Copying files @files to $host:$dest\n";
  return 1;
}

sub get {
  my $self = shift;
  my $files = shift;
  die "Error in get: provide source files\n" unless UNIVERSAL::isa($files, "ARRAY") && @$files;
  my @files = @{$files};

  my $dest = shift || Cwd::getcwd();

  #Warning: bug. host may be is not defined!!!!!!!!!!
  my $host = $self->host;
  die "put error: host is not defined\n" unless defined($host);

  my $scp = $self->{scp};
  die "put error: scp is not defined\n" unless defined($scp);

  my $from = shift || $self->getcwd()->result;

  for (@files) {
    # Check if $from is a relative path
    unless (File::Spec->file_name_is_absolute($_)) {
      $_ = File::Spec->catpath('', $from, $_);
    }
    $_ = "$host:$_";
  }

  # Check if @files exist
  system("$scp @files $dest") and die "get Error: copying files @files\n";
  return 1;
}

sub run {
  my $m = shift;
  my $command = shift;

  my $r = $m-> system($command);
  print "$r";

  return !$r->stderr;
}

# Install a module (.pm) or a family of modules (Parse::) on the remote machine
# does not deal with dependences
sub modput {
  my $self = shift;

  my @args;

  for my $descriptor (@_) {
    my %modules = %{which($descriptor)};

    for my $module (keys(%modules)) {
      # TODO: Check if that module already exists
      #
      my $path = which($module)->{$module}{path}; 

      unless (defined($path) and -r $path) {
        die "Can't find module $module\n";
      }

      local $/ = undef;
      open my $FILE, "< $path";
        my $m = <$FILE>;
      close($FILE);
      push @args, $module, $m;
    }
  }
  $self->send_operation("GRID::Machine::MODPUT", @args);

  return $self->_get_result();
}

# Not finished
sub module_transfer {
  my $self = shift;

  my $olddir = $self->getcwd->result;

  my $dir = $self->prefix;
  $self->chdir($dir);

  for my $dist (@_) {
    my %modules = %{which($dist)};
    for my $m (keys(%modules)) {
      my $path = which($m)->{$m}{path}; 

      unless (defined($path) and -r $path) {
        die "Can't find module $m\n";
      }

      $self->put([$path]);
    } # for
  } # for

  $self->chdir($olddir);
}

# Warning! needs more exception control
# Must be based on rsync instead of put
# Include tar.gz case: expand automatically
# and use the corresponding directory
# perhaps a hook callback after the fileswere transferred?
# Control de args: check!!
sub copyandmake {
  my $m = shift;
  my %arg = @_;

  my $dir = $arg{dir} || die "copyandmake error: Provide a directory\n";
  my $target = $arg{target} || '';
  my $files = $arg{files} || [];
  my $existsmakefile  = first { $_ eq 'Makefile' } @$files;
  my $make = $existsmakefile ? 'make' : '';
  $make = $arg{make} if defined($arg{make});
  my $makeargs = $arg{makeargs} || '';
  my $cleanfiles = $arg{cleanfiles} || 0;
  my $cleandirs = $arg{cleandirs} || 0;
  my $keepdir = $arg{keepdir} || 0;

  $m->mkdir($dir) unless $m->_x($dir)->result;

  $m->mark_as_clean(dirs=> [ $dir ]) if $cleandirs;

  my $olddir = $m->getcwd();
  $m->chdir($dir);

  # Must be done after changing directory ...
  $m->mark_as_clean(files=>$files) if $cleanfiles;

  unless ($m->_x($target)->result) {
    if (@$files) { 
      $m->put($files);
    }
    if ($make) {
      my $r = $m->system("$make $makeargs");
      die "copyandmake error while executing $make $makeargs $!" unless $r->ok;
    }
  }

  $m->chdir($olddir) if $keepdir;
}

# Add a SIGPIPE handler
sub openpipe {
  my $machine = shift;
  my $exec = shift;
  my $mode = shift;

  my $host = $machine->host;
  my $ssh = $machine->ssh;

  my $r = $machine->wrapexec($exec);
  die $r unless $r->ok;

  my $scriptname = $r->result;

  my $command = "$ssh $host perl $scriptname";
  $command = $mode? "$command |" : "| $command";

  my $proc = IO::File->new;
  my $pid = open($proc, $command) || die "Can't open <$ssh $host perl $scriptname>\n";

  return (wantarray ? ($proc, $pid) : $proc);
}

# Add a SIGPIPE handler
sub open {
  my ($self, $descriptor) = @_;

  # Output pipe
  return $self->openpipe($descriptor, 1) if ($descriptor =~ s{\|\s*$}{}); 

  # Input pipe
  return $self->openpipe($descriptor, 0) if ($descriptor =~ s{^\s*\|}{}); 

  $self->send_operation( "GRID::Machine::OPEN", $descriptor );

  my $index = $self->_get_result()->result;

  return bless { index => $index, server => $self }, 'GRID::Machine::IOHandle';
}

sub DESTROY {
   my $self = shift;

   $self->send_operation( "GRID::Machine::QUIT" );

   my $ret = $self->_get_result( );

       warn "Remote host ".$self->host
           ." threw an exception while quitting"
           .$ret->errmsg
   if blessed($ret) && ( $ret->type eq "DIED" );

   waitpid $self->{pid}, 0 if defined $self->{pid};
}

sub qc {
   my ($package, $filename, $line) = caller;
   return <<"EOI";

#line $line $filename
@_
EOI
}

sub qx {
  my $self = shift;

  my $wantarray = wantarray();
  my $r = $self->qqx($wantarray, $/, @_);
  $wantarray? $r->Results : $r->result;
}

1;

