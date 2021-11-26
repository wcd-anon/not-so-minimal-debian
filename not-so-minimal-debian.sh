#!/usr/bin/env bash
Name="not-so-minimal-debian.sh"

# Copyright (c) 2021 Daniel Wayne Armstrong. All rights reserved.

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE. See the LICENSE file for more details.

set -euo pipefail # run `bash -x not-so-minimal-debian.sh` for debugging

Version="11"
Release="bullseye" 

hello_world() {
clear
banner "START"
cat << _EOF_
*$Name* is a script for configuring Debian GNU/Linux.
It is ideally run after the first boot into a minimal install [1] of
Debian $Version aka "$Release".

A choice of either a _server_ or _desktop_ configuration is available.
Server installs packages for a basic console setup, whereas desktop
installs a more complete setup with the option of either the _Openbox_
window manager [2] or _Xorg_ server (with no desktop).

[1] https://www.dwarmstrong.org/minimal-debian/
[2] https://www.dwarmstrong.org/openbox/

_EOF_
}

run_options() {
    while getopts ":h" OPT
    do
        case $OPT in
        h)
            hello_world
            exit
            ;;
        ?)
            err "Invalid option ${OPTARG}."
            exit 1
            ;;
        esac
    done
}

invalid_reply() {
printf "\nInvalid reply.\n\n"
}

run_script() {
while :
do
    read -r -n 1 -p "Run script now? [yN] > "
    if [[ "$REPLY" == [yY] ]]; then
        break
    elif [[ "$REPLY" == [nN] || "$REPLY" == "" ]]; then
        echo ""
        exit
    else
        invalid_reply
    fi
done
}

# ANSI escape codes
RED="\\033[1;31m"
GREEN="\\033[1;32m"
YELLOW="\\033[1;33m"
PURPLE="\\033[1;35m"
NC="\\033[0m" # no colour

echo_red() {
echo -e "${RED}$1${NC}"
}

echo_green() {
echo -e "${GREEN}$1${NC}"
}

echo_yellow() {
echo -e "${YELLOW}$1${NC}"
}

echo_purple() {
echo -e "${PURPLE}$1${NC}"
}

banner() {
printf "\n\n========> $1\n\n"
}

bak_file() {
for f in "$@"; do cp "$f" "$f.$(date +%FT%H%M%S).bak"; done
}

verify_root() {
if (( EUID != 0 )); then
    printf "\n\nScript must be run with root privileges. Abort.\n"
    exit 1
fi
}

verify_version() {
local version
version="$(grep VERSION_ID /etc/os-release | egrep -o '[[:digit:]]{2}')"
if [[ $version == "$Version" ]]; then
    :
else
    echo $version
    printf "\n\nScript for Debian $Version stable/$Release only. Abort.\n"
    exit 1
fi
}

verify_homedir() {
# $1 is $USER
if [[ "$#" -eq 0 ]]; then
    printf "\n\nNo username provided. Abort.\n"
    exit 1
elif [[ ! -d "/home/$1" ]]; then
    printf "\n\nA home directory for $1 not found. Abort.\n"
    exit 1
fi
}

config_consolefont() {
banner "Configure console font"
local file
file="/etc/default/console-setup"
dpkg-reconfigure console-setup
grep FONTFACE $file
grep FONTSIZE $file
}

config_keyboard() {
banner "Configure keyboard"
local file
file="/etc/default/keyboard"
dpkg-reconfigure keyboard-configuration
setupcon
grep XKB $file
}

config_apt_sources() {
banner "Configure apt sources.list"
# Add backports repository, update package list, upgrade packages.
local file
file="/etc/apt/sources.list"
local mirror
mirror="http://deb.debian.org/debian/"
local sec_mirror
sec_mirror="http://security.debian.org/debian-security"
local repos
repos="main contrib non-free"
# Backup previous config
bak_file $file
# Create a new config
cat << _EOL_ > $file
deb $mirror $Release $repos
#deb-src $mirror $Release $repos

deb $sec_mirror ${Release}-security $repos
#deb-src $sec_mirror ${Release}-security $repos

deb $mirror ${Release}-updates $repos
#deb-src $mirror ${Release}-updates $repos

deb $mirror ${Release}-backports $repos
#deb-src $mirror ${Release}-backports $repos
_EOL_
# Update/upgrade
cat $file
echo ""
echo "Update list of packages available and upgrade $HOSTNAME ..."
apt-get update && apt-get -y dist-upgrade
}

