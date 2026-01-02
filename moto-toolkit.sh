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
    if [ -n "$_SPINNER_PID" ]; then
        kill "$_SPINNER_PID" 2>/dev/null
        wait "$_SPINNER_PID" 2>/dev/null
        _SPINNER_PID=""
        printf "\b \n"
    fi
}

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

    printf "${PURPLE}${BOLD}┏"; printf '━%.0s' $(seq 1 "$width"); printf "┓${RESET}\n"
    printf "${PURPLE}${BOLD}┃${RESET}%*s${YELLOW}${BOLD}%s${RESET}%*s${PURPLE}${BOLD}┃${RESET}\n" "$l" "" "$text" "$r" ""
    printf "${PURPLE}${BOLD}┗"; printf '━%.0s' $(seq 1 "$width"); printf "┛${RESET}\n"
}

draw_box "Motorola Toolkit By RepairA2Z"
echo

# ==================================================
# ============ TOOL CHECK (TERMUX) ==================
# ==================================================

printf "${BLUE}[•] Checking termux-adb & termux-fastboot...${RESET}\n"

if ! command -v termux-adb >/dev/null 2>&1 || ! command -v termux-fastboot >/dev/null 2>&1; then
    printf "${YELLOW}[!] termux-adb / termux-fastboot not found${RESET}\n"

    if [ -f "installadb.sh" ]; then
        printf "${BLUE}[•] Running installadb.sh...${RESET}\n"
        bash installadb.sh
    fi

    printf "${BLUE}[•] Installing android-tools...${RESET}\n"
    pkg install -y android-tools
fi

command -v termux-adb >/dev/null 2>&1 || {
    printf "${RED}[✘] termux-adb still missing${RESET}\n"
    printf "${YELLOW}[!] Please run installadb.sh manually${RESET}\n"
   sleep 1.0
    clear
    exit 1
}

command -v termux-fastboot >/dev/null 2>&1 || {
    printf "${RED}[✘] termux-fastboot still missing${RESET}\n"
    sleep 1.0
    clear
     exit 1
}

printf "${GREEN}[✔] termux-adb & termux-fastboot ready${RESET}\n"

# ==================================================
# ============ FASTBOOT CHECK (STABLE) ==============
# ==================================================

fastboot_check() {
    local retries=5
    local delay=1
    local count=1

    while [ $count -le $retries ]; do
        spinner_start "Scanning fastboot device (Attempt $count/$retries)"

        # OTG stability nudge
        termux-usb -l >/dev/null 2>&1
        ls /dev/bus/usb >/dev/null 2>&1

        DEVICE=$(termux-fastboot devices | grep -m1 .)

        spinner_stop

        if [ -n "$DEVICE" ]; then
            printf "${GREEN}[✔] Fastboot device detected${RESET}\n"
            printf "${CYAN}%s${RESET}\n" "$DEVICE"
            return 0
        fi

        printf "${YELLOW}[!] Device not found, retrying...${RESET}\n"
        sleep $delay
        count=$((count + 1))
    done

    printf "\n${RED}[✘] Fastboot device not detected${RESET}\n"
    printf "${PURPLE}[⚠] Please check:${RESET}\n"
    printf "  • OTG adapter\n"
    printf "  • USB DATA cable\n"
    printf "  • Device in FASTBOOT mode\n"
    printf "  • Reconnect cable and retry\n\n"
    sleep 1.0
    clear
    return 1
}

