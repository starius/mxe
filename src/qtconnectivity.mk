# This file is part of MXE.
# See index.html for further information.

PKG             := qtconnectivity
$(PKG)_IGNORE   :=
$(PKG)_VERSION   = $(qtbase_VERSION)
$(PKG)_CHECKSUM := 098fa8e6690219b27818e7331ed1caf5b94245f9
$(PKG)_SUBDIR    = $(subst qtbase,qtconnectivity,$(qtbase_SUBDIR))
$(PKG)_FILE      = $(subst qtbase,qtconnectivity,$(qtbase_FILE))
$(PKG)_URL       = $(subst qtbase,qtconnectivity,$(qtbase_URL))
$(PKG)_DEPS     := gcc qtbase qtdeclarative

define $(PKG)_UPDATE
    echo $(qtbase_VERSION)
endef

define $(PKG)_BUILD
    cd '$(1)' && '$(PREFIX)/$(TARGET)/qt5/bin/qmake'
    $(MAKE) -C '$(1)' -j '$(JOBS)'
    $(MAKE) -C '$(1)' -j 1 install
endef

