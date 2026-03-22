#!/bin/sh
# Copyright (C) 2026 Ragnar
# SPDX-License-Identifier: GPL-3.0-only
set -eu

# =========================
# Global configuration
# =========================

OMZ_REPO="https://github.com/ohmyzsh/ohmyzsh.git"
FILES_RAW_BASE="https://raw.githubusercontent.com/blackden/home_stuff/master"

DRY_RUN=0
SKIP_SHELL=0
INTERACTIVE=0
ASSUME_YES=0
MODE="minimal"   # minimal | all | omz-only | dotfiles-only
TARGET_USERS=""
ACK_ROOT_DANGER=0
ENABLE_WHEEL_SUDO=0
USED_SUDO=0

CURRENT_USER="$(id -un)"
OS=""
PKG_MANAGER=""
SUDO_CMD=""

# =========================
# Common helpers
# =========================

log() {
    printf '%s\n' "==> $*"
}

warn() {
    printf '%s\n' "WARN: $*" >&2
}

die() {
    printf '%s\n' "ERROR: $*" >&2
    exit 1
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1
}

run_cmd() {
    if [ "$DRY_RUN" -eq 1 ]; then
        printf '%s\n' "[dry-run] $*"
    else
        "$@"
    fi
}

is_root() {
    [ "$(id -u)" -eq 0 ]
}

prompt_yes_no_default_no() {
    prompt="$1"

    if [ "$ASSUME_YES" -eq 1 ]; then
        return 0
    fi

    printf '%s [y/N]: ' "$prompt" >&2
    read -r answer || true
    case "${answer:-N}" in
        y|Y|yes|YES)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

dedupe_words() {
    printf '%s\n' "$*" | awk '{for (i=1; i<=NF; i++) print $i}' | awk '!seen[$0]++'
}

# =========================
# Privilege handling
# =========================

cleanup() {
    if [ "$DRY_RUN" -eq 1 ]; then
        return 0
    fi

    if ! is_root && [ "${USED_SUDO:-0}" -eq 1 ] && need_cmd sudo; then
        sudo -k >/dev/null 2>&1 || true
    fi
}

setup_escalation() {
    if is_root; then
        SUDO_CMD=""
        return 0
    fi

    if need_cmd sudo; then
        SUDO_CMD="sudo"
        return 0
    fi

    SUDO_CMD=""
}

validate_sudo() {
    if is_root; then
        return 0
    fi

    if [ -n "$SUDO_CMD" ]; then
        log "requesting sudo access"
        if [ "$DRY_RUN" -eq 1 ]; then
            printf '%s\n' "[dry-run] sudo -v"
            return 0
        fi

        if sudo -v; then
            USED_SUDO=1
            return 0
        fi

        die "sudo authentication failed or user '$CURRENT_USER' is not allowed to use sudo"
    fi

    die "root privileges are required. Re-run the script as root."
}

run_as_root() {
    if is_root; then
        run_cmd "$@"
        return 0
    fi

    if [ -n "$SUDO_CMD" ]; then
        validate_sudo
        if [ "$DRY_RUN" -eq 1 ]; then
            printf '%s\n' "[dry-run] sudo $*"
        else
            sudo "$@"
        fi
        return 0
    fi

    die "need root privileges for: $*"
}

# =========================
# OS detection
# =========================

detect_os() {
    case "$(uname -s)" in
        Darwin)
            OS="macos"
            PKG_MANAGER="brew"
            ;;
        Linux)
            if [ -r /etc/os-release ]; then
                . /etc/os-release
                case "${ID:-linux}" in
                    alpine)
                        OS="alpine"
                        PKG_MANAGER="apk"
                        ;;
                    ubuntu|debian)
                        OS="${ID}"
                        PKG_MANAGER="apt"
                        ;;
                    *)
                        OS="${ID:-linux}"
                        PKG_MANAGER=""
                        ;;
                esac
            else
                OS="linux"
                PKG_MANAGER=""
            fi
            ;;
        *)
            OS="unknown"
            PKG_MANAGER=""
            ;;
    esac
}

# =========================
# Root safety rules
# =========================

