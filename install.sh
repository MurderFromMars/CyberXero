
#!/usr/bin/env bash
[ -z "$BASH_VERSION" ] && exec bash "$0" "$@"
set -euo pipefail



REPO_DIR="$HOME/CyberXero"
BACKUP_DIR="$HOME/CyberXero-backup-$(date +%Y%m%d_%H%M%S)"
DISTRO="unknown"
WALLPAPER_PATH="/usr/local/share/icons/cyberfield.jpg"
# Activity ID baked into the repo appletsrc — will be replaced with target system's ID
REPO_ACTIVITY_ID="c9d52ed7-43dd-4b93-95f6-74b5ee97b192"

log()  { printf "\033[1;36m[Ξ]\033[0m %s\n" "$1"; }
ok()   { printf "\033[1;32m[✔]\033[0m %s\n" "$1"; }
warn() { printf "\033[1;33m[!]\033[0m %s\n" "$1"; }
err()  { printf "\033[1;31m[✖]\033[0m %s\n" "$1" >&2; }

section() {
    printf "\n\033[1;35m╔═══════════════════════════════════════════════════════╗\033[0m\n"
    printf "\033[1;35m║\033[0m  %-51s \033[1;35m║\033[0m\n" "$1"
    printf "\033[1;35m╚═══════════════════════════════════════════════════════╝\033[0m\n\n"
}

subsection() {
    printf "\n\033[1;36m┌─────────────────────────────────────────────────────────┐\033[0m\n"
    printf "\033[1;36m│\033[0m  %-50s \033[1;36m│\033[0m\n" "$1"
    printf "\033[1;36m└─────────────────────────────────────────────────────────┘\033[0m\n"
}

backup_file() {
    local target="$1"
    if [ -e "$target" ]; then
        mkdir -p "$BACKUP_DIR"
        cp -a "$target" "$BACKUP_DIR/"
        log "backup → $target"
    fi
}

purge_old_panels_live() {
    log "purging existing panels from live session..."

    if ! command -v qdbus6 >/dev/null 2>&1; then
        warn "qdbus6 not found, skipping live panel purge"
        return
    fi

    qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
        const allPanels = panels();
        for (let i = allPanels.length - 1; i >= 0; i--) {
            allPanels[i].remove();
        }
    " 2>/dev/null && ok "panels removed from live session" || warn "panel removal failed"
}

stop_plasmashell() {
    log "stopping plasmashell…"
    if pgrep -x plasmashell >/dev/null 2>&1; then
        kquitapp6 plasmashell 2>/dev/null || killall plasmashell 2>/dev/null || true
        # Wait for clean exit
        local timeout=10
        while pgrep -x plasmashell >/dev/null 2>&1 && [ "$timeout" -gt 0 ]; do
            sleep 1
            timeout=$((timeout - 1))
        done
        # Force kill if still alive
        if pgrep -x plasmashell >/dev/null 2>&1; then
            kill -9 "$(pgrep -x plasmashell)" 2>/dev/null || true
            sleep 1
        fi
        ok "plasmashell stopped"
    else
        ok "plasmashell not running"
    fi
}

start_plasmashell() {
    log "starting plasmashell…"
    nohup plasmashell --replace >/dev/null 2>&1 &
    disown
    # Give it a moment to initialize
    sleep 3
    if pgrep -x plasmashell >/dev/null 2>&1; then
        ok "plasmashell started"
    else
        warn "plasmashell may not have started — check manually"
    fi
}

fetch_repo() {
    log "syncing CyberXero repository…"
    if [ ! -d "$REPO_DIR/.git" ]; then
        if git clone https://github.com/MurderFromMars/CyberXero "$REPO_DIR" 2>&1 | grep -v -E "^(remote:|Receiving|Resolving|Counting)" | grep -v "^$" || false; then
            ok "repository cloned"
        else
            err "failed to clone repository"
            exit 1
        fi
    else
        if git -C "$REPO_DIR" pull --rebase >/dev/null 2>&1; then
            ok "repository updated"
        else
            warn "failed to update repository (continuing with existing)"
        fi
    fi
}

