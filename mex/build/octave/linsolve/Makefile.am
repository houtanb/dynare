EXEEXT = .oct
include ../mex.am

mex_PROGRAMS = linsolve

nodist_linsolve_SOURCES = \
	linsolve.cc

FILES_TO_LINK = \
	$(addprefix ../../../sources/linsolve/,$(nodist_linsolve_SOURCES))

include ../../linkmexfiles.am

distclean-local:
	rm -f $(nodist_linsolve_SOURCES)
	rm -f .mexfileslinked