is_wheel_sudo_only() {
    [ "$ENABLE_WHEEL_SUDO" -eq 1 ] &&
    [ -z "$TARGET_USERS" ] &&
    [ "$MODE" = "minimal" ] &&
    [ "$INTERACTIVE" -eq 0 ] &&
    [ "$SKIP_SHELL" -eq 0 ]
}

require_explicit_root_ack() {
    if ! is_root; then
        return 0
    fi

    [ "$ACK_ROOT_DANGER" -eq 1 ] || die "running as root requires --i-know-what-im-doing"

    if is_wheel_sudo_only; then
        return 0
    fi

    [ -n "$TARGET_USERS" ] || die "running as root requires --users. Example: --users root or --users ragnar"
}

# =========================
# OS-specific: Alpine
# =========================

alpine_map_missing_packages() {
    mapped=""

    for pkg in "$@"; do
        case "$pkg" in
            chsh)
                mapped="$mapped shadow"
                ;;
            visudo)
                mapped="$mapped sudo"
                ;;
            *)
                mapped="$mapped $pkg"
                ;;
        esac
    done

    dedupe_words "$mapped"
}

alpine_install_missing_packages() {
    missing="$1"
    mapped="$(alpine_map_missing_packages $missing)"

    run_as_root apk update
    run_as_root apk add $mapped ca-certificates sudo
}

alpine_enable_wheel_sudo() {
    need_cmd visudo || die "visudo is required to validate sudoers configuration"

    log "enabling sudo for wheel via /etc/sudoers.d/wheel"

    if [ "$DRY_RUN" -eq 1 ]; then
        printf '%s\n' "[dry-run] mkdir -p /etc/sudoers.d"
        printf '%s\n' "[dry-run] write /etc/sudoers.d/wheel"
        printf '%s\n' "[dry-run] chmod 0440 /etc/sudoers.d/wheel"
        printf '%s\n' "[dry-run] visudo -c"
        return 0
    fi

    run_as_root mkdir -p /etc/sudoers.d
    printf '%%wheel ALL=(ALL:ALL) ALL\n' | run_as_root tee /etc/sudoers.d/wheel >/dev/null
    run_as_root chmod 0440 /etc/sudoers.d/wheel
    run_as_root visudo -c
}

# =========================
# OS-specific: Debian/Ubuntu
# =========================

deb_map_missing_packages() {
    mapped=""

    for pkg in "$@"; do
        case "$pkg" in
            chsh)
                mapped="$mapped passwd"
                ;;
            visudo)
                mapped="$mapped sudo"
                ;;
            *)
                mapped="$mapped $pkg"
                ;;
        esac
    done

    dedupe_words "$mapped"
}

deb_install_missing_packages() {
    missing="$1"
    mapped="$(deb_map_missing_packages $missing)"

    run_as_root apt update
    run_as_root apt install -y $mapped ca-certificates sudo
}

deb_enable_wheel_sudo() {
    need_cmd visudo || die "visudo is required to validate sudoers configuration"

    log "enabling sudo for wheel via /etc/sudoers.d/wheel"

    if [ "$DRY_RUN" -eq 1 ]; then
        printf '%s\n' "[dry-run] mkdir -p /etc/sudoers.d"
        printf '%s\n' "[dry-run] write /etc/sudoers.d/wheel"
        printf '%s\n' "[dry-run] chmod 0440 /etc/sudoers.d/wheel"
        printf '%s\n' "[dry-run] visudo -c"
        return 0
    fi

    run_as_root mkdir -p /etc/sudoers.d
    printf '%%wheel ALL=(ALL:ALL) ALL\n' | run_as_root tee /etc/sudoers.d/wheel >/dev/null
    run_as_root chmod 0440 /etc/sudoers.d/wheel
    run_as_root visudo -c
}

# =========================
# OS-specific: macOS
# =========================

macos_map_missing_packages() {
    dedupe_words "$@"
}

macos_install_missing_packages() {
    missing="$1"
    mapped="$(macos_map_missing_packages $missing)"

    run_cmd brew update
    run_cmd brew install $mapped
}

