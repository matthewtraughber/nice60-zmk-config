#!/usr/bin/env bash

# convenience script for fast(er) board updates
# requires bash 4+

# Ensure volume is up (nice60-zmk-config)
# https://zmk.dev/docs/development/local-toolchain/setup/container#creating-volumes

set -Eeuo pipefail

SOURCE_DIR="${HOME}/Downloads"
WORKING_DIR="$(pwd)"
TARGET_DIR="/Volumes/NICE60"
ZIP="${SOURCE_DIR}/firmware.zip"
FILE="${WORKING_DIR}/out/nice60-zmk.uf2"

# universal logging (overkill here)
function log_prefix() {
  local level="${1}"
  local title="[${level^^}]"
  local prefix
  test -v CI && prefix="::${level} title=${title}::" || prefix="${title} "
  echo "${prefix}$(basename "${0}"):"
}
function with_stderr() { >&2 "${@}"; }
function log_with_level() { with_stderr echo "$(log_prefix "${1}")" "${@:2}"; }
function notice() { log_with_level "${FUNCNAME[0]}" "${@}"; }
function warning() { log_with_level "${FUNCNAME[0]}" "${@}"; }
function error() { log_with_level "${FUNCNAME[0]}" "${@}"; }

function is_mounted() { mount | grep --quiet --fixed-strings "${TARGET_DIR}"; }

while getopts "l" opt; do
  case $opt in
    l) zmk_usb_logging="zmk-usb-logging" ;; # https://zmk.dev/docs/development/usb-logging
    *) exit 1 ;;
  esac
done

if test -n "${zmk_usb_logging:-}"; then
  warning "USB logging enabled — ensure CONFIG_ZMK_USB_LOGGING=y is set in nice60.conf"
fi

if test -e "${ZIP}"; then
  notice "${ZIP} found, unzipping..."

  mv "${ZIP}" "${WORKING_DIR}/firmware.zip"
  unzip firmware.zip
  rm -f firmware.zip
else
  warning "${ZIP} is missing, building locally..."

  DOCKER_PS=$(docker ps --all --format json | jq --raw-output 'select(.Image | startswith("vsc-zmk"))')
  DOCKER_ID=$(jq --raw-output '.ID' <<< "${DOCKER_PS}")
  DOCKER_STATE=$(jq --raw-output '.State' <<< "${DOCKER_PS}")

  if test -z "${DOCKER_ID}"; then
    error "vsc-zmk docker container not found"
    exit 1
  fi

  if test "${DOCKER_STATE}" != "running"; then
    notice "Starting stopped container ${DOCKER_ID}"
    docker start "${DOCKER_ID}"
  fi

  mkdir -p "$(dirname "${FILE}")"
  docker exec --workdir /workspaces/zmk/app "${DOCKER_ID}" \
    west --quiet build \
      ${zmk_usb_logging:+--snippet "$zmk_usb_logging"} \
      --pristine \
      --board nice60 \
      -- -DZMK_CONFIG="/workspaces/zmk-config/config"
  docker cp "${DOCKER_ID}:/workspaces/zmk/app/build/zephyr/zmk.uf2" "${FILE}"
fi

elapsed=0
BOOTLOADER_TIMEOUT=30
while ! is_mounted; do
  if test "${elapsed}" -ge "${BOOTLOADER_TIMEOUT}"; then
    error "${TARGET_DIR} did not appear after ${BOOTLOADER_TIMEOUT}s"
    exit 1
  fi

  remaining=$((BOOTLOADER_TIMEOUT - elapsed))
  notice "Waiting ${remaining}s for ${TARGET_DIR} (enter bootloader mode on nice60)..."

  sleep 1
  elapsed=$((elapsed + 1))
done

if ! mv_out=$(mv "${FILE}" "${TARGET_DIR}" 2>&1); then
  sleep 2  # let board unmount
  if is_mounted; then
    >&2 echo "${mv_out}"
    exit 1
  fi
fi
notice "Board updated successfully"