detect_distro() {
    log "scanning system architecture…"
    if command -v pacman >/dev/null 2>&1; then
        DISTRO="arch"
        ok "arch‑based system detected"
    elif command -v dnf >/dev/null 2>&1; then
        DISTRO="fedora"
        ok "fedora‑based system detected"
    elif command -v apt >/dev/null 2>&1; then
        DISTRO="debian"
        ok "debian‑based system detected"
    else
        err "unsupported distribution"
        exit 1
    fi
}

install_arch_dependencies() {
    log "installing arch dependencies…"
    sudo pacman -S --needed --noconfirm \
        git cmake extra-cmake-modules base-devel unzip cava \
        kitty fastfetch imagemagick >/dev/null 2>&1

    if command -v yay >/dev/null 2>&1; then
        yay -S --needed --noconfirm qt5-tools >/dev/null 2>&1
    elif command -v paru >/dev/null 2>&1; then
        paru -S --needed --noconfirm qt5-tools >/dev/null 2>&1
    else
        warn "AUR helper not found → qt5-tools skipped"
    fi
    ok "arch dependencies installed"
}

install_debian_dependencies() {
    log "installing debian dependencies…"
    sudo apt update >/dev/null 2>&1
    sudo apt install -y \
        git cmake g++ extra-cmake-modules qt6-tools-dev kwin-dev unzip \
        libkf6configwidgets-dev gettext libkf6crash-dev \
        libkf6globalaccel-dev libkf6kio-dev libkf6service-dev \
        libkf6notifications-dev libkf6kcmutils-dev libkdecorations3-dev \
        libxcb-composite0-dev libxcb-randr0-dev libxcb-shm0-dev \
        qt6-base-private-dev qt6-base-dev-tools \
        libdrm-dev libplasma-dev cava \
        kitty fastfetch imagemagick >/dev/null 2>&1
    ok "debian dependencies installed"
}

install_fedora_dependencies() {
    log "installing fedora dependencies…"
    sudo dnf -y install \
        git cmake extra-cmake-modules gcc-c++ unzip \
        kf6-kwindowsystem-devel plasma-workspace-devel \
        libplasma-devel qt6-qtbase-private-devel qt6-qtbase-devel \
        kwin-devel kf6-knotifications-devel kf6-kio-devel \
        kf6-kcrash-devel kf6-ki18n-devel kf6-kguiaddons-devel \
        libepoxy-devel kf6-kglobalaccel-devel kf6-kcmutils-devel \
        kf6-kconfigwidgets-devel kf6-kdeclarative-devel \
        kdecoration-devel kf6-kglobalaccel kf6-kdeclarative \
        libplasma kf6-kio qt6-qtbase kf6-kguiaddons kf6-ki18n \
        wayland-devel libdrm-devel \
        spectacle python3 python3-dbus python3-gobject \
        qt6-qtwebsockets python3-websockets \
        cava kitty fastfetch ImageMagick >/dev/null 2>&1
    ok "fedora dependencies installed"
}

install_dependencies() {
    case "$DISTRO" in
        arch)   install_arch_dependencies ;;
        fedora) install_fedora_dependencies ;;
        debian) install_debian_dependencies ;;
        *)      err "invalid distro state"; exit 1 ;;
    esac
}

build_panel_colorizer() {
    log "compiling plasma‑panel‑colorizer…"
    local tmp
    tmp="$(mktemp -d)"
    git clone "https://github.com/luisbocanegra/plasma-panel-colorizer" "$tmp/plasma-panel-colorizer" 2>&1 | grep -v -E "^(remote:|Receiving|Resolving|Counting)" | grep -v "^$" || true
    cd "$tmp/plasma-panel-colorizer"
    chmod +x install.sh
    ./install.sh >/dev/null 2>&1 || true
    cd ~
    rm -rf "$tmp"
    ok "panel colorizer installed"
}

