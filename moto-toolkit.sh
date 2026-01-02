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

MOTO_URL="https://motorola-global-portal.custhelp.com/app/standalone/bootloader/unlock-your-device"

clear

# ============== DYNAMIC BOX ===============
draw_box() {
    local text="$1"
    local cols=$(tput cols 2>/dev/null)
    [ -z "$cols" ] && cols=60

    local max=$((cols - 4))
    local len=${#text}
    local width=$((len + 4))
    [ "$width" -gt "$max" ] && width="$max"
    [ "$width" -lt 30 ] && width=30

    local l=$(( (width - len) / 2 ))
    local r=$(( width - len - l ))

    printf "${CYAN}${BOLD}┏"; printf '━%.0s' $(seq 1 "$width"); printf "┓${RESET}\n"
    printf "${CYAN}${BOLD}┃${RESET}%*s${WHITE}${BOLD}%s${RESET}%*s${CYAN}${BOLD}┃${RESET}\n" "$l" "" "$text" "$r" ""
    printf "${CYAN}${BOLD}┗"; printf '━%.0s' $(seq 1 "$width"); printf "┛${RESET}\n"
}

draw_box "Motorola Flashing Toolkit"
echo

# ==================================================
# ============ TOOL CHECK (TERMUX) ==================
# ==================================================

printf "${BLUE}[•] Checking termux-adb & termux-fastboot...${RESET}\n"

if ! command -v termux-adb >/dev/null 2>&1 || ! command -v termux-fastboot >/dev/null 2>&1; then
    printf "${YELLOW}[!] termux-adb / termux-fastboot not found${RESET}\n"
    printf "${BLUE}[•] Installing android-tools...${RESET}\n"

    if [ -f "installadb.sh" ]; then
        bash installadb.sh
    fi

    pkg install -y android-tools
fi

command -v termux-adb >/dev/null 2>&1 || {
    printf "${RED}[✘] termux-adb still missing${RESET}\n"
    exit 1
}

command -v termux-fastboot >/dev/null 2>&1 || {
    printf "${RED}[✘] termux-fastboot still missing${RESET}\n"
    exit 1
}

printf "${GREEN}[✔] termux-adb & termux-fastboot ready${RESET}\n"

# ============ COMMON CHECKS ===============
adb_check() {
    termux-adb get-state 1>/dev/null 2>&1 || {
        printf "${RED}[✘] No ADB device detected${RESET}\n"
        return 1
    }
}

fastboot_check() {
    termux-fastboot devices | grep -q . || {
        printf "${RED}[✘] No fastboot device detected${RESET}\n"
        return 1
    }
}

# ============ XML FLASH ===================
flash_from_xml() {
    fastboot_check || return
    read -p "Enter firmware folder path: " FW
    [ ! -f "$FW/flashfile.xml" ] && {
        printf "${RED}[✘] flashfile.xml not found${RESET}\n"
        return
    }

    cd "$FW" || return
    draw_box "XML FLASHING STARTED"
    printf "${YELLOW}⚠ Do NOT disconnect device${RESET}\n"

    grep -E "<(flash|erase|reboot)" flashfile.xml | while read -r line; do
        CMD=$(echo "$line" | sed -n 's/.*command="\([^"]*\)".*/\1/p')
        [ -z "$CMD" ] && continue
        printf "${BLUE}[•] termux-fastboot %s${RESET}\n" "$CMD"
        termux-fastboot $CMD || return
    done

    printf "${GREEN}[✔] XML flashing completed${RESET}\n"
}

# ============ ONE CLICK UNBRICK ===========
unbrick_mode() {
    fastboot_check || return
    read -p "Enter firmware folder path: " FW
    [ ! -d "$FW" ] && {
        printf "${RED}[✘] Invalid firmware path${RESET}\n"
        return
    }

    cd "$FW" || return
    draw_box "ONE CLICK UNBRICK"

    for part in boot dtbo vbmeta recovery; do
        for img in $part.img*; do
            [ -f "$img" ] && termux-fastboot flash "$part" "$img"
        done
    done

    for chunk in system.img_sparsechunk.* vendor.img_sparsechunk.*; do
        [ -f "$chunk" ] && termux-fastboot flash "${chunk%%.*}" "$chunk"
    done

    termux-fastboot reboot
    printf "${GREEN}[✔] Unbrick completed${RESET}\n"
}

# =========================================================
# ============ OPTION 3 : BOOTLOADER UNLOCK ================
# =========================================================

check_device() {
    printf "${BLUE}[•] Scanning fastboot device...${RESET}\n"
    DEVICE=$(termux-fastboot devices | head -n 1)
    [ -z "$DEVICE" ] && {
        printf "${RED}[✘] No fastboot device detected${RESET}\n"
        return 1
    }
    printf "${GREEN}[✔] Device detected:${RESET}\n${CYAN}%s${RESET}\n" "$DEVICE"
}

open_website() {
    if command -v termux-open-url >/dev/null 2>&1; then
        termux-open-url "$MOTO_URL"
    elif command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$MOTO_URL"
    else
        printf "%s\n" "$MOTO_URL"
    fi
}

unlock_with_key() {
    check_device || return
    printf "${PURPLE}➤ Enter UNLOCK KEY: ${RESET}"
    read UNLOCK_KEY
    [ -z "$UNLOCK_KEY" ] && {
        printf "${RED}[✘] Unlock key empty${RESET}\n"
        return
    }
    termux-fastboot oem unlock "$UNLOCK_KEY"
    printf "${GREEN}[✔] Unlock command sent${RESET}\n"
}

get_unlock_data() {
    check_device || return
    RAW_DATA=$(termux-fastboot oem get_unlock_data 2>&1)

    UNLOCK_STRING=$(echo "$RAW_DATA" \
        | grep -i "unlock data" \
        | sed 's/(bootloader)//g;s/INFO//g' \
        | tr -d ' \r\n')

    [ -z "$UNLOCK_STRING" ] && {
        printf "${RED}[✘] Failed to get unlock data${RESET}\n"
        return
    }

    draw_box "COPY THIS UNLOCK DATA"
    printf "${WHITE}%s${RESET}\n\n" "$UNLOCK_STRING"

    read -p "Open Motorola website now? (yes/no): " OP
    [[ "$OP" =~ ^(y|Y|yes)$ ]] && open_website

    read -p "Press ENTER after receiving unlock key..."
    unlock_with_key
}

bootloader_unlock_menu() {
    fastboot_check || return
    read -p "Do you already have an unlock key? (yes/no): " HAS_KEY
    case "$HAS_KEY" in
        y|Y|yes|YES) unlock_with_key ;;
        n|N|no|NO) get_unlock_data ;;
        *) printf "${RED}Invalid input${RESET}\n" ;;
    esac
}

# ================== MAIN MENU ==================
while true; do
    echo
    draw_box "MAIN MENU"
    echo -e "${CYAN}
1) XML Based Full Flash
2) One-Click Unbrick Mode
3) Bootloader Unlock
0) Exit
${RESET}"
    printf "${PURPLE}Select option: ${RESET}"
    read opt

    case "$opt" in
        1) flash_from_xml ;;
        2) unbrick_mode ;;
        3) bootloader_unlock_menu ;;
        0) exit ;;
        *) printf "${RED}Invalid option${RESET}\n" ;;
    esac
done