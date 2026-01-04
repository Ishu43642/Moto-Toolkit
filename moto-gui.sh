#!/bin/bash

# ================= COLORS =================
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
PURPLE="\033[35m"
CYAN="\033[36m"
WHITE="\033[97m"
BOLD="\033[1m"
RESET="\033[0m"

APP_NAME="Motorola Toolkit by RepairA2Z"
APP_VERSION="v1.0"

MOTO_URL="https://motorola-global-portal.custhelp.com/app/standalone/bootloader/unlock-your-device"

clear

# ================= SPINNER =================
_SPINNER_PID=""
spinner_start() {
    local msg="$1"
    local spin='|/-\'
    local i=0
    printf "${BLUE}%s ${RESET}" "$msg"
    (
        while true; do
            i=$(( (i + 1) % 4 ))
            printf "\b${CYAN}%c${RESET}" "${spin:$i:1}"
            sleep 0.1
        done
    ) &
    _SPINNER_PID=$!
}
spinner_stop() {
    [ -n "$_SPINNER_PID" ] && kill "$_SPINNER_PID" 2>/dev/null && wait "$_SPINNER_PID" 2>/dev/null
    _SPINNER_PID=""
    printf "\b \n"
}

# ============== BOX =================
draw_box() {
    local text="$1"
    printf "${PURPLE}${BOLD}==============================${RESET}\n"
    printf "${YELLOW}${BOLD}%s${RESET}\n" "$text"
    printf "${PURPLE}${BOLD}==============================${RESET}\n"
}

draw_box "$APP_NAME $APP_VERSION"

# ==================================================
# ============ TOOL CHECK ==========================
# ==================================================

command -v termux-adb >/dev/null 2>&1 || bash installadb.sh 2>/dev/null
command -v termux-fastboot >/dev/null 2>&1 || pkg install -y android-tools

command -v termux-fastboot >/dev/null 2>&1 || {
    termux-dialog alert -t "Error" -i "termux-fastboot not found"
    exit 1
}


show_splash() {
    RESP=$(termux-dialog confirm \
        -t "$APP_NAME" \
        -i "Version: $APP_VERSION

Author: RepairA2Z

• Motorola flashing & unlock tool
• Fastboot / XML / Unbrick support

YES = Continue
NO  = Exit Tool" \
        2>/dev/null)

    ANSWER=$(echo "$RESP" | jq -r '.text // empty')

    if [ "$ANSWER" = "yes" ]; then
        clear
        return 0
    else
        clear
        exit 0
    fi
}


show_splash
# ==================================================
# ============ FASTBOOT CHECK ======================
# ==================================================

fastboot_check() {
    while true; do
        for i in {1..5}; do
            spinner_start "Scanning fastboot device ($i/5)"

            # OTG nudge
            termux-usb -l >/dev/null 2>&1

            DEVICE=$(termux-fastboot devices | grep -m1 .)

            spinner_stop

            if [ -n "$DEVICE" ]; then
                return 0   # fastboot device found
            fi

            sleep 1
        done

        spinner_stop

        # -------- USB DEVICE LIST --------
        USB_LIST=""

        # termux-usb output
        USB_TERMUX=$(termux-usb -l 2>/dev/null | tr -d '\r')

        if [ -n "$USB_TERMUX" ]; then
            USB_LIST+="Termux USB devices:\n$USB_TERMUX\n\n"
        fi

        # /dev/bus/usb fallback
        USB_DEVICES=$(ls /dev/bus/usb/*/* 2>/dev/null | wc -l)

        USB_LIST+="USB nodes detected: $USB_DEVICES"

        # -------- DIALOG --------
        RESP=$(termux-dialog confirm \
  -t "Fastboot Device Not Found" \
  -i "No fastboot device detected.

$USB_LIST

YES = Retry
NO  = Exit Tool" \
  2>/dev/null)
        ANSWER=$(echo "$RESP" | jq -r '.text // empty')

        if [ "$ANSWER" = "yes" ]; then
            clear
            continue   # retry scanning
        else
            clear
            exit 0     # exit tool
        fi
    done
}

run_fastboot() {
    CMD_DESC="$1"
    shift

    "$@"
    RET=$?

    if [ $RET -ne 0 ]; then
        termux-dialog confirm \
            -t "Fastboot Error" \
            -i "Operation failed:

$CMD_DESC

Please check:
• Correct device
• Bootloader state
• Firmware compatibility

Press OK to return to menu." \
            >/dev/null 2>&1

        clear
        return 1
    fi

    return 0
}
# ================= XML FLASH =================
flash_from_xml() {
    fastboot_check || return
    FW=$(termux-dialog text -t "Firmware Path" -i "Enter firmware folder path" | jq -r '.text')
    [ ! -f "$FW/flashfile.xml" ] && termux-dialog alert -t "Error" -i "flashfile.xml not found" && return
    cd "$FW" || return

    draw_box "XML FLASHING"
    grep '<step' flashfile.xml | while read -r line; do
        op=$(sed -n 's/.*operation="\([^"]*\)".*/\1/p' <<< "$line")
        part=$(sed -n 's/.*partition="\([^"]*\)".*/\1/p' <<< "$line")
        file=$(sed -n 's/.*filename="\([^"]*\)".*/\1/p' <<< "$line")
        var=$(sed -n 's/.*var="\([^"]*\)".*/\1/p' <<< "$line")

        case "$op" in
            flash) termux-fastboot flash "$part" "$file" || return ;;
            erase) termux-fastboot erase "$part" || return ;;
            reboot) termux-fastboot reboot ;;
            reboot-bootloader) termux-fastboot reboot-bootloader ;;
            oem) termux-fastboot oem $var ;;
            getvar) termux-fastboot getvar "$var" ;;
        esac
    done
    termux-dialog alert -t "Done" -i "XML flashing completed"
}

