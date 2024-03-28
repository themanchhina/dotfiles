#!/bin/sh

# install homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/opt/homebrew/bin/brew shellenv)"
brew tap sdkman/tap
brew install zsh antigen sdkman-cli fnm

# link dotfiles
dir=$(pwd)
rm ~/.zshrc; ln -s $dir/.zshrc ~/.zshrc
rm ~/.zprofile; ln -s $dir/.zprofile ~/.zprofile
rm ~/.antigenrc; ln -s $dir/.antigenrc ~/.antigenrc
rm ~/.ssh/config; ln -s $dir/ssh-config ~/.ssh/config

rm ~/.gitconfig; ln -s $dir/.gitconfig ~/.gitconfig
rm ~/code/git.conf; ln -s $dir/git.conf ~/code/git.conf

# download recommended powerline10k font
cd ~/Library/Fonts && { 
    curl -L 'https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Regular.ttf' -o 'MesloLGS NF Regular.ttf'
    curl -L 'https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold.ttf' -o 'MesloLGS NF Bold.ttf'
    curl -L 'https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Italic.ttf' -o 'MesloLGS NF Italic.ttf'
    curl -L 'https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold%20Italic.ttf' -o 'MesloLGS NF Bold Italic.ttf'
    cd -; }