config_ssh() {
banner "Create SSH directory for $User"
apt-get -y install openssh-server keychain
# Install SSH server and create $HOME/.ssh.
# See https://www.dwarmstrong.org/ssh-keys/
local ssh_dir
ssh_dir="/home/${User}/.ssh"
local auth_key
auth_key="${ssh_dir}/authorized_keys"
# Create ~/.ssh
if [[ -d "$ssh_dir" ]]; then
    echo ""
    echo "SSH directory $ssh_dir already exists. Skipping ..."
else
    mkdir $ssh_dir && chmod 700 $ssh_dir && touch $auth_key
    chmod 600 $auth_key && chown -R ${User}: $ssh_dir
fi
}

config_sudo() {
banner "Configure sudo"
apt-get -y install sudo
# Add config file to /etc/sudoers.d/ to allow $User to
# run any command without a password.
local file
file="/etc/sudoers.d/sudoers_${User}"
if [[ -f "$file" ]]; then
    echo ""
    echo "$file already exists. Skipping ..."
else
    echo "$User ALL=(ALL) NOPASSWD: ALL" > $file
    usermod -aG sudo $User
fi
}

config_sysctl() {
banner "Configure sysctl"
local sysctl
sysctl="/etc/sysctl.conf"
local dmesg
dmesg="kernel.dmesg_restrict = 0"
if grep -q "$dmesg" "$sysctl"; then
    echo "Option $dmesg already set. Skipping ..."
else
    bak_file $sysctl
    cat << _EOL_ >> $sysctl

# Allow non-root access to dmesg
$dmesg
_EOL_
    # Reload configuration.
    sysctl -p
fi
}

config_grub() {
banner "Configure GRUB"
local file
file="/etc/default/grub"
local custom_cfg
custom_cfg="/boot/grub/custom.cfg"
# Backup configs
bak_file $file
if [[ -f "$custom_cfg" ]]; then
    bak_file $custom_cfg
fi
# Configure default/grub
if ! grep -q ^GRUB_DISABLE_SUBMENU "$file"; then
    cat << _EOL_ >> $file

# Kernel list as a single menu
GRUB_DISABLE_SUBMENU=y
_EOL_
fi
# Menu colours
cat << _EOL_ > $custom_cfg
set color_normal=white/black
set menu_color_normal=white/black
set menu_color_highlight=white/green
_EOL_
# Apply changes
update-grub
}

config_trim() {
banner "TRIM"
# Enable a weekly task that discards unused blocks on the drive.
systemctl enable fstrim.timer
systemctl status fstrim.timer | grep Active
}

install_microcode() {
banner "Install microcode"
# Intel and AMD processors may periodically need updates to their microcode
# firmware. Microcode can be updated (and kept in volatile memory) during
 # boot by installing either intel-microcode or amd64-microcode (AMD).
local file
file="/proc/cpuinfo"
if grep -q GenuineIntel "$file"; then
    apt-get -y install intel-microcode
elif grep -q AuthenticAMD "$file"; then
    apt-get -y install amd64-microcode
fi
}

install_console_pkgs() {
banner "Install console packages"
local pkg_tools
pkg_tools="apt-file apt-show-versions apt-utils aptitude command-not-found"
local build_tools
build_tools="build-essential autoconf automake checkinstall libtool"
local console
console="cowsay cryptsetup curl figlet firmware-misc-nonfree git gnupg "
console+="keychain libncurses-dev lolcat mlocate ncal neofetch neovim "
console+="net-tools nmap openssh-server rsync shellcheck sl speedtest-cli "
console+="tmux unzip wget whois zram-tools"
apt-get -y install $pkg_tools $build_tools $console
apt-file update && update-command-not-found
# Create the mlocate database
/etc/cron.daily/mlocate
# Train kept a rollin' ...
if [[ -x "/usr/games/sl" ]]; then
    /usr/games/sl
fi
}

install_unattended_upgrades() {
banner "Configure unattend-upgrades"
# Install security updates automatically courtesy of `unattended-upgrades`.
# See https://www.dwarmstrong.org/unattended-upgrades/
local file
file="/etc/apt/apt.conf.d/50unattended-upgrades"
local auto_file
auto_file="/etc/apt/apt.conf.d/20auto-upgrades"
# Install
apt-get -y install unattended-upgrades
# Enable *-updates and *-proposed-updates.
sed -i '29,30 s://::' $file
# Enable *-backports.
sed -i '42 s://::' $file
# Send email to root concerning any problems or packages upgrades.
sed -i \
's#//Unattended-Upgrade::Mail \"\";#Unattended-Upgrade::Mail \"root\";#' $file
# Remove unused packages after the upgrade (equivalent to apt-get autoremove).
sed -i '111 s://::' $file
sed -i '111 s:false:true:' $file
# If an upgrade needs to reboot the device, reboot at a specified time
# instead of immediately.
sed -i '124 s://::' $file
# Automatically download and install stable updates (0=disabled, 1=enabled).
cat << _EOL_ > $auto_file
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
_EOL_
}

install_syncthing() {
banner "Install syncthing"
local key_file
key_file="/usr/share/keyrings/syncthing-archive-keyring.gpg"
local repo
repo="https://apt.syncthing.net/ syncthing stable"
local apt_file
apt_file="/etc/apt/sources.list.d/syncthing.list"
local pin_file
pin_file="/etc/apt/preferences.d/syncthing"
local raw_git
raw_git="https://raw.githubusercontent.com/syncthing/syncthing/main/etc"
local service_file
service_file="linux-systemd/system/syncthing%40.service"
local service_dir
service_dir="/etc/systemd/system/"
# As per https://apt.syncthing.net/ ...
#
# Add the release PGP keys:
curl -s -o $key_file https://syncthing.net/release-key.gpg
# Add the "stable" channel to your APT sources:
echo "deb [signed-by=${key_file}] ${repo}" > $apt_file
# Increase preference of Syncthing's packages ("pinning")
cat << _EOL_ > $pin_file
Package: *
Pin: origin apt.syncthing.net
Pin-Priority: 990
_EOL_
# Update and install syncthing:
apt-get update
apt-get -y install syncthing
# Remove older service file
if [[ -f "${service_dir}syncthing@.service" ]]; then
    rm ${service_dir}syncthing@.service
fi
# Setup a systemd unit to automate the startup. Add the systemd service ...
wget ${raw_git}/${service_file} --directory-prefix=${service_dir}
systemctl daemon-reload
# Enable and start Syncthing for your username ...
systemctl enable --now syncthing@${User}
}

install_server_pkgs() {
banner "Install server packages"
local server
server="fail2ban lm-sensors logwatch newsboat rdiff-backup vbetool"
apt-get -y install $server
}

install_xorg() {
banner "Install Xorg"
local xorg
xorg="xorg xbacklight xbindkeys xvkbd xinput xserver-xorg-input-all"
local fonts
fonts="fonts-dejavu fonts-firacode fonts-liberation2 fonts-ubuntu"
apt-get -y install $xorg $fonts
}

install_openbox() {
banner "Install Openbox window manager"
local pkgs
pkgs="openbox obconf menu "
pkgs+="diodon dunst dbus-x11 feh hsetroot i3lock libnotify-bin lximage-qt "
pkgs+="network-manager network-manager-gnome pavucontrol-qt "
pkgs+="pulseaudio pulseaudio-utils rofi scrot tint2 volumeicon-alsa "
pkgs+="xfce4-power-manager"
apt-get -y install $pkgs
}

install_desktop_pkgs() {
banner "Install desktop packages"
local pkgs
pkgs="alsa-utils build-essential default-jre espeak firefox-esr "
pkgs+="ffmpeg gimp gimp-help-en gimp-data-extras gthumb ipython3 jmtpfs "
pkgs+="lm-sensors python3-pip qpdfview qt5-style-plugins thunderbird "
pkgs+="transmission-qt vlc xfce4-terminal"
apt-get -y install $pkgs
}

