#!/usr/bin/env bash

# convenience script for fast(er) board updates
# requires bash 4+

# Ensure volume is up (nice60-zmk-config)
# https://zmk.dev/docs/development/local-toolchain/setup/container#creating-volumes

set -Eeuo pipefail

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

while getopts "l" opt; do
  case $opt in
    l) zmk_usb_logging="zmk-usb-logging" ;; # https://zmk.dev/docs/development/usb-logging
    *) exit 1 ;;
  esac
done

SOURCE_DIR="${HOME}/Downloads"
WORKING_DIR="$(pwd)"
TARGET_DIR="/Volumes/NICE60"
ZIP="${SOURCE_DIR}/firmware.zip"
FILE="${WORKING_DIR}/out/nice60-zmk.uf2"

DOCKER_ID=$(docker ps | awk '/vsc-zmk/ { print $1 }')

if [ -e "${ZIP}" ]
then
  notice "${ZIP} found, unzipping"
  mv "${ZIP}" "${WORKING_DIR}/firmware.zip"
  unzip firmware.zip && rm -f firmware.zip
else
  warning "${ZIP} is missing"
  if [ -z "${DOCKER_ID}" ]
  then
    error "vsc-zmk Docker container not found"
    exit 1
  else
    notice "Found vsc-zmk Docker container ID ${DOCKER_ID}"
    docker exec -w /workspaces/zmk/app "${DOCKER_ID}" west -q build ${zmk_usb_logging:+--snippet "$zmk_usb_logging"} --pristine --board nice60 -- -DZMK_CONFIG="/workspaces/zmk-config/config"
    docker cp "${DOCKER_ID}:/workspaces/zmk/app/build/zephyr/zmk.uf2" "${FILE}"
  fi
fi

if [ ! -d "${TARGET_DIR}" ]; then
  error "${TARGET_DIR} does not exist; put nice!60 in bootloader mode"
else
  mv "${FILE}" "${TARGET_DIR}"
  notice "Keyboard updated"
fi