build_kurve() {
    log "installing kurve…"
    local tmp
    tmp="$(mktemp -d)"
    git clone "https://github.com/luisbocanegra/kurve.git" "$tmp/kurve" 2>&1 | grep -v -E "^(remote:|Receiving|Resolving|Counting)" | grep -v "^$" || true
    cd "$tmp/kurve"
    chmod +x install.sh
    ./install.sh >/dev/null 2>&1 || true
    cd ~
    rm -rf "$tmp"
    ok "kurve installed"
}

install_krohnkite() {
    log "deploying krohnkite kwinscript…"
    local script="$REPO_DIR/krohnkite.kwinscript"
    if [ ! -f "$script" ]; then
        warn "krohnkite.kwinscript missing in repo"
        return
    fi
    if command -v kpackagetool6 >/dev/null 2>&1; then
        if kpackagetool6 --type KWin/Script --install "$script" 2>/dev/null; then
            ok "krohnkite installed"
        elif kpackagetool6 --type KWin/Script --upgrade "$script" 2>/dev/null; then
            ok "krohnkite upgraded"
        else
            warn "kpackagetool6 failed, using manual installation"
            local target="$HOME/.local/share/kwin/scripts/krohnkite"
            rm -rf "$target"
            mkdir -p "$target"
            unzip -q "$script" -d "$target"
            ok "krohnkite installed (manual) → $target"
        fi
    else
        warn "kpackagetool6 not found, using manual installation"
        local target="$HOME/.local/share/kwin/scripts/krohnkite"
        rm -rf "$target"
        mkdir -p "$target"
        unzip -q "$script" -d "$target"
        ok "krohnkite installed (manual) → $target"
    fi
}

build_kde_rounded_corners() {
    log "compiling kde‑rounded‑corners…"
    local tmp
    tmp="$(mktemp -d)"
    git clone "https://github.com/matinlotfali/KDE-Rounded-Corners" "$tmp/kde-rounded-corners" 2>&1 | grep -v -E "^(remote:|Receiving|Resolving|Counting)" | grep -v "^$" || true
    cd "$tmp/kde-rounded-corners"
    mkdir build && cd build
    cmake .. >/dev/null 2>&1
    cmake --build . -j"$(nproc)" 2>&1 | grep -E "Built target|^\[" || true
    sudo make install >/dev/null 2>&1
    cd ~
    rm -rf "$tmp"
    ok "rounded corners installed"
}

build_better_blur() {
    log "compiling kwin‑effects‑better‑blur‑dx…"
    local tmp
    tmp="$(mktemp -d)"
    git clone "https://github.com/xarblu/kwin-effects-better-blur-dx" "$tmp/kwin-effects-better-blur-dx" 2>&1 | grep -v -E "^(remote:|Receiving|Resolving|Counting)" | grep -v "^$" || true
    cd "$tmp/kwin-effects-better-blur-dx"
    mkdir build && cd build
    cmake .. -DCMAKE_INSTALL_PREFIX=/usr >/dev/null 2>&1
    make -j"$(nproc)" 2>&1 | grep -E "Built target|^\[" || true
    sudo make install >/dev/null 2>&1
    cd ~
    rm -rf "$tmp"
    ok "better blur dx installed"
}

