# shellcheck shell=bash

host_user=${1:?host user is required}
kanata_config=${2:?kanata config path is required}
uinput_rules=${3:?uinput rules path is required}
kanata_unit=${4:?kanata unit path is required}

ensure_group() {
  local group_name=${1:?group name is required}

  if grep -q "^$group_name:" /etc/group 2>/dev/null; then
    return
  fi
  if [[ -f /usr/lib/group ]] && grep -q "^$group_name:" /usr/lib/group; then
    grep -E "^$group_name:" /usr/lib/group >>/etc/group
    return
  fi
  groupadd --system "$group_name"
}

install -d -m 0755 /etc/kanata /etc/modules-load.d /etc/udev/rules.d /etc/systemd/system
install -m 0644 "$kanata_config" /etc/kanata/kanata.kbd

ensure_group input
ensure_group uinput
usermod -aG input,uinput "$host_user"

printf "%s\n" uinput >/etc/modules-load.d/uinput.conf
install -m 0644 "$uinput_rules" /etc/udev/rules.d/70-nix-dotfiles-uinput.rules
install -m 0644 "$kanata_unit" /etc/systemd/system/kanata-main.service

modprobe uinput || true
udevadm control --reload-rules || true
udevadm trigger --subsystem-match=misc --attr-match=name=uinput || true
systemctl daemon-reload
if systemctl list-unit-files kanata.service --no-legend 2>/dev/null | grep -q "^kanata\\.service"; then
  systemctl disable --now kanata.service || true
  if [[ -e /etc/systemd/system/kanata.service ]] && ! [[ -L /etc/systemd/system/kanata.service ]]; then
    mv /etc/systemd/system/kanata.service /etc/systemd/system/kanata.service.nix-dotfiles-disabled
  fi
  systemctl mask kanata.service || true
  systemctl daemon-reload
fi
systemctl enable --now kanata-main.service
systemctl restart kanata-main.service
