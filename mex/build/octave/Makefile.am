ACLOCAL_AMFLAGS = -I ../../../m4

if DO_SOMETHING
SUBDIRS = mjdgges kronecker bytecode block_kalman_filter sobol local_state_space_iterations

# libdynare++ must come before gensylv, k_order_perturbation, dynare_simul_
if HAVE_MATIO
SUBDIRS += libdynare++ gensylv k_order_perturbation dynare_simul_
endif

if HAVE_GSL
if HAVE_MATIO
SUBDIRS += ms_sbvar
endif
endif

if HAVE_SLICOT
SUBDIRS += kalman_steady_state
endif

install-exec-local:
	$(MKDIR_P) $(DESTDIR)$(pkglibdir)/mex/octave

endif