macos_enable_wheel_sudo() {
    die "--enable-wheel-sudo is not implemented for macOS"
}

# =========================
# OS-specific dispatchers
# =========================

install_missing_packages() {
    missing="$1"
    [ -n "$missing" ] || return 0

    case "$OS" in
        alpine)
            alpine_install_missing_packages "$missing"
            ;;
        ubuntu|debian)
            deb_install_missing_packages "$missing"
            ;;
        macos)
            macos_install_missing_packages "$missing"
            ;;
        *)
            die "unsupported OS/package manager for auto-install: $OS"
            ;;
    esac
}

enable_wheel_sudo() {
    case "$OS" in
        alpine)
            alpine_enable_wheel_sudo
            ;;
        ubuntu|debian)
            deb_enable_wheel_sudo
            ;;
        macos)
            macos_enable_wheel_sudo
            ;;
        *)
            die "--enable-wheel-sudo is unsupported on OS: $OS"
            ;;
    esac
}

# =========================
# User and file operations
# =========================

user_exists() {
    username="$1"
    awk -F: -v u="$username" '$1 == u {found=1} END {exit !found}' /etc/passwd
}

user_home() {
    username="$1"
    if [ "$username" = "root" ]; then
        printf '%s\n' "/root"
        return 0
    fi

    home_dir="$(awk -F: -v u="$username" '$1 == u {print $6}' /etc/passwd)"
    [ -n "$home_dir" ] || die "cannot determine home for user: $username"
    printf '%s\n' "$home_dir"
}

user_shell() {
    username="$1"
    awk -F: -v u="$username" '$1 == u {print $7}' /etc/passwd
}

ensure_home_exists() {
    home_dir="$1"
    [ -d "$home_dir" ] || die "home directory does not exist: $home_dir"
}

primary_group_for_user() {
    username="$1"
    id -gn "$username" 2>/dev/null || printf '%s\n' "$username"
}

chown_if_needed() {
    username="$1"
    target="$2"

    if [ "$username" = "root" ]; then
        return 0
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        printf '%s\n' "[dry-run] chown $username:$username $target"
        return 0
    fi

    group_name="$(primary_group_for_user "$username")"
    run_as_root chown "$username:$group_name" "$target" 2>/dev/null || run_as_root chown "$username" "$target" 2>/dev/null || true
}

backup_file_for_user() {
    file="$1"
    backup="$file.bak"

    if [ -f "$file" ] && [ ! -f "$backup" ]; then
        log "creating backup: $backup"
        run_cmd cp -a "$file" "$backup"
    fi
}

check_remote_file() {
    remote_name="$1"
    url="$FILES_RAW_BASE/$remote_name"

    if [ "$DRY_RUN" -eq 1 ]; then
        printf '%s\n' "[dry-run] curl -fsSLI $url"
        return 0
    fi

    curl -fsSLI "$url" >/dev/null 2>&1 || die "remote file is not accessible: $url"
}

download_file() {
    remote_name="$1"
    local_path="$2"

    log "downloading $remote_name -> $local_path"
    if [ "$DRY_RUN" -eq 1 ]; then
        printf '%s\n' "[dry-run] curl -fsSL $FILES_RAW_BASE/$remote_name -o $local_path"
    else
        curl -fsSL "$FILES_RAW_BASE/$remote_name" -o "$local_path"
    fi
}

ensure_shell_in_etc_shells() {
    shell_path="$1"

    [ -n "$shell_path" ] || die "empty shell path"

    if [ "$DRY_RUN" -eq 1 ]; then
        printf '%s\n' "[dry-run] ensure $shell_path exists in /etc/shells"
        return 0
    fi

    if [ ! -f /etc/shells ]; then
        printf '%s\n' "$shell_path" | run_as_root tee /etc/shells >/dev/null
        return 0
    fi

    if ! grep -Fxq "$shell_path" /etc/shells; then
        printf '%s\n' "$shell_path" | run_as_root tee -a /etc/shells >/dev/null
    fi
}

# =========================
# Requirement resolution
# =========================

