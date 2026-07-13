# if not running interactively, don't do anything
[[ $- != *i* ]] && return

export EDITOR=vi
export VISUAL=vi

export BUN_INSTALL="$HOME/.bun"
export PATH="$PATH:$BUN_INSTALL/bin"

export PATH="$PATH:$HOME/scripts"

export PS1='\[\e[31m\][\[\e[33m\]\u\[\e[32m\]@\[\e[34m\]\h \[\e[35m\]\W\[\e[31m\]]\[\e[m\]\$ '

alias nvim="nvi"
alias yay="ya"

alias sc="ssh vps1 systemctl --user"
alias ssc="ssh vps1 sudo systemctl"
alias jc="ssh vps1 journalctl --user -u"
alias jjc="ssh vps1 journalctl -u"

alias ports="sudo ss -lntup"
alias clean-cache="ya -Yc && ya -Scc && bun pm -g cache rm"
alias pa="ssh -t vps1 podman attach "
alias caddy-reload="ssh vps1 podman exec -w /etc/caddy caddy caddy reload"
