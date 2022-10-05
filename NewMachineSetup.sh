#!/usr/bin/env bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
if [ "$(expr substr $(uname -s) 1 5)" == "Linux" ]; then
  echo '# Set PATH, MANPATH, etc., for Homebrew.' >> /home/runner/.bash_profile
  echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> /home/runner/.bash_profile
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi
brew update
packages=()
while IFS= read -r line; do
   packages+=("$line")
done <brews.txt

install () {
  brew install $1
  return $?
}

uninstall () {
  brew uninstall $1
  brew $?
}

force_link () {
  brew link --overwrite $1
}

for package in ${packages[@]}; do
  install $package
  [ $? -eq 0 ] && echo "$package was installed successfully" || "$package was not installed for some reason and we could not correct this."
done
