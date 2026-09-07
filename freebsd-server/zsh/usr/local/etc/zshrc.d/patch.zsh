# /usr/local/etc/zshrc.d/patch.zsh

# Favor the GNU variant of `patch`.
if [[ ${+commands[gpatch]} -ne 0 ]]
then
    alias patch="gpatch"
else
    alias patch="patch --posix"
fi