setup_autorebuild_system() {
    log "configuring auto-rebuild for KDE Rounded Corners & Better Blur DX…"
    sudo mkdir -p /usr/local/bin

    # --- KDE Rounded Corners rebuild script ---
    sudo tee /usr/local/bin/rebuild-kde-rounded-corners.sh > /dev/null <<'REBUILD_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
LOG_FILE="/var/log/kde-rounded-corners-rebuild.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "=== KDE Rounded Corners Rebuild Started ==="

TMP_DIR="$(mktemp -d)"
cd "$TMP_DIR"

log "Cloning repository..."
if git clone "https://github.com/matinlotfali/KDE-Rounded-Corners" kde-rounded-corners; then
    log "Repository cloned successfully"
else
    log "ERROR: Failed to clone repository"
    rm -rf "$TMP_DIR"
    exit 1
fi

cd kde-rounded-corners

log "Building KDE Rounded Corners..."
if mkdir build && cd build; then
    if cmake .. && cmake --build . -j"$(nproc)"; then
        log "Build successful"

        log "Installing..."
        if make install; then
            log "Installation successful"
        else
            log "ERROR: Installation failed"
            cd ~
            rm -rf "$TMP_DIR"
            exit 1
        fi
    else
        log "ERROR: Build failed"
        cd ~
        rm -rf "$TMP_DIR"
        exit 1
    fi
else
    log "ERROR: Failed to create build directory"
    cd ~
    rm -rf "$TMP_DIR"
    exit 1
fi

# Cleanup
cd ~
rm -rf "$TMP_DIR"

log "=== KDE Rounded Corners Rebuild Completed Successfully ==="

# Reconfigure KWin to load the updated effect
if command -v qdbus6 >/dev/null 2>&1; then
    qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null || true
    log "KWin reconfigured"
fi

exit 0
REBUILD_SCRIPT

    sudo chmod +x /usr/local/bin/rebuild-kde-rounded-corners.sh

    # --- Better Blur DX rebuild script ---
    sudo tee /usr/local/bin/rebuild-better-blur-dx.sh > /dev/null <<'REBUILD_BLUR'
#!/usr/bin/env bash
set -euo pipefail
LOG_FILE="/var/log/better-blur-dx-rebuild.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "=== Better Blur DX Rebuild Started ==="

TMP_DIR="$(mktemp -d)"
cd "$TMP_DIR"

log "Cloning repository..."
if git clone "https://github.com/xarblu/kwin-effects-better-blur-dx" better-blur-dx; then
    log "Repository cloned successfully"
else
    log "ERROR: Failed to clone repository"
    rm -rf "$TMP_DIR"
    exit 1
fi

cd better-blur-dx

log "Building Better Blur DX..."
if mkdir build && cd build; then
    if cmake .. -DCMAKE_INSTALL_PREFIX=/usr && make -j"$(nproc)"; then
        log "Build successful"

        log "Installing..."
        if make install; then
            log "Installation successful"
        else
            log "ERROR: Installation failed"
            cd ~
            rm -rf "$TMP_DIR"
            exit 1
        fi
    else
        log "ERROR: Build failed"
        cd ~
        rm -rf "$TMP_DIR"
        exit 1
    fi
else
    log "ERROR: Failed to create build directory"
    cd ~
    rm -rf "$TMP_DIR"
    exit 1
fi

cd ~
rm -rf "$TMP_DIR"

log "=== Better Blur DX Rebuild Completed Successfully ==="

if command -v qdbus6 >/dev/null 2>&1; then
    qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null || true
    log "KWin reconfigured"
fi

exit 0
REBUILD_BLUR

    sudo chmod +x /usr/local/bin/rebuild-better-blur-dx.sh

    # --- Log files ---
    sudo touch /var/log/kde-rounded-corners-rebuild.log
    sudo chmod 666 /var/log/kde-rounded-corners-rebuild.log
    sudo touch /var/log/better-blur-dx-rebuild.log
    sudo chmod 666 /var/log/better-blur-dx-rebuild.log

    # --- Combined rebuild wrapper (called by hooks) ---
    sudo tee /usr/local/bin/rebuild-kwin-effects.sh > /dev/null <<'WRAPPER'
#!/usr/bin/env bash
# Rebuild all KWin effects that need recompilation after kwin updates
/usr/local/bin/rebuild-kde-rounded-corners.sh
/usr/local/bin/rebuild-better-blur-dx.sh
WRAPPER

    sudo chmod +x /usr/local/bin/rebuild-kwin-effects.sh

    case "$DISTRO" in
        arch)
            log "installing pacman hook…"
            sudo mkdir -p /etc/pacman.d/hooks
            sudo tee /etc/pacman.d/hooks/kwin-effects-rebuild.hook > /dev/null <<'HOOK'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = kwin

