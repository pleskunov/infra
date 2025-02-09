#!/bin/bash

set -xeu
set -o pipefail

#if ! [ "${EUID:-$(id -u)}" -eq 0 ]; then
#  echo "The script must be run as root!"
#  exit 1
#fi

package_list="/root/arch-packages.txt"
package_list_url="https://raw.githubusercontent.com/pleskunov/infra/refs/heads/main/arch-packages.txt"
sys_dots=("/etc/chrony.conf" "/etc/dnscrypt-proxy/dnscrypt-proxy.toml" "/etc/nftables.conf" "/etc/resolv.conf")

GREEN="\e[32m"
RED="\e[31m"
RESET="\e[0m"

configure_service() {
  local service_name="$1"
  echo -n "Configuring $service_name..."

  if some_command "$service_name"; then
    echo -e " [${GREEN}OK${RESET}]"
  else
    echo -e " [${RED}FAIL${RESET}]"
  fi
}

some_command() {
  [[ "$1" == "service1" ]]
}

backup_file() {
  local file_path="$1"
  echo -n "Backing up $file_path..."
  if [[ ! -f "$file_path" ]]; then
    echo -e "[\e[31mFAIL\e[0m] File '$file_path' not found."
    return 1
  fi

  local backup_path="${file_path}.bak"
  if cp -- "$file_path" "$backup_path"; then
    echo -e "[\e[32mOK\e[0m]"
  else
    echo -e "[\e[31mFAIL\e[0m] Failed to create backup."
    return 1
  fi
}

echo -n "Downloading the packages list..."
if curl --proto '=https' --tlsv1.2 -o "$package_list" -sSf "$package_list_url"; then
  echo -e " [${GREEN}OK${RESET}]"
else
  echo -e " [${RED}FAIL${RESET}]"
  exit 1
fi

echo -n "Installing the packages..."
echo ""
if pacman -Sy --needed $(<"$package_list"); then
  echo -e " [${GREEN}DONE${RESET}]"
else
  echo -e " [${RED}FAIL${RESET}]"
  exit 1
fi

for dotfile in "${sys_dots[@]}"; do
  backup_file "${dotfile}"
done

configure_service "service1"
configure_service "service2"

exit 0
