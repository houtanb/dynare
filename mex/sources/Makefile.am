EXTRA_DIST = \
	dynblas.h \
	dynlapack.h \
	dynumfpack.h \
	dynmex.h \
	mjdgges \
	kronecker \
	bytecode \
	k_order_perturbation \
	kalman_steady_state \
	ms-sbvar \
	block_kalman_filter \
	sobol \
	local_state_space_iterations

clean-local:
	rm -rf `find mex/sources -name *.o`

dist-hook:
	rm -rf `find $(distdir)/mex/sources -name *.o -or -name *~`