# ================= XML FLASH =================
flash_from_xml() {
    fastboot_check || return

    read -p "Enter firmware folder path: " FW
    [ ! -f "$FW/flashfile.xml" ] && {
        printf "${RED}[✘] flashfile.xml not found${RESET}\n"
        return
    }

    cd "$FW" || return
    draw_box "XML FLASHING STARTED"
    printf "${YELLOW}⚠ Do NOT disconnect device${RESET}\n\n"

    STEP_COUNT=0

    while read -r line; do
        op=$(echo "$line" | sed -n 's/.*operation="\([^"]*\)".*/\1/p')
        part=$(echo "$line" | sed -n 's/.*partition="\([^"]*\)".*/\1/p')
        file=$(echo "$line" | sed -n 's/.*filename="\([^"]*\)".*/\1/p')
        var=$(echo "$line" | sed -n 's/.*var="\([^"]*\)".*/\1/p')

        case "$op" in
            flash)
                printf "${BLUE}[•] fastboot flash %s %s${RESET}\n" "$part" "$file"
                termux-fastboot flash "$part" "$file" || return
                ;;
            erase)
                printf "${BLUE}[•] fastboot erase %s${RESET}\n" "$part"
                termux-fastboot erase "$part" || return
                ;;
            reboot)
                printf "${BLUE}[•] fastboot reboot${RESET}\n"
                termux-fastboot reboot || return
                ;;
            reboot-bootloader)
                printf "${BLUE}[•] fastboot reboot-bootloader${RESET}\n"
                termux-fastboot reboot-bootloader || return
                ;;
            oem)
                printf "${BLUE}[•] fastboot oem %s${RESET}\n" "$var"
                termux-fastboot oem $var || return
                ;;
            getvar)
                printf "${BLUE}[•] fastboot getvar %s${RESET}\n" "$var"
                termux-fastboot getvar "$var"
                ;;
            *)
                printf "${YELLOW}[!] Unknown operation: %s${RESET}\n" "$op"
                ;;
        esac

        STEP_COUNT=$((STEP_COUNT + 1))

    done < <(grep '<step' flashfile.xml)

    if [ "$STEP_COUNT" -eq 0 ]; then
        printf "${RED}[✘] No XML steps executed${RESET}\n"
        return
    fi

    printf "\n${GREEN}[✔] XML flashing completed successfully${RESET}\n"
}
# ================= UNBRICK ==================
unbrick_mode() {
    fastboot_check || return

    read -p "Enter firmware folder path: " FW
    [ ! -d "$FW" ] && {
        printf "${RED}[✘] Invalid firmware path${RESET}\n"
       sleep 1.0
      clear
     return
    }

    cd "$FW" || return
    draw_box "UNBRICK (DYNAMIC PARTITION)"

    # ---------- sanity check ----------
    shopt -s nullglob
    super_chunks=(super.img_sparsechunk.*)
    shopt -u nullglob

    if [ ${#super_chunks[@]} -eq 0 ]; then
        printf "${RED}[✘] super.img_sparsechunk files not found${RESET}\n"
        printf "${YELLOW}[!] This is not a dynamic-partition firmware${RESET}\n"
      sleep 1.0
       clear
       return
    fi

    # ---------- critical partitions ----------
    for part in boot vendor_boot dtbo vbmeta vbmeta_system; do
        shopt -s nullglob
        imgs=($part.img*)
        shopt -u nullglob

        for img in "${imgs[@]}"; do
            printf "${BLUE}[•] Flashing %s${RESET}\n" "$img"
            termux-fastboot flash "$part" "$img" || return
        done
    done

    # ---------- flash super sparsechunks ----------
    printf "${GREEN}[✔] Flashing super.img sparsechunks${RESET}\n"

    for chunk in "${super_chunks[@]}"; do
        printf "${BLUE}[•] Flashing %s${RESET}\n" "$chunk"
        termux-fastboot flash super "$chunk" || return
    done

    termux-fastboot reboot
    printf "${GREEN}[✔] Unbrick completed successfully${RESET}\n"
}
# ================= UNLOCK ===================
open_website() {
    command -v termux-open-url >/dev/null && termux-open-url "$MOTO_URL" || echo "$MOTO_URL"
}

unlock_with_key() {
    fastboot_check || return
    read -p "Enter UNLOCK KEY: " UNLOCK_KEY
    [ -z "$UNLOCK_KEY" ] && {
        printf "${RED}[✘] Unlock key empty${RESET}\n"
       sleep 1.0
       clear 
      return
    }
    termux-fastboot oem unlock "$UNLOCK_KEY"
    printf "${GREEN}[✔] Unlock command sent${RESET}\n"

}

get_unlock_data() {
    fastboot_check || return

    RAW_DATA=$(termux-fastboot oem get_unlock_data 2>&1)
    UNLOCK_STRING=$(echo "$RAW_DATA" | sed 's/(bootloader)//g;s/INFO//g' | tr -d ' \r\n')

    [ -z "$UNLOCK_STRING" ] && {
        printf "${RED}[✘] Failed to get unlock data${RESET}\n"
       sleep 1.0
      clear 
      return
    }

    draw_box "COPY THIS UNLOCK DATA"
    printf "${WHITE}%s${RESET}\n\n" "$UNLOCK_STRING"

    while true; do
    read -p "Open Motorola website now? (yes/no): " OP
    case "$OP" in
        y|Y|yes|YES)
            open_website
            break
            ;;
        n|N|no|NO)
            printf "${YELLOW}[•] Returning to main menu...${RESET}\n"
            sleep 1.0
            clear
            return
            ;;
        *)
            printf "${RED}[✘] Please enter yes or no${RESET}\n"
            ;;
    esac
done

read -p "Press ENTER after receiving unlock key..."
unlock_with_key
}

bootloader_unlock_menu() {
    fastboot_check || return
    read -p "Do you already have an unlock key? (yes/no): " HAS_KEY
    case "$HAS_KEY" in
        y|Y|yes) unlock_with_key ;;
        n|N|no) get_unlock_data ;;
        *) printf "${RED}Invalid input${RESET}\n" ;;
    esac
}

# ================= MAIN MENU =================
while true; do
    echo
    draw_box "MAIN MENU"
    echo -e "${GREEN}
1) XML Based Full Flash
2) One-Click Unbrick Mode
3) Bootloader Unlock
0) Exit
${RESET}"
    draw_box "Please Select your option"
  printf "${CYAN}Enter option: ${RESET}"
    read opt

    case "$opt" in
        1) flash_from_xml ;;
        2) unbrick_mode ;;
        3) bootloader_unlock_menu ;;
        0) exit ;;
        *) printf "${RED}Invalid option${RESET}\n" ;;
    esac
done