[Action]
Description = Rebuilding KWin effects (Rounded Corners + Better Blur DX) after KWin update...
When = PostTransaction
Exec = /usr/local/bin/rebuild-kwin-effects.sh
Depends = kwin
HOOK
            ok "pacman hook installed → auto-rebuild enabled"
            ;;
        debian)
            log "creating apt hook…"

            sudo tee /usr/local/bin/check-and-rebuild-kwin-effects.sh > /dev/null <<'CHECKSCRIPT'
#!/usr/bin/env bash
# Only rebuild if kwin packages were updated in the current dpkg run
if tail -20 /var/log/dpkg.log 2>/dev/null | grep -qE " (upgrade|configure) kwin"; then
    /usr/local/bin/rebuild-kwin-effects.sh
fi
CHECKSCRIPT
            sudo chmod +x /usr/local/bin/check-and-rebuild-kwin-effects.sh

            sudo tee /etc/apt/apt.conf.d/99-kwin-effects-rebuild > /dev/null <<'APTHOOK'
DPkg::Post-Invoke { "/usr/local/bin/check-and-rebuild-kwin-effects.sh"; };
APTHOOK
            ok "apt hook installed → auto-rebuild on kwin updates"
            ;;
        fedora)
            log "creating dnf post-transaction hook…"

            sudo mkdir -p /etc/dnf/plugins/post-transaction-actions.d
            sudo tee /etc/dnf/plugins/post-transaction-actions.d/kwin-effects-rebuild.action > /dev/null <<'DNFHOOK'
kwin-wayland:any:install:/usr/local/bin/rebuild-kwin-effects.sh
kwin-wayland:any:update:/usr/local/bin/rebuild-kwin-effects.sh
DNFHOOK
            ok "dnf hook installed → auto-rebuild on kwin updates"
            ;;
    esac

    ok "auto-rebuild system configured"
}

install_kyanite() {
    log "deploying kyanite kwinscript…"
    local script="$REPO_DIR/kyanite.kwinscript"
    if [ ! -f "$script" ]; then
        warn "kyanite.kwinscript missing in repo"
        return
    fi
    if command -v kpackagetool6 >/dev/null 2>&1; then
        if kpackagetool6 --type KWin/Script --install "$script" 2>/dev/null; then
            ok "kyanite installed"
        elif kpackagetool6 --type KWin/Script --upgrade "$script" 2>/dev/null; then
            ok "kyanite upgraded"
        else
            warn "kpackagetool6 failed, using manual installation"
            local target="$HOME/.local/share/kwin/scripts/kyanite"
            rm -rf "$target"
            mkdir -p "$target"
            unzip -q "$script" -d "$target"
            ok "kyanite installed (manual) → $target"
        fi
    else
        warn "kpackagetool6 not found, using manual installation"
        local target="$HOME/.local/share/kwin/scripts/kyanite"
        rm -rf "$target"
        mkdir -p "$target"
        unzip -q "$script" -d "$target"
        ok "kyanite installed (manual) → $target"
    fi
}

deploy_tv_effect() {
    log "deploying TV [Burn-My-Windows] kwin effect…"
    local src="$REPO_DIR/kwin6_effect_tv"
    local dest="$HOME/.local/share/kwin/effects/kwin6_effect_tv"

    if [ ! -d "$src" ]; then
        warn "missing → kwin6_effect_tv (not found in repo)"
        return
    fi

    mkdir -p "$HOME/.local/share/kwin/effects"
    rm -rf "$dest"
    cp -r "$src" "$dest"
    ok "kwin effect → kwin6_effect_tv"
}

