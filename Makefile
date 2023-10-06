OMZ_REPO: https://github.com/ohmyzsh/ohmyzsh.git
HS_REPO: https://github.com/blackden/home_stuff.git
OMZ_DIR: ~/.oh-my-zsh
HS_DIR: ~/home_stuff
ZSHRC_TARGET: ~/.zshrc
ZSHRC_BAK: ~/.zshrc.bak

.PHONY: clean

install_dependencies:
	brew update && brew upgrade
	brew install git zsh rsync

make_omz:
	@if [ -d $(OMZ_DIR) ];  then \
		echo "OMZ уже склонирован."; \
	else \
		git clone $(OMZ_REPO) $(OMZ_DIR)
		cp -a $(ZSHRC_TARGET) $(ZSHRC_BAK)
	fi

make_home_stuff:
	@if [ -d $(HS_DIR) ];  then \
		echo "home_stuff уже склонирован."; \
	else \
		git clone $(HS_REPO) $(HS_DIR)
		cp -a $(HS_DIR)/.zshrc $(ZSHRC_TARGET)
		chsh -s $(which zsh)
	fi

clean:
	rm -rf $(OMZ_DIR) $(HS_DIR) $(ZSHRC_TARGET)
	chsh -s $(which bash)

install_and_clone: install_dependencies make_omz make_home_stuff
