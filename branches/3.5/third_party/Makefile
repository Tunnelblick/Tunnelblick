# This Makefile builds all the third_party code
# It should not be called by anything other than automated scripts
#
# Created 2015-01-18 by Jonathan K. Bullard

ifeq "$(XCODE_VERSION_MAJOR)" "0300"
	ifeq "$(XCODE_VERSION_ACTUAL)" "0322"
		include Makefile-Xcode3
	else
		@echo "error: Tunnelblick must be built with Xcode 3.2.2 or with Xcode 4 or higher"
	endif
else
    include Makefile-Xcode4andUp
endif
