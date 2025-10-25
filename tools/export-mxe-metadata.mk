# Helper makefile that reuses MXE's core logic to dump package metadata.

THIS_FILE := $(lastword $(MAKEFILE_LIST))
TOP_DIR   := $(patsubst %/,%,$(dir $(abspath $(THIS_FILE))))/..

include $(TOP_DIR)/Makefile

DELIM := $(shell printf '\037')

define DUMP_GLOBAL
$(info global$(DELIM)$(1)$(DELIM)$(strip $(2)))
endef

define DUMP_PKG_FIELD
$(info pkg$(DELIM)$(1)$(DELIM)$(strip $(2))$(DELIM)$(strip $(3)))
endef

define DUMP_TARGET_FIELD
$(info target$(DELIM)$(1)$(DELIM)$(2)$(DELIM)$(strip $(3))$(DELIM)$(strip $(4)))
endef

.PHONY: metadata-dump
metadata-dump:
	$(call DUMP_GLOBAL,host,$(BUILD))
	$(call DUMP_GLOBAL,mxe-targets,$(MXE_TARGETS))
	$(call DUMP_GLOBAL,git-head,$(GIT_HEAD))
	$(foreach PKG,$(PKGS),\
		$(call DUMP_PKG_FIELD,$(PKG),version,$($(PKG)_VERSION))\
		$(call DUMP_PKG_FIELD,$(PKG),website,$($(PKG)_WEBSITE))\
		$(call DUMP_PKG_FIELD,$(PKG),description,$($(PKG)_DESCR))\
        $(call DUMP_PKG_FIELD,$(PKG),ignore,$($(PKG)_IGNORE))\
		$(call DUMP_PKG_FIELD,$(PKG),checksum,$($(PKG)_CHECKSUM))\
		$(call DUMP_PKG_FIELD,$(PKG),file,$($(PKG)_FILE))\
		$(call DUMP_PKG_FIELD,$(PKG),file-deps,$($(PKG)_FILE_DEPS))\
		$(call DUMP_PKG_FIELD,$(PKG),subdir,$($(PKG)_SUBDIR))\
		$(call DUMP_PKG_FIELD,$(PKG),url,$($(PKG)_URL))\
		$(call DUMP_PKG_FIELD,$(PKG),url-2,$($(PKG)_URL_2))\
		$(call DUMP_PKG_FIELD,$(PKG),gh-conf,$($(PKG)_GH_CONF))\
		$(call DUMP_PKG_FIELD,$(PKG),type,$($(PKG)_TYPE))\
		$(call DUMP_PKG_FIELD,$(PKG),patches,$($(PKG)_PATCHES))\
		$(call DUMP_PKG_FIELD,$(PKG),source-tree,$($(PKG)_SOURCE_TREE))\
		$(call DUMP_PKG_FIELD,$(PKG),targets,$($(PKG)_TARGETS))\
	)
	$(foreach PKG,$(PKGS),\
		$(foreach TARGET,$(MXE_TARGETS),\
			$(if $(filter $(PKG),$($(TARGET)_PKGS)),\
				$(call DUMP_TARGET_FIELD,$(PKG),$(TARGET),build,$(if $(value $(call LOOKUP_PKG_RULE,$(PKG),BUILD,$(TARGET))),yes,no))\
				$(call DUMP_TARGET_FIELD,$(PKG),$(TARGET),deps,$(value $(call LOOKUP_PKG_RULE,$(PKG),DEPS,$(TARGET))))\
				$(call DUMP_TARGET_FIELD,$(PKG),$(TARGET),oo-deps,$(value $(call LOOKUP_PKG_RULE,$(PKG),OO_DEPS,$(TARGET))))\
				$(call DUMP_TARGET_FIELD,$(PKG),$(TARGET),file,$(value $(call LOOKUP_PKG_RULE,$(PKG),FILE,$(TARGET))))\
				$(call DUMP_TARGET_FIELD,$(PKG),$(TARGET),url,$(value $(call LOOKUP_PKG_RULE,$(PKG),URL,$(TARGET))))\
				$(call DUMP_TARGET_FIELD,$(PKG),$(TARGET),url-2,$(value $(call LOOKUP_PKG_RULE,$(PKG),URL_2,$(TARGET))))\
				$(call DUMP_TARGET_FIELD,$(PKG),$(TARGET),message,$(value $(call LOOKUP_PKG_RULE,$(PKG),MESSAGE,$(TARGET))))\
			)\
		)\
	)
	@:

