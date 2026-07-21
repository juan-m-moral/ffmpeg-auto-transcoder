#!/usr/bin/env bash

###############################################################################
# FFmpeg Auto Transcoder
# Theme
###############################################################################

# Reset
RST='\e[0m'

# Styles
BOLD='\e[1m'
DIM='\e[2m'

# Colors
WHITE='\e[97m'
BLACK='\e[30m'

BLUE='\e[38;5;33m'
CYAN='\e[38;5;45m'
GREEN='\e[38;5;46m'
YELLOW='\e[38;5;220m'
ORANGE='\e[38;5;208m'
RED='\e[38;5;196m'
MAGENTA='\e[38;5;141m'

GRAY='\e[38;5;245m'
LIGHTGRAY='\e[38;5;250m'

###############################################################################
# Printing helpers
###############################################################################

title()
{
    separator
    printf "%b%b%s%b\n" "$BOLD" "$BLUE" "$*" "$RST"
    separator
}

section()
{
    echo
    separator
    printf "%b%b%s%b\n" "$BOLD" "$CYAN" "$*"
    printf "%b\n" "$RST"
}

label()
{
    printf "${GRAY}%s${RST}" "$1"
}

value()
{
    printf "${WHITE}%s${RST}" "$1"
}

ok()
{
    printf "${GREEN}%s${RST}" "$1"
}

warn()
{
    printf "${YELLOW}%s${RST}" "$1"
}

error()
{
    printf "${RED}%s${RST}" "$1"
}

accent()
{
    printf "${MAGENTA}%s${RST}" "$1"
}

separator()
{
    local cols

    cols=$(tput cols 2>/dev/null)

    if [[ ! "$cols" =~ ^[0-9]+$ ]] || (( cols < 40 )); then
        cols=80
    fi

    printf "%b" "$BLUE"

    printf '━%.0s' $(seq 1 "$cols")

    printf "%b\n" "$RST"
}

terminal_width()
{
    local cols

    cols=$(tput cols 2>/dev/null)

    if [[ ! "$cols" =~ ^[0-9]+$ ]] || (( cols < 80 )); then
        cols=80
    fi

    printf "%d" "$cols"
}

