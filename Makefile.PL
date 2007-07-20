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
  examples/MyLocal.pm
  examples/MyRemote.pm
  examples/extendprotocol.pl
  examples/synopsis1.pl
);
return <<"EOT";
pdf: @files
	atopdf @files -o /tmp/gridmachine.pdf

publicdist: dist
	chmod a+r GRID-Machine-*.tar.gz
	cp GRID-Machine-0.07.tar.gz /home/pp2/public_html/perlexamples/

xdvi: 
	pod2latex -full -prefile preamble.tex lib/GRID/Machine.pod
	latex Machine
	latex Machine
	makeindex Machine; latex Machine.tex 

html:
	mpod2html -nowarnings -noverbose -nonavigation -nobanner -noidx -notoc lib/GRID/Machine.pod

publish: html xdvi
	cp Machine.dvi /home/pp2/public_html/GRID_Machine/
	cp Machine.html /home/pp2/public_html/GRID_Machine/
EOT
}