deploy_config_folders() {
    log "deploying configuration modules…"
    local folders=(btop kitty fastfetch cava)
    for f in "${folders[@]}"; do
        if [ -d "$REPO_DIR/$f" ]; then
            backup_file "$HOME/.config/$f"
            rm -rf "$HOME/.config/$f"
            cp -r "$REPO_DIR/$f" "$HOME/.config/$f"
            ok "config → $f"
        else
            warn "missing → $f"
        fi
    done
}

deploy_gtk4_config() {
    log "deploying gtk-4.0 configuration…"
    local src="$REPO_DIR/gtk-4.0"
    local dest="$HOME/.config/gtk-4.0"

    if [ ! -d "$src" ]; then
        warn "missing → gtk-4.0 (not found in repo)"
        return
    fi

    backup_file "$dest"
    rm -rf "$dest"
    cp -r "$src" "$dest"
    ok "config → gtk-4.0"
}

deploy_rc_files() {
    log "deploying plasma rc files…"
    local rc_files=(
        kwinrc
        plasmarc
        plasma-org.kde.plasma.desktop-appletsrc
        breezerc
    )
    for rc in "${rc_files[@]}"; do
        if [ -f "$REPO_DIR/$rc" ]; then
            backup_file "$HOME/.config/$rc"
            cp "$REPO_DIR/$rc" "$HOME/.config/$rc"
            ok "rc → $rc"
        else
            warn "missing → $rc"
        fi
    done
}

deploy_kwinrules() {
    log "deploying kwinrulesrc…"
    local file="kwinrulesrc"
    if [ -f "$REPO_DIR/$file" ]; then
        backup_file "$HOME/.config/$file"
        cp "$REPO_DIR/$file" "$HOME/.config/$file"
        ok "rules → $file"
    else
        warn "missing → $file"
    fi
}

patch_appletsrc_activity_id() {
    log "patching desktop activity ID in appletsrc…"
    local appletsrc="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"

    if [ ! -f "$appletsrc" ]; then
        warn "appletsrc not found, skipping activity ID patch"
        return
    fi

    # Get the real activity ID from the running activity manager
    local real_activity_id=""

    if command -v qdbus6 >/dev/null 2>&1; then
        real_activity_id=$(qdbus6 org.kde.ActivityManager /ActivityManager/Activities ListActivities 2>/dev/null | head -1) || true
    fi

    # Fallback: read from the backup of the original appletsrc
    if [ -z "$real_activity_id" ] && [ -f "$BACKUP_DIR/plasma-org.kde.plasma.desktop-appletsrc" ]; then
        real_activity_id=$(grep -oP 'activityId=\K[0-9a-f-]{36}' "$BACKUP_DIR/plasma-org.kde.plasma.desktop-appletsrc" 2>/dev/null | head -1) || true
    fi

    if [ -z "$real_activity_id" ]; then
        warn "could not determine system activity ID — wallpaper containment may not bind"
        return
    fi

    if [ "$real_activity_id" = "$REPO_ACTIVITY_ID" ]; then
        ok "activity ID already matches ($real_activity_id)"
        return
    fi

    # Replace the hardcoded repo activity ID with the real one
    sed -i "s|$REPO_ACTIVITY_ID|$real_activity_id|g" "$appletsrc"
    ok "activity ID patched → $real_activity_id"
}

apply_wallpaper_fallback() {
    log "applying wallpaper via plasma-apply-wallpaperimage…"
    if [ ! -f "$WALLPAPER_PATH" ]; then
        warn "wallpaper not found at $WALLPAPER_PATH"
        return
    fi
    if command -v plasma-apply-wallpaperimage >/dev/null 2>&1; then
        sleep 2
        plasma-apply-wallpaperimage "$WALLPAPER_PATH" 2>/dev/null && \
            ok "wallpaper applied → $WALLPAPER_PATH" || \
            warn "plasma-apply-wallpaperimage failed (activity ID patch should handle it)"
    else
        warn "plasma-apply-wallpaperimage not found"
    fi
}

