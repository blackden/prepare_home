# prepare_home

Bootstrap installer for shell environment setup.

## Quick start

Minimal mode:

```sh
curl -fsSL https://raw.githubusercontent.com/blackden/prepare_home/master/install.sh | sh
```

Full mode:

```sh
curl -fsSL https://raw.githubusercontent.com/blackden/prepare_home/master/install.sh | sh -s -- --all
```

## Modes

- default: `minimal` — install zsh, oh-my-zsh, set login shell
- `--all` — minimal + `.zshrc` + `.vimrc`
- `--omz-only` — install only oh-my-zsh + shell
- `--dotfiles-only` — install only `.zshrc` + `.vimrc`

## Extra options

- `--users user1,user2`
- `--enable-wheel-sudo`
- `--dry-run`
- `--yes`
- `--skip-shell`
- `--interactive`

## Root safety

When running as root:

- `--i-know-what-im-doing` is required
- `--users` is required for normal install actions

## Examples

Install minimal setup for current user:

```sh
sh install.sh
```

Install full setup for current user:

```sh
sh install.sh --all
```

Enable sudo for wheel:

```sh
sudo sh install.sh --enable-wheel-sudo --i-know-what-im-doing
```

## License

Copyright (C) 2026 Ragnar (blackden, ragnar.black)

Licensed under the GNU General Public License v3.0 only.
See [`LICENSE`](LICENSE) for the full text.
