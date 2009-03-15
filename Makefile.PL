use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'GRID::Machine',
    VERSION_FROM      => 'lib/GRID/Machine.pm', # finds $VERSION
    PREREQ_PM         => {Module::Which => '0.0205', }, 
    'EXE_FILES'       => [ # 'scripts/gmdb', # remote debugger. Not finished
                           'scripts/remotetest.pl' 
                         ],
    ($] >= 5.007 ?     ## Add these new keywords supported since 5.005
      (
         ABSTRACT_FROM  => 'lib/GRID/Machine.pod', # retrieve abstract from module
         AUTHOR         => 'Casiano Rodriguez-Leon <casiano@ull.es>',
      )
      : ()
    )
);

sub MY::postamble {
  # To check tests in remote machines. See goal remotetest
	my @machines = qw{orion beowulf};

	# To print: see goal pdf
	my @files = (
		'TODO',
		'lib/GRID/Machine.pm',
		'lib/GRID/Machine/Core.pm',
	#  'lib/GRID/Machine/MakeAccessors.pm',
		'lib/GRID/Machine/Message.pm',
		'lib/GRID/Machine/REMOTE.pm',
	#  'lib/GRID/Machine/Request.pm',
		'lib/GRID/Machine/Result.pm',
		 'lib/GRID/Machine/IOHandle.pm',
		 'lib/GRID/Machine/RIOHandle.pm',
	#  'examples/MyLocal.pm',
	#  'examples/MyRemote.pm',
	#  'examples/extendprotocol.pl',
	#  'examples/synopsis',1'.pl',
	#  'examples/gprint.pl',
	#  'examples/nestedcallback.pl',
	#  'examples/salida',
	);

return <<"EOT";

doc:tt2/Machine.tt2 tt2/Message.tt2 tt2/REMOTE.tt2 tt2/Result.tt2
	cd tt2; tpage  Machine.tt2 > ../lib/GRID/Machine.pod
	cd tt2; tpage  Message.tt2 > ../lib/GRID/Machine/Message.pod
	cd tt2; tpage  REMOTE.tt2 > ../lib/GRID/Machine/REMOTE.pod
	cd tt2; tpage  Core.tt2 > ../lib/GRID/Machine/Core.pod
	cd tt2; tpage  Result.tt2 > ../lib/GRID/Machine/Result.pod
	cd tt2; tpage  IOHandle.tt2 > ../lib/GRID/Machine/IOHandle.pod
	cd tt2; tpage  perlparintro.tt2 > ../lib/GRID/Machine/perlparintro.pod
	cd tt2; tpage  remotedebugtut.tt2 > ../lib/GRID/Machine/remotedebugtut.pod

pdf: @files
	atopdf @files -o /tmp/gridmachine.pdf

publicdist: publish rmdist dist
	chmod a+r GRID-Machine-*.tar.gz
	cp GRID-Machine-*.tar.gz /home/pp2/public_html/perlexamples/GRID-Machine.tar.gz
	cp GRID-Machine-*.tar.gz /tmp/
	chmod a+r /tmp/GRID-Machine-*.tar.gz

rmdist:
	rm -fR GRID-Machine-*.tar.gz
	rm -fR /tmp/GRID-Machine-*.tar.gz

xdvi: doc
	pod2latex -full -prefile preamble.tex lib/GRID/Machine.pod
	latex Machine
	latex Machine
	makeindex Machine; latex Machine.tex 
	pod2latex -full -prefile preamble.tex lib/GRID/Machine/IOHandle.pod
	latex IOHandle
	latex IOHandle
	makeindex IOHandle; latex IOHandle.tex 
	pod2latex -full -prefile preamblegen.tex lib/GRID/Machine/perlparintro.pod
	#pod2latex -full lib/GRID/Machine/perlparintro.pod
	latex perlparintro
	latex perlparintro
	makeindex perlparintro; latex perlparintro.tex 
	pod2latex -full -prefile preamblegen.tex lib/GRID/Machine/remotedebugtut.pod
	#pod2latex -full lib/GRID/Machine/remotedebugtut.pod
	latex remotedebugtut
	latex remotedebugtut
	makeindex remotedebugtut; latex remotedebugtut.tex 

html: doc
	mpod2html -nowarnings -noverbose -nonavigation -nobanner -noidx -notoc lib/GRID/Machine.pod
	mpod2html -nowarnings -noverbose -nonavigation -nobanner -noidx -notoc lib/GRID/Machine/Core.pod
	mpod2html -nowarnings -noverbose -nonavigation -nobanner -noidx -notoc lib/GRID/Machine/REMOTE.pod
	mpod2html -nowarnings -noverbose -nonavigation -nobanner -noidx -notoc lib/GRID/Machine/IOHandle.pod
	mpod2html -nowarnings -noverbose -nonavigation -nobanner -noidx -notoc lib/GRID/Machine/perlparintro.pod
	mpod2html -nowarnings -noverbose -nonavigation -nobanner -noidx -notoc lib/GRID/Machine/remotedebugtut.pod
	mpod2html -nowarnings -noverbose -nonavigation -nobanner -noidx -notoc scripts/remotetest.pl

publish: doc html xdvi
	cp *.html /home/pp2/public_html/GRID_Machine/
	cp *.dvi /home/pp2/public_html/GRID_Machine/

remotetest:
	scripts/remotetest.pl \${DISTVNAME}.tar.gz @machines

.PHONY: tags
tags:
	/usr/share/vim/vim71/tools/pltags.pl lib/GRID/Machine/*.pm lib/GRID/Machine.pm
	ctags -a --exclude=examples --exclude=t --exclude=doc --exclude=tt2

EOT
}