deploy_yamis_icons() {
    log "installing YAMIS icon theme…"
    mkdir -p "$HOME/.local/share/icons"
    local yamis_zip="$REPO_DIR/YAMIS.zip"
    local yamis_dest="$HOME/.local/share/icons"
    if [ -f "$yamis_zip" ]; then
        [ -d "$yamis_dest/YAMIS" ] && rm -rf "$yamis_dest/YAMIS"
        unzip -q "$yamis_zip" -d "$yamis_dest"
        ok "icons → YAMIS"
    else
        warn "YAMIS.zip not found at $yamis_zip"
    fi
}

deploy_modernclock() {
    log "installing Modern Clock widget…"
    mkdir -p "$HOME/.local/share/plasma/plasmoids"
    local clock_source="$REPO_DIR/com.github.prayag2.modernclock"
    local clock_dest="$HOME/.local/share/plasma/plasmoids/com.github.prayag2.modernclock"
    if [ -d "$clock_source" ]; then
        [ -d "$clock_dest" ] && rm -rf "$clock_dest"
        cp -r "$clock_source" "$clock_dest"
        ok "widget → Modern Clock"
    else
        warn "Modern Clock folder not found at $clock_source"
    fi
}

deploy_color_scheme() {
    log "installing CyberXero color scheme…"
    mkdir -p "$HOME/.local/share/color-schemes"
    if [ -f "$REPO_DIR/CyberXero.colors" ]; then
        cp "$REPO_DIR/CyberXero.colors" "$HOME/.local/share/color-schemes/"
        ok "colors → CyberXero"
    else
        warn "CyberXero.colors missing"
    fi
}

deploy_wallpapers() {
    log "deploying wallpapers…"
    sudo mkdir -p /usr/local/share/icons

    if [ -f "$REPO_DIR/cyberfield.jpg" ]; then
        sudo cp "$REPO_DIR/cyberfield.jpg" /usr/local/share/icons/
        ok "wallpaper → cyberfield.jpg → /usr/local/share/icons"
    else
        warn "missing → cyberfield.jpg"
    fi

    if [ -f "$REPO_DIR/cyberxero2.png" ]; then
        sudo cp "$REPO_DIR/cyberxero2.png" /usr/local/share/icons/
        ok "icon → cyberxero2.png → /usr/local/share/icons"
    else
        warn "missing → cyberxero2.png"
    fi

    mkdir -p "$HOME/Pictures"
    if [ -f "$REPO_DIR/cyberxero.png" ]; then
        cp "$REPO_DIR/cyberxero.png" "$HOME/Pictures/"
        ok "wallpaper → cyberxero.png → ~/Pictures"
    else
        warn "missing → cyberxero.png"
    fi
}

apply_breeze_decoration() {
    log "configuring Breeze window decoration…"
    if command -v kwriteconfig6 >/dev/null 2>&1; then
        local current_decoration
        current_decoration=$(kreadconfig6 --file kwinrc --group org.kde.kdecoration2 --key library 2>/dev/null || echo "")

        if [ "$current_decoration" != "org.kde.breeze" ]; then
            kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key library "org.kde.breeze"
            kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key theme "Breeze"
            ok "decoration → Breeze (changed from ${current_decoration:-none})"
        else
            ok "decoration → Breeze (already active)"
        fi
    else
        warn "kwriteconfig6 not found, cannot set decoration"
    fi
}

