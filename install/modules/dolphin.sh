#!/usr/bin/env bash

DOLPHIN_DESKTOP_ID="org.kde.dolphin.desktop"
DOLPHIN_ICON="org.kde.dolphin"

remove_ski_installation() {
    # Remove only the files deployed by Serpantinum's former Ski installer.
    # In particular, remove Ski's FileManager1 D-Bus service from /usr/local
    # so it cannot shadow the FileManager1 service shipped by Dolphin.
    local stale_files=(
        "/usr/local/bin/ski"
        "/usr/local/share/applications/ski.desktop"
        "/usr/local/share/icons/hicolor/scalable/apps/ski.svg"
        "/usr/local/share/xdg-desktop-portal/portals/ski.portal"
        "/usr/local/share/dbus-1/services/org.freedesktop.impl.portal.desktop.ski.service"
        "/usr/local/share/dbus-1/services/org.freedesktop.FileManager1.service"
        "/usr/local/share/licenses/ski/LICENSE"
    )

    sudo rm -f -- "${stale_files[@]}"
    rm -f "${XDG_STATE_HOME:-$HOME/.local/state}/serpantinum/ski-version"
    hash -r

    if command -v update-desktop-database >/dev/null 2>&1; then
        sudo update-desktop-database /usr/local/share/applications >/dev/null 2>&1 || true
    fi
    if command -v gtk-update-icon-cache >/dev/null 2>&1; then
        sudo gtk-update-icon-cache -qf /usr/local/share/icons/hicolor >/dev/null 2>&1 || true
    fi
}

install_dolphin() {
    if ! command -v dolphin >/dev/null 2>&1; then
        echo -e "\e[33m[ WARN ]\e[0m Dolphin is not available; check the package installation log."
        return 0
    fi

    echo -e "\n\e[36m[ INFO ]\e[0m Removing the previous Ski integration..."
    remove_ski_installation
    echo -e "\e[32m[ OK ]\e[0m Dolphin is installed and the old Ski services have been removed."
}

set_portal_filechooser() {
    local conf="$1"
    local backend="gtk"
    local key="org.freedesktop.impl.portal.FileChooser"
    mkdir -p "$(dirname "$conf")"

    if [ ! -f "$conf" ]; then
        printf '[preferred]\n%s=%s\n' "$key" "$backend" > "$conf"
    elif grep -q "^${key}=" "$conf"; then
        sed -i "s|^${key}=.*|${key}=${backend}|" "$conf"
    elif grep -q '^\[preferred\]' "$conf"; then
        sed -i "/^\[preferred\]/a ${key}=${backend}" "$conf"
    else
        printf '\n[preferred]\n%s=%s\n' "$key" "$backend" >> "$conf"
    fi
}

dolphin_set_portal_preference() {
    local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/xdg-desktop-portal"

    # Hyprland uses a desktop-specific file. Keep its normal Hyprland/GTK
    # portal routing and send FileChooser requests to the already-installed GTK backend.
    local hyprland_conf="$config_dir/hyprland-portals.conf"
    if [ ! -f "$hyprland_conf" ]; then
        mkdir -p "$config_dir"
        cat > "$hyprland_conf" <<'EOF'
[preferred]
default=hyprland;gtk
org.freedesktop.impl.portal.FileChooser=gtk
EOF
    else
        set_portal_filechooser "$hyprland_conf"
    fi

    # Keep the chooser preference available for other supported compositors
    # without changing their default backend for unrelated portal interfaces.
    set_portal_filechooser "$config_dir/portals.conf"
}

dolphin_set_dock_entry() {
    local settings="${XDG_CONFIG_HOME:-$HOME/.config}/serpantinum/settings.json"
    [ -s "$settings" ] || return 0
    command -v jq >/dev/null 2>&1 || return 0

    local updated
    updated="$(jq --arg desktop "$DOLPHIN_DESKTOP_ID" --arg icon "$DOLPHIN_ICON" '
        if (.dock.apps // null) == null then .
        else .dock.apps |= map(
            if ((.desktop_id // "") | test("^(ski|org\\.gnome\\.Nautilus(\\.desktop)?)$"))
            then .desktop_id = $desktop | .icon = $icon
            else . end)
        end' "$settings" 2>/dev/null)"

    [ -n "$updated" ] && printf '%s\n' "$updated" > "$settings"
}

configure_dolphin_defaults() {
    command -v dolphin >/dev/null 2>&1 || return 0

    if command -v xdg-mime >/dev/null 2>&1; then
        xdg-mime default "$DOLPHIN_DESKTOP_ID" inode/directory 2>/dev/null || true
    fi

    dolphin_set_portal_preference

    local env_dir="${XDG_CONFIG_HOME:-$HOME/.config}/environment.d"
    mkdir -p "$env_dir"
    printf 'GTK_USE_PORTAL=1\n' > "$env_dir/serpantinum-portal.conf"

    dolphin_set_dock_entry
}
