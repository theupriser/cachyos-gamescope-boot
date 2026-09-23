#!/bin/bash
# Undo journal for per-user KDE settings, so every component can be turned
# off again exactly: the first time a component changes a key, the key's
# previous value is recorded, and reverting the component puts it back (or
# deletes the key if it didn't exist before).
# Sourced by setup-gamescope-boot.sh; not meant to be run on its own.

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/cachyos-gamescope-boot"
UNSET=$'\x01'

kset() {
    # kset <component> <file> <group[|group...]> <key> <value>
    # kwriteconfig6, recording the old value in the component's journal.
    # <value> "--delete" removes the key.
    local component="$1" file="$2" groups="$3" key="$4" value="$5"
    local journal="$STATE_DIR/$component.journal" old id
    local -a gargs=() g
    local groups_item
    IFS='|' read -ra g <<< "$groups"
    for groups_item in "${g[@]}"; do gargs+=(--group "$groups_item"); done

    mkdir -p "$STATE_DIR"
    id="$(printf '%s\t%s\t%s' "$file" "$groups" "$key")"
    if ! grep -qxF -- "$id" <(cut -f1-3 "$journal" 2>/dev/null); then
        old="$(kreadconfig6 --file "$file" "${gargs[@]}" --key "$key" --default "$UNSET")"
        printf '%s\t%s\n' "$id" "$(printf '%s' "$old" | base64 -w0)" >> "$journal"
    fi

    if [[ "$value" == "--delete" ]]; then
        kwriteconfig6 --file "$file" "${gargs[@]}" --key "$key" --delete
    else
        kwriteconfig6 --file "$file" "${gargs[@]}" --key "$key" "$value"
    fi
}

krevert() {
    # krevert <component>: restore every key the component changed, newest
    # first, then forget the journal.
    local component="$1"
    local journal="$STATE_DIR/$component.journal"
    local file groups key old groups_item
    local -a g
    [[ -f "$journal" ]] || return 0
    while IFS=$'\t' read -r file groups key old; do
        local -a gargs=()
        IFS='|' read -ra g <<< "$groups"
        for groups_item in "${g[@]}"; do gargs+=(--group "$groups_item"); done
        old="$(printf '%s' "$old" | base64 -d)"
        if [[ "$old" == "$UNSET" ]]; then
            kwriteconfig6 --file "$file" "${gargs[@]}" --key "$key" --delete
        else
            kwriteconfig6 --file "$file" "${gargs[@]}" --key "$key" "$old"
        fi
    done < <(tac "$journal")
    rm -f "$journal"
}

has_journal() {
    [[ -s "$STATE_DIR/$1.journal" ]]
}

state_set() {
    # state_set <component> <name> <value>: remember a value for later.
    mkdir -p "$STATE_DIR"
    kwriteconfig6 --file "$STATE_DIR/$1.state" --group State --key "$2" "$3"
}

state_get() {
    # state_get <component> <name> [default]
    kreadconfig6 --file "$STATE_DIR/$1.state" --group State --key "$2" --default "${3:-}"
}

state_clear() {
    rm -f "$STATE_DIR/$1.state"
}

current_display_manager() {
    systemctl show -p Id --value display-manager 2>/dev/null | sed 's/\.service$//'
}
