dnl @synopsis AX_SIZE_T_PRINTF
dnl
dnl Test if %zx is supported by printf.
dnl
dnl @version
dnl @author <alon.barlev@gmail.com>
AC_DEFUN([AX_SIZE_T_PRINTF], [dnl
	AC_TYPE_SIZE_T dnl
	AC_CHECK_SIZEOF([size_t])dnl
	AC_MSG_CHECKING([size_t printf format])
	if test ${ac_cv_sizeof_size_t} = 4; then
		ax_cv_printf_z_format="%08x"
	else
		ax_cv_printf_z_format="%016lx"
	fi
	AC_MSG_RESULT([${ax_cv_printf_z_format}])dnl
	AC_DEFINE_UNQUOTED(
		[PRINTF_Z_FORMAT],dnl
		["${ax_cv_printf_z_format}"],dnl
		[Define printf format for size_t]dnl
	)dnl
])
