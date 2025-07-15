sudo apt update
sudo apt upgrade -y

sudo apt install zsh

git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
~/.fzf/install
echo 'source <(fzf --zsh)' >> .zshrc
cd

sudo apt install -y lsd

zsh <(curl -s https://raw.githubusercontent.com/zap-zsh/zap/master/install.zsh) --branch release-v1

cd

echo 'plug "romkatv/powerlevel10k"' >> .zshrc

echo 'plug "wintermi/zsh-lsd"' >> .zshrc

echo 'plug "zsh-users/zsh-syntax-highlighting"' >> .zshrc

echo 'plug "zsh-users/zsh-history-substring-search"' >> .zshrc

echo 'plug "Aloxaf/fzf-tab"' >> .zshrc
