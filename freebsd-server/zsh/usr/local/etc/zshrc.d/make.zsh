# /usr/local/etc/zshrc.d/make.zsh

# Favor the GNU variant of make in general.

# However, the ports tree and poudriere’s copy of it are written
# for BSD make, so those two locations keep the base system's variant.
if [[ ${+commands[gmake]} -ne 0 ]]
then
    function make() {
        if [[ $(pwd) == "/usr/ports"* ]] || [[ $(pwd) == "/usr/local/poudriere/ports"* ]]
        then
            command make "$@"
        else
            gmake "$@"
        fi
    }
fi

