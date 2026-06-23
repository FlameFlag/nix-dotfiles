# nix-dotfiles 🌸

Personal NixOS, nix-darwin, Ansible, chezmoi, and Bluefin setup

<p>
  <a href="https://projectbluefin.io"><img alt="Bluefin" src="https://img.shields.io/badge/Bluefin-f4b8e4?style=flat-square&logo=fedora&logoColor=f4b8e4&labelColor=232634"></a>
  <a href="https://nixos.org"><img alt="NixOS" src="https://img.shields.io/badge/NixOS-f4b8e4?style=flat-square&logo=nixos&logoColor=f4b8e4&labelColor=232634"></a>
  <a href="https://github.com/nix-darwin/nix-darwin"><img alt="nix-darwin" src="https://img.shields.io/badge/nix--darwin-f4b8e4?style=flat-square&logo=apple&logoColor=f4b8e4&labelColor=232634"></a>
  <a href="https://www.chezmoi.io"><img alt="chezmoi" src="https://img.shields.io/badge/chezmoi-f4b8e4?style=flat-square&logo=homeassistant&logoColor=f4b8e4&labelColor=232634"></a>
  <a href="https://www.ansible.com"><img alt="Ansible" src="https://img.shields.io/badge/Ansible-f4b8e4?style=flat-square&logo=ansible&logoColor=f4b8e4&labelColor=232634"></a>
  <a href="https://catppuccin.com"><img alt="Catppuccin Latte and Frappe" src="https://img.shields.io/badge/Catppuccin-Latte%20%2B%20Frapp%C3%A9-f4b8e4?style=flat-square&labelColor=ea76cb"></a>
</p>

> [!IMPORTANT]
> This is my personal setup

## Bootstrap

```bash
git clone https://github.com/FlameFlag/nix-dotfiles.git ~/nix-dotfiles
cd ~/nix-dotfiles
```

## Install

### NixOS

```bash
sudo nixos-generate-config --show-hardware-config > hosts/linux/hardware-configuration.nix
sudo nixos-rebuild switch --flake .#lenovo-legion
nix run .#immutable-activate -- --backend auto --flake "$PWD" --reset-containers

chezmoi init --source "$PWD/dotfiles"
chezmoi apply --refresh-externals=always --force
```

### macOS

```bash
nix run nix-darwin -- switch --flake .#FlameFlags-Mac-mini
sudo darwin-rebuild switch --flake .#FlameFlags-Mac-mini
ansible-playbook ansible/playbooks/userland.yml

chezmoi init --source "$PWD/dotfiles"
chezmoi apply --refresh-externals=always --force
```

### Portable Linux

```bash
./ansible/bootstrap.sh
env CGO_ENABLED=0 go run ./cmd/immutable-activate --backend auto --flake "$PWD" --reset-containers

chezmoi init --source "$PWD/dotfiles"
chezmoi apply --refresh-externals=always --force
```

Host bits:

```bash
ansible-playbook ansible/playbooks/host.yml
```

### Spectrum / Bluefin

Spectrum is the Bluefin host path: bootc image first, userland after reboot.

Published image:

```bash
sudo bootc switch ghcr.io/flameflag/nix-dotfiles-bluefin:latest
systemctl reboot
```

After reboot:

```bash
git clone https://github.com/FlameFlag/nix-dotfiles.git ~/nix-dotfiles
cd ~/nix-dotfiles

env CGO_ENABLED=0 go run ./cmd/immutable-activate --backend auto --flake "$PWD" --reset-containers

chezmoi init --source "$PWD/dotfiles"
chezmoi apply --refresh-externals=always --force

ansible-playbook ansible/playbooks/host.yml
```

Local image instead of GHCR:

```bash
sudo podman build --pull=newer --tag localhost/nix-dotfiles-bluefin:local --file spectrum/Containerfile .
sudo bootc switch --transport containers-storage localhost/nix-dotfiles-bluefin:local
systemctl reboot
```

After changing `spectrum/` or anything copied by `spectrum/Containerfile`, rebuild the same local tag and upgrade into it:

```bash
sudo podman build --pull=newer --tag localhost/nix-dotfiles-bluefin:local --file spectrum/Containerfile .
sudo bootc upgrade
systemctl reboot
```

Use `bootc switch` when changing to a different image reference, such as first moving from stock Bluefin to Spectrum or moving from the local image to GHCR. Use `bootc upgrade` after rebuilding or republishing the image reference that the machine already tracks.

UBlue automatic updates do not run Ansible. Use `update` for userland, and run `ansible-playbook ansible/playbooks/host.yml` for host bits.

## Daily

```bash
update
rebuild
check
cza
```

## Check

```bash
nix fmt
nix flake check

ansible-playbook --syntax-check ansible/playbooks/bootstrap.yml
ansible-playbook --syntax-check ansible/playbooks/userland.yml
ansible-playbook --syntax-check ansible/playbooks/host.yml
ansible-playbook --syntax-check ansible/playbooks/site.yml

ansible-lint ansible
yamllint .

docker compose build
docker compose run --rm alpine
docker compose run --rm fedora-44
docker compose --profile nix-profile build nix-profile
docker compose --profile nix-profile run --rm nix-profile
```

## License

[LICENSE.txt](LICENSE.txt)
