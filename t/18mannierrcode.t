#!/usr/bin/perl
use strict;
use warnings;

my $numtests;
BEGIN {
    $numtests = 7;
}
use Test::More tests => $numtests;
BEGIN { use_ok('GRID::Machine', 'is_operative') };

my $test_exception_installed;
BEGIN {
 $test_exception_installed = 1;
 eval { require Test::Exception };
 $test_exception_installed = 0 if $@;
}

sub e2r {
  local $_ = shift;

  s/\s+//g;
  $_ = quotemeta;
  $_ = qr{$_};
}

my $debug = @ARGV ? 1234 : 0;

my $host = $ENV{GRID_REMOTE_MACHINE} || '';
SKIP: {
  skip "Remote not operative or Test::Exception not installed", $numtests-1 unless $test_exception_installed and is_operative('ssh', $host);

   my $m;
   Test::Exception::lives_ok {
     $m = GRID::Machine->new(
        host => $host,
        prefix => '/tmp/perl5lib',                                                          
        startdir => '/tmp',                                                                               
        log => '/tmp/rperl$$.log',                                                                                           
        err => '/tmp/rperl$$.err',                                                                                
        debug => $debug,
        cleanup => 1,                                                                                 
        sendstdout => 1
      );
   } 'No fatals creating a GRID::Machine object';

  my $r = $m->system("anunknowncommand");

  my $expected = e2r(q{Can't exec "anunknowncommand":});
  my $err = $r->stderr;
  $err =~s/\s+//g;
  like($err, $expected, q{Can't exec "anunknowncommand":});

  is($r->stdout, '', q{nothing in stdout});

  is($r->errcode, -1, q{result is -1});

  is($r->errmsg, '', q{errmsg is ''});

  is($r->type, 'RETURNED', q{type is 'RETURNED'});

}

