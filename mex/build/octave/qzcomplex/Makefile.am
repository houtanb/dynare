EXEEXT = .oct
include ../mex.am

mex_PROGRAMS = qzcomplex

nodist_qzcomplex_SOURCES = \
	qzcomplex.cc

FILES_TO_LINK = \
	$(addprefix ../../../sources/qzcomplex/,$(nodist_qzcomplex_SOURCES))

include ../../linkmexfiles.am

distclean-local:
	rm -f $(nodist_qzcomplex_SOURCES)
	rm -f .mexfileslinked
