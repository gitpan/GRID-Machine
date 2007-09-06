use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'GRID::Machine',
    VERSION_FROM      => 'lib/GRID/Machine.pm', # finds $VERSION
    PREREQ_PM         => {Module::Which => '0.0205', }, 
    ($] >= 5.007 ?     ## Add these new keywords supported since 5.005
      (
         ABSTRACT_FROM  => 'lib/GRID/Machine.pod', # retrieve abstract from module
         AUTHOR         => 'Casiano Rodriguez-Leon <casiano@ull.es>',
      )
      : ()
    )
);

sub MY::postamble {
my @files = qw(
  TODO
  lib/GRID/Machine.pm
  lib/GRID/Machine/Core.pm
  lib/GRID/Machine/MakeAccessors.pm
  lib/GRID/Machine/Message.pm
  lib/GRID/Machine/REMOTE.pm
  lib/GRID/Machine/Request.pm
  lib/GRID/Machine/Result.pm
  lib/GRID/Machine/IOHandle.pm
  lib/GRID/Machine/RIOHandle.pm
  examples/MyLocal.pm
  examples/MyRemote.pm
  examples/extendprotocol.pl
  examples/synopsis1.pl
);
return <<"EOT";
doc:tt2/Machine.tt2 tt2/Message.tt2 tt2/REMOTE.tt2 tt2/Result.tt2
	cd tt2; tpage  Machine.tt2 > ../lib/GRID/Machine.pod
	cd tt2; tpage  Message.tt2 > ../lib/GRID/Machine/Message.pod
	cd tt2; tpage  REMOTE.tt2 > ../lib/GRID/Machine/REMOTE.pod
	cd tt2; tpage  Core.tt2 > ../lib/GRID/Machine/Core.pod
	cd tt2; tpage  Result.tt2 > ../lib/GRID/Machine/Result.pod

pdf: @files
	atopdf @files -o /tmp/gridmachine.pdf

publicdist: doc dist
	chmod a+r GRID-Machine-*.tar.gz
	cp GRID-Machine-*.tar.gz /home/pp2/public_html/perlexamples/GRID-Machine.tar.gz

xdvi: doc
	pod2latex -full -prefile preamble.tex lib/GRID/Machine.pod
	latex Machine
	latex Machine
	makeindex Machine; latex Machine.tex 

html: doc
	mpod2html -nowarnings -noverbose -nonavigation -nobanner -noidx -notoc lib/GRID/Machine.pod
	mpod2html -nowarnings -noverbose -nonavigation -nobanner -noidx -notoc lib/GRID/Machine/Core.pod

publish: doc html xdvi
	cp Machine.dvi /home/pp2/public_html/GRID_Machine/
	cp Machine.html /home/pp2/public_html/GRID_Machine/
EOT
}

