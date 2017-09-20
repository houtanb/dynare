EXEEXT = .oct
include ../mex.am

mex_PROGRAMS = ordschur

nodist_ordschur_SOURCES = \
	ordschur.cc

FILES_TO_LINK = \
	$(addprefix ../../../sources/ordschur/,$(nodist_ordschur_SOURCES))

include ../../linkmexfiles.am

distclean-local:
	rm -f $(nodist_ordschur_SOURCES)
	rm -f .mexfileslinked
