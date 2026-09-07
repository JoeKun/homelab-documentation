# /usr/local/etc/zshrc.d/mdv.zsh

# Combine the markdown viewer with a pager.
if [[ ${+commands[mdv]} -ne 0 ]]
then
    function mdv() {
        command mdv "$@" 2> /dev/null | less -R
    }
fi

