# Copyright (C) 2026 Ragnar (blackden, ragnar.black)
# SPDX-License-Identifier: GPL-3.0-only
#
# Thin wrapper over install.sh: all logic lives in the script,
# targets only map to its modes and options.

SHELL := /bin/sh
INSTALL := sh ./install.sh

# Options: make <target> USERS=ragnar,papan DRY_RUN=1
USERS ?=
DRY_RUN ?=
YES ?=
SKIP_SHELL ?=
# install.sh refuses to run as root without it
I_KNOW_WHAT_IM_DOING ?=

OPTS := $(if $(USERS),--users $(USERS)) \
        $(if $(DRY_RUN),--dry-run) \
        $(if $(YES),--yes) \
        $(if $(SKIP_SHELL),--skip-shell) \
        $(if $(I_KNOW_WHAT_IM_DOING),--i-know-what-im-doing)

OMZ_DIR := $(HOME)/.oh-my-zsh
HS_DIR := $(HOME)/home_stuff
FALLBACK_SHELL := /bin/bash

.DEFAULT_GOAL := help
.PHONY: help install minimal omz dotfiles wheel-sudo interactive clean

help:
	@echo "Targets:"
	@echo "  install      oh-my-zsh + login shell + .zshrc + .vimrc  (install.sh --all)"
	@echo "  minimal      oh-my-zsh + login shell                    (install.sh)"
	@echo "  omz          oh-my-zsh + login shell only               (install.sh --omz-only)"
	@echo "  dotfiles     .zshrc + .vimrc only                       (install.sh --dotfiles-only)"
	@echo "  wheel-sudo   enable sudo for %wheel                     (install.sh --enable-wheel-sudo)"
	@echo "  interactive  choose mode interactively                  (install.sh --interactive)"
	@echo "  clean        current user: remove oh-my-zsh, restore .zshrc/.vimrc backups, reset shell"
	@echo
	@echo "Variables:"
	@echo "  USERS=u1,u2             target users (required as root)"
	@echo "  DRY_RUN=1               print actions only"
	@echo "  YES=1                   install missing packages without asking"
	@echo "  SKIP_SHELL=1            do not change login shell"
	@echo "  I_KNOW_WHAT_IM_DOING=1  required when running as root"
	@echo
	@echo "Example:"
	@echo "  sudo make install USERS=root,ragnar,papan I_KNOW_WHAT_IM_DOING=1 YES=1"

install:
	$(INSTALL) --all $(OPTS)

minimal:
	$(INSTALL) $(OPTS)

omz:
	$(INSTALL) --omz-only $(OPTS)

dotfiles:
	$(INSTALL) --dotfiles-only $(OPTS)

wheel-sudo:
	$(INSTALL) --enable-wheel-sudo $(OPTS)

interactive:
	$(INSTALL) --interactive $(OPTS)

clean:
	rm -rf "$(OMZ_DIR)" "$(HS_DIR)"
	for f in .zshrc .vimrc; do \
		if [ -f "$(HOME)/$$f.bak" ]; then mv -f "$(HOME)/$$f.bak" "$(HOME)/$$f"; fi; \
	done
	sudo chsh -s $(FALLBACK_SHELL) $(USER)
