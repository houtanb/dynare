EXEEXT = .mex
include ../mex.am
include ../../ms_sbvar.am

ms_sbvar_command_line_CPPFLAGS = $(AM_CPPFLAGS) $(CPPFLAGS_MATIO)
ms_sbvar_create_init_file_CPPFLAGS = $(AM_CPPFLAGS) $(CPPFLAGS_MATIO)

ms_sbvar_command_line_LDFLAGS = $(AM_LDFLAGS) $(LDFLAGS_MATIO)
ms_sbvar_create_init_file_LDFLAGS = $(AM_LDFLAGS) $(LDFLAGS_MATIO)

ms_sbvar_command_line_LDADD = $(LIBADD_MATIO)
ms_sbvar_create_init_file_LDADD = $(LIBADD_MATIO)
