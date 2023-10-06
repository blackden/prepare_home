SHELL := /bin/bash
ZSH_PATH := $(shell which zsh)

KERNEL := $(shell uname -s)
DISTRO := $(shell cat /etc/*release | grep -oP '(?<=ID=)\w+' | head -1 | tr '[:upper:]' '[:lower:]')

OMZ_REPO := "https://github.com/ohmyzsh/ohmyzsh.git"
HS_REPO := "https://github.com/blackden/home_stuff.git"
OMZ_DIR := "$(HOME)/.oh-my-zsh"
HS_DIR := "$(HOME)/home_stuff"
ZSHRC_TARGET := "$(HOME)/.zshrc"
ZSHRC_BAK := "$(HOME)/.zshrc.bak"

all: install_dependencies make_omz make_home_stuff

.PHONY: install_dependencies make_omz make_home_stuff clean

install_dependencies:
ifeq ($(KERNEL),Darwin)
	brew update && brew upgrade
	brew install git zsh rsync
else ifeq ($(KERNEL),Linux)
ifeq ($(DISTRO),ubuntu)
	sudo apt update
	sudo apt install -y git zsh	
endif
endif

make_omz:
	@if [ -d $(OMZ_DIR) ];  then \
		echo "OMZ уже склонирован."; \
	else \
		git clone $(OMZ_REPO) $(OMZ_DIR); \
		if [ -e $(ZSHRC_TARGET) ]; then \
			cp -a $(ZSHRC_TARGET) $(ZSHRC_BAK); \
		else \
			echo "$(ZSHRC_TARGET) не существует."; \
		fi \
	fi

make_home_stuff:
	@if [ -d $(HS_DIR) ];  then \
		echo "home_stuff уже склонирован."; \
	else \
		git clone $(HS_REPO) $(HS_DIR); \
		cp -a $(HS_DIR)/.zshrc $(ZSHRC_TARGET); \
		chsh -s $(ZSH_PATH) $(USER); \
	fi

clean:
	rm -rf $(OMZ_DIR) $(HS_DIR) $(ZSHRC_TARGET)
	chsh -s $(SHELL) $(USER)

