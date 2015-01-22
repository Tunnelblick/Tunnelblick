# This Makefile builds all the third_party code
# It should not be called by anything other than automated scripts
#
# Created 2015-01-18 by Jonathan K. Bullard

ifeq "$(XCODE_VERSION_MAJOR)" "0300"
    include Makefile-Xcode3
else
    include Makefile-Xcode4andUp
endif