install_theme() {
banner "Install theme: Nordic"
local pkgs
pkgs="adwaita-qt gnome-themes-standard gtk2-engines-murrine "
pkgs+="gtk2-engines-pixbuf lxappearance obconf papirus-icon-theme "
pkgs+="qt5-style-plugins"
local themes
themes="/home/${User}/.themes"
local theme_gtk
theme_gtk="Nordic"
local src_theme_gtk 
src_theme_gtk="https://github.com/EliverLara/Nordic.git"
local theme_openbox
theme_openbox="Nordic-Openbox"
local src_theme_openbox
src_theme_openbox="https://github.com/hsully03/Nordic-Openbox.git"
apt-get -y install $pkgs
if [[ -d "$themes" ]]; then
    printf "\n$themes already exists.\n"
else
    mkdir $themes
fi
if [[ -d "${themes}/${theme_gtk}" ]]; then
    printf "\n$theme_gtk already installed.\n"
else
    git clone $src_theme_gtk
    mv $theme_gtk $themes
fi
if [[ -d "${themes}/${theme_openbox}" ]]; then
    printf "\n$theme_openbox already installed.\n"
else
    git clone $src_theme_openbox
    mv $theme_openbox $themes
fi
chown -R ${User}: $themes
}

server_profile() {
install_server_pkgs
}

openbox_profile() {
install_xorg
install_openbox
install_desktop_pkgs
install_theme
}

xorg_profile() {
install_xorg
}

config_update_alternatives() {
banner "Configure default commands"
update-alternatives --config editor
if [[ "$Profile" == "openbox" ]]; then
    update-alternatives --config x-terminal-emulator
fi
}

