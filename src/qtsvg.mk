# This file is part of MXE.
# See index.html for further information.

PKG             := qtsvg
$(PKG)_IGNORE   :=
$(PKG)_VERSION   = $(qtbase_VERSION)
$(PKG)_CHECKSUM := cbbe6dca5fdf02b43c040e9e0b7e2514a5de0e0c
$(PKG)_SUBDIR    = $(subst qtbase,qtsvg,$(qtbase_SUBDIR))
$(PKG)_FILE      = $(subst qtbase,qtsvg,$(qtbase_FILE))
$(PKG)_URL       = $(subst qtbase,qtsvg,$(qtbase_URL))
$(PKG)_DEPS     := gcc qtbase

define $(PKG)_UPDATE
    echo $(qtbase_VERSION)
endef

define $(PKG)_BUILD
    cd '$(1)' && '$(PREFIX)/$(TARGET)/qt5/bin/qmake'
    $(MAKE) -C '$(1)' -j '$(JOBS)'
    $(MAKE) -C '$(1)' -j 1 install
endef