required_commands_for_mode() {
    req=""

    if [ "$ENABLE_WHEEL_SUDO" -eq 1 ]; then
        req="$req visudo"
    fi

    case "$MODE" in
        minimal|omz-only|all)
            req="$req git zsh chsh"
            ;;
    esac

    case "$MODE" in
        all|dotfiles-only)
            req="$req curl vim"
            ;;
    esac

    dedupe_words "$req"
}

find_missing_commands() {
    missing=""

    for cmd in $(required_commands_for_mode); do
        if ! need_cmd "$cmd"; then
            missing="$missing $cmd"
        fi
    done

    printf '%s\n' "$missing" | awk '{$1=$1; print}'
}

ensure_required_tools() {
    missing="$(find_missing_commands)"
    [ -n "$missing" ] || return 0

    warn "missing required commands: $missing"

    if is_root || [ -n "$SUDO_CMD" ] || [ "$PKG_MANAGER" = "brew" ]; then
        if prompt_yes_no_default_no "Install missing packages now?"; then
            install_missing_packages "$missing"
        else
            die "required commands are missing: $missing"
        fi
    else
        die "required commands are missing: $missing. Re-run the script as root."
    fi
}

# =========================
# Install actions
# =========================

install_ohmyzsh_for_user() {
    username="$1"
    home_dir="$2"
    omz_dir="$home_dir/.oh-my-zsh"

    if [ -d "$omz_dir" ]; then
        log "oh-my-zsh already installed for $username"
        return 0
    fi

    log "installing oh-my-zsh for $username"

    if [ "$username" = "$CURRENT_USER" ] && ! is_root; then
        run_cmd git clone "$OMZ_REPO" "$omz_dir"
    else
        if [ "$DRY_RUN" -eq 1 ]; then
            validate_sudo
            printf '%s\n' "[dry-run] git clone $OMZ_REPO $omz_dir"
            printf '%s\n' "[dry-run] chown -R $username $omz_dir"
        else
            run_as_root git clone "$OMZ_REPO" "$omz_dir"
            run_as_root chown -R "$username:$(primary_group_for_user "$username")" "$omz_dir" 2>/dev/null || run_as_root chown -R "$username" "$omz_dir"
        fi
    fi
}

set_login_shell_for_user() {
    username="$1"

    [ "$SKIP_SHELL" -eq 0 ] || return 0

    zsh_path="$(command -v zsh || true)"
    [ -n "$zsh_path" ] || die "zsh not found in PATH"

    ensure_shell_in_etc_shells "$zsh_path"

    current_shell="$(user_shell "$username")"
    if [ "$current_shell" = "$zsh_path" ]; then
        log "login shell already set to $zsh_path for $username"
        return 0
    fi

    log "changing login shell to $zsh_path for $username"
    run_as_root chsh -s "$zsh_path" "$username"
}

install_dotfiles_for_user() {
    username="$1"
    home_dir="$(user_home "$username")"

    backup_file_for_user "$home_dir/.zshrc"
    backup_file_for_user "$home_dir/.vimrc"

    download_file ".zshrc" "$home_dir/.zshrc"
    download_file ".vimrc" "$home_dir/.vimrc"

    chown_if_needed "$username" "$home_dir/.zshrc"
    chown_if_needed "$username" "$home_dir/.vimrc"
}

should_install_dotfiles_for_user() {
    case "$MODE" in
        all|dotfiles-only)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

install_for_user() {
    username="$1"
    user_exists "$username" || die "user does not exist: $username"

    home_dir="$(user_home "$username")"
    ensure_home_exists "$home_dir"

    case "$MODE" in
        minimal|omz-only|all)
            install_ohmyzsh_for_user "$username" "$home_dir"
            set_login_shell_for_user "$username"
            ;;
    esac

    if should_install_dotfiles_for_user "$username"; then
        install_dotfiles_for_user "$username"
    fi
}

# =========================
# Target resolution
# =========================

parse_users_csv() {
    csv="$1"
    old_ifs="$IFS"
    IFS=','
    set -- $csv
    IFS="$old_ifs"

    for u in "$@"; do
        [ -n "$u" ] || continue
        printf '%s\n' "$u"
    done
}