go_or_no_go() {
local Num
Num="10"
local User
User="foo"
local Sudo
Sudo="no"
local Profile
Profile="foobar"
local Auto_update
Auto_update="no"
local Kbd
Kbd="no"
local Font
Font="no"
local Ssd
Ssd="no"
local Grub
Grub="no"
local Sync
Sync="no"

while :
do
    banner "Question 1 of $Num"
    read -r -p "What is your non-root username? > "
    User=$REPLY
    verify_homedir $User

    banner "Question 2 of $Num"
    local sudo_msg
    sudo_msg="Allow $User to use 'sudo' to execute any command "
    sudo_msg+="without a password?"
    while :
    do
        read -r -n 1 -p "$sudo_msg [Yn] > "
        if [[ "$REPLY" == [nN] ]]; then
            break
        elif [[ "$REPLY" == [yY] || "$REPLY" == "" ]]; then
            Sudo="yes"
            break
        else
            invalid_reply
        fi
    done

    banner "Question 3 of $Num"
    while :
    do
        echo "Setup this computer as:"
        echo "[1] Server [2] Desktop (Openbox) [3] Desktop (Xorg)"
        echo ""
        read -r -n 1 -p "Choose a number > "
        if [[ "$REPLY" == 1 ]]; then
            Profile="server"
            break
        elif [[ "$REPLY" == 2 ]]; then
            Profile="openbox"
            break
        elif [[ "$REPLY" == 3 ]]; then
            Profile="xorg"
            break
        else
            invalid_reply
        fi
    done

    banner "Question 4 of $Num"
    while :
    do
        echo "Automatically fetch and install the latest security fixes "
        echo "(unattended-upgrades(8)). Useful especially on servers."
        echo ""
        read -r -n 1 -p "Auto-install security updates? [Yn] > "
        if [[ "$REPLY" == [nN] ]]; then
            break
        elif [[ "$REPLY" == [yY] || "$REPLY" == "" ]]; then
            Auto_update="yes"
            break
        else
            invalid_reply
        fi
    done

    banner "Question 5 of $Num"
    while :
    do
        echo "Change the model of keyboard and/or the keyboard map."
        echo "Example: QWERTY to Colemak, or non-English layouts."
        echo ""
        read -r -n 1 -p "Setup different keyboard configuration? [Yn] > "
        if [[ "$REPLY" == [nN] ]]; then
            break
        elif [[ "$REPLY" == [yY] || "$REPLY" == "" ]]; then
            Kbd="yes"
            break
        else
            invalid_reply
        fi
    done

    banner "Question 6 of $Num"
    while :
    do
        echo "Change the font and font-size used in the console."
        echo "Example: TERMINUS font in size 10x20."
        echo ""
        read -r -n 1 -p "Setup a different console font? [Yn] > "
        if [[ "$REPLY" == [nN] ]]; then
            break
        elif [[ "$REPLY" == [yY] || "$REPLY" == "" ]]; then
            Font="yes"
            break
        else
            invalid_reply
        fi
    done

    banner "Question 7 of $Num"
    while :
    do
        echo "Periodic TRIM optimizes performance on solid-state"
        echo "storage. If this machine has an SSD drive, you"
        echo "should enable this task."
        echo ""
        read -r -n 1 -p "Discard unused blocks? [Yn] > "
        if [[ "$REPLY" == [nN] ]]; then
            break
        elif [[ "$REPLY" == [yY] || "$REPLY" == "" ]]; then
            Ssd="yes"
            break
        else
            invalid_reply_yn
        fi
    done

    banner "Question 8 of $Num"
    while :
    do
        echo "GRUB extras: Add a bit of colour and sound!"
        echo ""
        read -r -n 1 -p "Setup a custom GRUB? [Yn] > "
        if [[ "$REPLY" == [nN] ]]; then
            break
        elif [[ "$REPLY" == [yY] || "$REPLY" == "" ]]; then
            Grub="yes"
            break
        else
            invalid_reply
        fi
    done

    banner "Question 9 of $Num"
    while :
    do
        echo "Syncthing [1] is a continuous file synch program. It"
        echo "syncs files between multiple computers in real time."
        echo ""
        echo "[1] https://www.dwarmstrong.org/syncthing/"
        echo ""
	    read -r -n 1 -p "Install syncthing? [Yn] > "
        if [[ "$REPLY" == [nN] ]]; then
            break
        elif [[ "$REPLY" == [yY] || "$REPLY" == "" ]]; then
            Sync="yes"
            break
        else
            invalid_reply
        fi
    done

    banner "Question 10 of $Num"
    echo_purple "Username: $User"
    echo_purple "Profile: $Profile"
    if [[ "$Sudo" == "yes" ]]; then
        echo_green "Sudo without password: $Sudo"
    else
        echo_red "Sudo without password: $Sudo"
    fi
    if [[ "$Auto_update" == "yes" ]]; then
        echo_green "Automatic Updates: $Auto_update"
    else
        echo_red "Automatic Updates: $Auto_update"
    fi
    if [[ "$Kbd" == "yes" ]]; then
        echo_green "Configure Keyboard: $Kbd"
    else
        echo_red "Configure Keyboard: $Kbd"
    fi
    if [[ "$Font" == "yes" ]]; then
        echo_green "Configure Font: $Font"
    else
        echo_red "Configure Font: $Font"
    fi
    if [[ "$Ssd" == "yes" ]]; then
        echo_green "TRIM: $Ssd"
    else
        echo_red "TRIM: $Ssd"
    fi
    if [[ "$Grub" == "yes" ]]; then
        echo_green "Custom GRUB: $Grub"
    else
        echo_red "Custom GRUB: $Grub"
    fi
    if [[ "$Sync" == "yes" ]]; then
        echo_green "Syncthing: $Sync"
    else
        echo_red "Syncthing: $Sync"
    fi
    echo ""
    read -r -n 1 -p "Is this correct? [Yn] > "
    if [[ "$REPLY" == [yY] || "$REPLY" == "" ]]; then
        printf "\n\nOK ... Let's roll ...\n"
        break
    elif [[ "$REPLY" == [nN] ]]; then
        printf "\n\nOK ... Let's try again ...\n"
    else
        invalid_reply
    fi
done

if [[ "$Font" == "yes" ]]; then
    config_consolefont || true # continue even if exit is not 0
fi
if [[ "$Kbd" == "yes" ]]; then
    config_keyboard || true
fi
config_apt_sources
config_ssh
if [[ "$Sudo" == "yes" ]]; then
    config_sudo
fi
config_sysctl
if [[ "$Grub" == "yes" ]]; then
    config_grub
fi
if [[ "$Ssd" == "yes" ]]; then
    config_trim
fi
install_microcode
install_console_pkgs
if [[ "$Auto_update" == "yes" ]]; then
    install_unattended_upgrades
fi
if [[ "$Sync" == "yes" ]]; then
    install_syncthing
fi
if [[ "$Profile" == "server" ]]; then
    server_profile
fi
if [[ "$Profile" == "openbox" ]]; then
    openbox_profile
fi
if [[ "$Profile" == "xorg" ]]; then
    xorg_profile
fi
config_update_alternatives
}

au_revoir() {
local message
message="Done! Debian is ready. Happy hacking!"
printf "\n\n"
echo "$message" | /usr/games/cowsay -f tux | /usr/games/lolcat
}

# (O<  Let's go!
# (/)_
run_options "$@"
verify_root
hello_world
run_script
verify_version
go_or_no_go
au_revoir
exit