# ================= UNBRICK ==================
unbrick_mode() {
    fastboot_check || return
    FW=$(termux-dialog text -t "Firmware Path" -i "Enter firmware folder path" | jq -r '.text')
    cd "$FW" || return

    shopt -s nullglob
    super=(super.img_sparsechunk.*)
    shopt -u nullglob
    [ ${#super[@]} -eq 0 ] && termux-dialog alert -t "Error" -i "No super.img_sparsechunk found" && return

    for part in boot vendor_boot dtbo vbmeta vbmeta_system; do
        for img in $part.img*; do
            [ -f "$img" ] && termux-fastboot flash "$part" "$img"
        done
    done

    for img in "${super[@]}"; do
        termux-fastboot flash super "$img"
    done

    termux-fastboot reboot
    termux-dialog alert -t "Done" -i "Unbrick completed"
}

# ================= UNLOCK ===================
confirm_unlock() {
    RESP=$(termux-dialog confirm -t "Bootloader Unlock" -i "This will ERASE all data.\nContinue?" | jq -r '.text')
    [ "$RESP" = "yes" ]
}

detect_unlock_method() {
    termux-fastboot getvar all 2>&1 | grep -qi flashing_unlocked && echo flashing || echo oem
}

unlock_with_key() {
    KEY=$(termux-dialog text -t "Unlock Key" -i "Paste unlock key" | jq -r '.text')
    [ -z "$KEY" ] && return
    run_fastboot "OEM unlock" termux-fastboot oem unlock "$KEY" || return
}

get_unlock_data() {
    DATA=$(termux-fastboot oem get_unlock_data 2>&1 | sed 's/(bootloader)//g;s/INFO//g' | tr -d ' \r\n')
    termux-dialog alert -t "Unlock Data" -i "$DATA"
    termux-open-url "$MOTO_URL"
    unlock_with_key
}

bootloader_unlock_menu() {
    fastboot_check || return
    confirm_unlock || return

    METHOD=$(detect_unlock_method)
    if [ "$METHOD" = "flashing" ]; then
        run_fastboot "Bootloader unlock (flashing unlock)" termux-fastboot flashing unlock || return
run_fastboot "Bootloader unlock (critical)" termux-fastboot flashing unlock_critical || return
        termux-dialog alert -t "Done" -i "Bootloader unlocked"
        return
    fi

    RESP=$(termux-dialog confirm -t "Unlock Key" -i "Do you already have unlock key?" | jq -r '.text')
    [ "$RESP" = "yes" ] && unlock_with_key || get_unlock_data
}

# ================= GUI MAIN MENU =================
while true; do
    CHOICE=$(termux-dialog sheet -t "$APP_NAME $APP_VERSION" -v "XML Flash,Unbrick,Bootloader Unlock,Exit" | jq -r '.text')
    case "$CHOICE" in
        "XML Flash") flash_from_xml ;;
        "Unbrick One Click") unbrick_mode ;;
        "Bootloader Unlock") bootloader_unlock_menu ;;
        "Exit"|null) exit ;;
    esac
done