resolve_target_users() {
    if [ -n "$TARGET_USERS" ]; then
        parse_users_csv "$TARGET_USERS"
        return 0
    fi

    printf '%s\n' "$CURRENT_USER"
}

# =========================
# CLI
# =========================

choose_mode_interactive() {
    printf '%s\n' "Select mode:"
    printf '%s\n' "  1) minimal       - zsh + oh-my-zsh + set login shell"
    printf '%s\n' "  2) all           - minimal + .zshrc + .vimrc"
    printf '%s\n' "  3) omz-only      - install oh-my-zsh + set login shell"
    printf '%s\n' "  4) dotfiles-only - install .zshrc + .vimrc"
    printf '%s' "Choice [1]: "
    read -r choice || true

    case "${choice:-1}" in
        1) MODE="minimal" ;;
        2) MODE="all" ;;
        3) MODE="omz-only" ;;
        4) MODE="dotfiles-only" ;;
        *) die "invalid mode choice" ;;
    esac
}

usage() {
    cat <<'EOF'
Usage:
  install.sh [options]

Modes:
  --all                 install everything: oh-my-zsh + shell + .zshrc + .vimrc
  --omz-only            install only oh-my-zsh + shell
  --dotfiles-only       install only .zshrc + .vimrc

Target selection:
  --users u1,u2         explicit target users

Safety:
  --i-know-what-im-doing
                        mandatory for any run as root

Standalone action:
  --enable-wheel-sudo   configure %wheel sudo via /etc/sudoers.d/wheel

Other options:
  --interactive         choose mode interactively
  --skip-shell          do not change login shell to zsh
  --dry-run             print actions without changing anything
  --yes                 assume yes for package installation prompts
  -h, --help            show this help

Default behavior:
  Without mode flags the script runs in "minimal" mode.

Important:
  - Dotfiles are applied only to explicitly targeted users.
  - If the script is run as root, --i-know-what-im-doing is mandatory.
  - For normal install actions run as root, --users is also mandatory.
  - For standalone --enable-wheel-sudo, --users is not required.
EOF
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --all)
                MODE="all"
                ;;
            --omz-only)
                MODE="omz-only"
                ;;
            --dotfiles-only)
                MODE="dotfiles-only"
                ;;
            --users)
                shift
                [ $# -gt 0 ] || die "--users requires a comma-separated value"
                TARGET_USERS="$1"
                ;;
            --i-know-what-im-doing)
                ACK_ROOT_DANGER=1
                ;;
            --interactive)
                INTERACTIVE=1
                ;;
            --skip-shell)
                SKIP_SHELL=1
                ;;
            --dry-run)
                DRY_RUN=1
                ;;
            --yes)
                ASSUME_YES=1
                ;;
            --enable-wheel-sudo)
                ENABLE_WHEEL_SUDO=1
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                die "unknown option: $1"
                ;;
        esac
        shift
    done
}

validate_args() {
    if [ "$INTERACTIVE" -eq 1 ]; then
        choose_mode_interactive
    fi
}

preflight_checks() {
    detect_os
    setup_escalation

    [ "$OS" != "unknown" ] || die "unsupported OS"
    [ -n "$PKG_MANAGER" ] || [ "$OS" = "macos" ] || die "unsupported package manager for OS: $OS"

    ensure_required_tools

    if [ "$MODE" = "all" ] || [ "$MODE" = "dotfiles-only" ]; then
        log "checking remote dotfiles availability"
        check_remote_file ".zshrc"
        check_remote_file ".vimrc"
    fi
}

main() {
    parse_args "$@"
    validate_args
    require_explicit_root_ack
    preflight_checks

    if [ "$ENABLE_WHEEL_SUDO" -eq 1 ]; then
        enable_wheel_sudo
    fi

    if is_wheel_sudo_only; then
        log "done"
        exit 0
    fi

    log "mode: $MODE"

    for username in $(resolve_target_users); do
        install_for_user "$username"
    done

    log "done"
    log "re-login to apply the new shell"
}

trap cleanup EXIT INT TERM
main "$@"
