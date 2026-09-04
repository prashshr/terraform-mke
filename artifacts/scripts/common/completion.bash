# Bash completion for terraform-ps Makefile
_make_terraform_ps() {
    local cur prev words cword
    if declare -F _init_completion >/dev/null 2>&1; then
        _init_completion || return
    else
        cur="${COMP_WORDS[COMP_CWORD]}"
        prev="${COMP_WORDS[COMP_CWORD-1]}"
    fi

    # Contextual subcommands
    case "${prev}" in
        create)
            COMPREPLY=( $(compgen -W "mke3 mke4 mke3stack mke4stack" -- "$cur") )
            return 0
            ;;
        destroy)
            COMPREPLY=( $(compgen -W "mke3 mke4 mke3stack mke4stack" -- "$cur") )
            return 0
            ;;
    esac

    # Top-level clean targets
    local targets="help config-apply config-get config-edit create destroy list-running"
    COMPREPLY=( $(compgen -W "${targets}" -- "$cur") )
}
complete -F _make_terraform_ps make