apply_kde_theme_settings() {
    log "activating neon theme parameters…"

    if command -v plasma-apply-colorscheme >/dev/null 2>&1; then
        plasma-apply-colorscheme CyberXero 2>/dev/null || true
        ok "color scheme activated → CyberXero"
    else
        warn "plasma-apply-colorscheme not found"
    fi

    if command -v kwriteconfig6 >/dev/null 2>&1; then
        # Set custom accent color (#fa1bf8)
        kwriteconfig6 --file kdeglobals --group General --key AccentColor "250,27,248"
        kwriteconfig6 --file kdeglobals --group General --key ColorSchemeHash ""
        ok "accent color → #fa1bf8"

        kwriteconfig6 --file kdeglobals --group Icons --key Theme "YAMIS"
        ok "icon theme activated → YAMIS"

        kwriteconfig6 --file kwinrc --group Plugins --key krohnkiteEnabled true
        ok "krohnkite enabled"

        kwriteconfig6 --file kwinrc --group Plugins --key kyaniteEnabled true
        ok "kyanite enabled"
    else
        warn "kwriteconfig6 not found"
    fi

    apply_breeze_decoration
}

main() {
    printf "\n\033[1;35m┌───────────────────────────────────────────────────────┐\n"
    printf   "│  CYBERXERO DYNAMIC TILING THEME BY MURDERFROMMARS  │\n"
    printf   "└───────────────────────────────────────────────────────┘\033[0m\n\n"

    section "PHASE 1: SYSTEM PREPARATION"
    fetch_repo
    detect_distro
    install_dependencies

    section "PHASE 2: BUILDING CORE COMPONENTS"
    subsection "Window Manager Extensions"
    build_panel_colorizer
    build_kurve
    build_kde_rounded_corners
    build_better_blur
    setup_autorebuild_system

    subsection "KWin Scripts"
    install_krohnkite
    install_kyanite
    deploy_tv_effect

    section "PHASE 3: THEME DEPLOYMENT"

    subsection "Panel Cleanup & Shell Shutdown"
    purge_old_panels_live
    stop_plasmashell

    subsection "Visual Assets"
    deploy_yamis_icons
    deploy_modernclock
    deploy_color_scheme
    deploy_wallpapers

    subsection "Configuration Files"
    deploy_config_folders
    deploy_gtk4_config
    deploy_rc_files
    deploy_kwinrules
    patch_appletsrc_activity_id

    subsection "Theme Activation"
    apply_kde_theme_settings

    subsection "Restarting Plasma Shell"
    start_plasmashell

    # Reconfigure KWin after shell is back
    if command -v qdbus6 >/dev/null 2>&1; then
        qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null || true
        ok "KWin reconfigured"
    fi

    # Belt-and-suspenders: also set wallpaper via CLI tool
    apply_wallpaper_fallback

    printf "\n\033[1;35m╔═══════════════════════════════════════════════════════╗\033[0m\n"
    printf "\033[1;35m║\033[0m  \033[1;32mCYBERXERO DEPLOYMENT COMPLETE\033[0m                    \033[1;35m║\033[0m\n"
    printf "\033[1;35m╚═══════════════════════════════════════════════════════╝\033[0m\n\n"
    printf "\033[1;36m📦 Backup archive:\033[0m %s\n" "$BACKUP_DIR"
    printf "\033[1;36m📋 Auto-rebuild logs:\033[0m /var/log/kde-rounded-corners-rebuild.log\n"
    printf "\033[1;36m📋 Auto-rebuild logs:\033[0m /var/log/better-blur-dx-rebuild.log\n\n"
    printf "\033[1;33m╔═══════════════════════════════════════════════════════╗\033[0m\n"
    printf "\033[1;33m║  ℹ️  Plasma shell has been restarted with new config.  ║\033[0m\n"
    printf "\033[1;33m║     If anything looks off, a full re-login will fix   ║\033[0m\n"
    printf "\033[1;33m║     any remaining state issues.                       ║\033[0m\n"
    printf "\033[1;33m╚═══════════════════════════════════════════════════════╝\033[0m\n\n"
}

main "$@"
