#!/usr/bin/env bash

# UnOfficial FOS-Streaming Automated Installation Script
# =============================================
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the MIT License as published by
#  the Open Source Foundation
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  MIT License for more details.
#
#  You should have received a copy of the MIT License
#  along with this program.  If not, see <https://opensource.org/licenses/MIT>.
#
# Supported Operating Systems: 
# Ubuntu server14.04 
# 32bit and 64bit
#
# Contributions installer from:
#
#   Tyfix (sevan@tyfix.nl)
#   Andy kimpe (andykimpe@gmail.com)

# FOS_STREAMING_CORE/INSTALLER_VERSION
# master - latest unstable
# 1.0.0 - example stable tag
##

FOS_STREAMING_INSTALLER_VERSION="master"
FOS_STREAMING_CORE_VERSION="master"

#--- Display the 'welcome' splash/user warning info..
echo ""
echo "############################################################"
echo "#  Welcome to the UnOfficial FOS-Streaming Installer $FOS_STREAMING_INSTALLER_VERSION  #"
echo "############################################################"

echo -e "\nChecking that minimal requirements are ok"

# Ensure the OS is compatible with the launcher
if [ -f /etc/centos-release ]; then
    OS="CentOs"
    VERFULL=$(sed 's/^.*release //;s/ (Fin.*$//' /etc/centos-release)
    VER=${VERFULL:0:1} # return 6 or 7
elif [ -f /etc/lsb-release ]; then
    OS=$(grep DISTRIB_ID /etc/lsb-release | sed 's/^.*=//')
    VER=$(grep DISTRIB_RELEASE /etc/lsb-release | sed 's/^.*=//')
elif [ -f /etc/os-release ]; then
    OS=$(grep -w ID /etc/os-release | sed 's/^.*=//')
    VER=$(grep VERSION_ID /etc/os-release | sed 's/^.*"\(.*\)"/\1/')
 else
    OS=$(uname -s)
    VER=$(uname -r)
fi
ARCH=$(uname -m)

echo "Detected : $OS  $VER  $ARCH"

if [[ "$OS" = "Ubuntu" && "$VER" = "14.04" ]] ; then
    echo "Ok."
else
    echo "Sorry, this OS is not supported by FOS-Streaming." 
    exit 1
fi

if [[ "$ARCH" == "i386" || "$ARCH" == "i486" || "$ARCH" == "i586" || "$ARCH" == "i686" ]]; then
ARCH="i386"
elif [[ "$ARCH" == "x86_64" || "$ARCH" == "amd64" ]]; then
ARCH="x86_64"
else
echo "Unexpected architecture name was returned ($ARCH ). :-("
echo "The installer have been designed for i[3-6]8- and x86_64' architectures. If you"
echo " think it may work on your, please report it to the Issue."
exit 1
fi

# Check if the user is 'root' before allowing installation to commence
if [ $UID -ne 0 ]; then
    echo "Install failed: you must be logged in as 'root' to install."
    echo "Use command 'sudo -i', then enter root password and then try again."
    exit 1
fi

# Check for some common control panels that we know will affect the installation/operating of FOS-Streaming.
if [ -e /usr/local/cpanel ] || [ -e /usr/local/directadmin ] || [ -e /usr/local/solusvm/www ] || [ -e /usr/local/home/admispconfig ] || [ -e /usr/local/lxlabs/kloxo ] || [ -e /etc/zpanel ] || [ -e /etc/zpanelx ] || [ -e /etc/sentora ] ; then
    echo "It appears that a control panel is already installed on your server; This installer"
    echo "is designed to install and configure FOS-Streaming on a clean OS installation only."
    echo -e "\nPlease re-install your OS before attempting to install using this script."
    exit 1
fi

# Check for some common packages that we know will affect the installation/operating of FOS-Streaming.
    PACKAGE_INSTALLER="apt-get -yqq install"
    PACKAGE_REMOVER="apt-get -yqq remove"

    inst() {
       dpkg -l "$1" 2> /dev/null | grep '^ii' &> /dev/null
    }
    
    DB_PCKG="mysql-server-5.5 mysql-server-core-5.5"
    HTTP_PCKG="apache2 libapache2-mod-php5 phpmyadmin"
    PHP_PCKG="php5 php5-mysql php5-fpm php5-curl"
    MY_CNF_PATH="/etc/mysql/my.cnf"
    
    if [ "$ARCH" == "i386" ]; then
    FFMPEGFILE=ffmpeg-release-32bit-static.tar.xz
    else
    FFMPEGFILE=ffmpeg-release-64bit-static.tar.xz
    fi

    pkginst="n"
    pkginstlist=""
    for package in "$DB_PCKG" "$HTTP_PCKG" "$PHP_PCKG" ; do
        if (inst "$package"); then
            pkginst="y" # At least one package is installed
            pkginstlist="$package $pkginstlist"
        fi
    done
    if [ $pkginst = "y" ]; then
        echo "It appears that the folowing package(s) are already installed:"
        echo "$pkginstlist"
        echo "This installer is designed to install and configure FOS-Streaming on a clean OS installation only!"
        echo -e "\nPlease re-install your OS before attempting to install using this script."
        exit 1
    fi
    unset pkginst
    unset pkginstlist
    
# *************************************************
#--- Prepare or query informations required to install

# Update repositories and Install wget and util used to grab server IP
echo -e "\n-- Installing wget and dns utils required to manage inputs"
apt-get -yqq update   #ensure we can install
$PACKAGE_INSTALLER dnsutils wget

extern_ip="$(wget -qO- http://andy.kimpe.free.fr/ip.php)"
#local_ip=$(ifconfig eth0 | sed -En 's|.*inet [^0-9]*(([0-9]*\.){3}[0-9]*).*$|\1|p')
local_ip=$(ip addr show | awk '$1 == "inet" && $3 == "brd" { sub (/\/.*/,""); print $2 }')

if [[ "$tz" == "" ]] ; then
    # Propose selection list for the time zone
    echo "Preparing to select timezone, please wait a few seconds..."
    $PACKAGE_INSTALLER tzdata
    # setup server timezone
        dpkg-reconfigure tzdata
        tz=$(cat /etc/timezone)
fi
# clear timezone information to focus user on important notice
clear

# Installer parameters
if [[ "$PUBLIC_IP" == "" ]] ; then
    PUBLIC_IP=$extern_ip
    while true; do
        echo ""
        if [[ "$PUBLIC_IP" != "$local_ip" ]]; then
          echo -e "\nThe public IP of the server is $PUBLIC_IP. Its local IP is $local_ip"
          echo "  For a production server, the PUBLIC IP must be used."
        fi  
        read -e -p "Enter (or confirm) the public IP for this server: " -i "$PUBLIC_IP" PUBLIC_IP
        echo ""
        if [[ "$PUBLIC_IP" != "$extern_ip" && "$PUBLIC_IP" != "$local_ip" ]]; then
            echo -e -n "\e[1;31mWARNING: $PUBLIC_IP does not match detected IP !\e[0m"
            echo "  FOS-Streaming will not work with this IP..."
                confirm="true"
        fi
        echo ""
        # if any warning, ask confirmation to continue or propose to change
        if [[ "$confirm" != "" ]] ; then
            echo "There are some warnings..."
            echo "Are you really sure that you want to setup FOS-Streaming with these parameters?"
            read -e -p "(y):Accept and install, (n):Change IP, (q):Quit installer? " yn
            case $yn in
                [Yy]* ) break;;
                [Nn]* ) continue;;
                [Qq]* ) exit;;
            esac
        else
            read -e -p "All is ok. Do you want to install FOS-Streaming now (y/n)? " yn
            case $yn in
                [Yy]* ) break;;
                [Nn]* ) exit;;
            esac
        fi
    done
fi

# ***************************************
# Installation really starts here

#--- Set custom logging methods so we create a log file in the current working directory.
logfile=$(date +%Y-%m-%d_%H.%M.%S_fos_streaming_install.log)
touch "$logfile"
exec > >(tee "$logfile")
exec 2>&1

echo "Installer version $FOS_STREAMING_INSTALLER_VERSION"
echo "FOS-Streaming core version $FOS_STREAMING_CORE_VERSION"
echo ""
echo "Installing FOS-Streaming $FOS_STREAMING_CORE_VERSION at http://$PUBLIC_IP:8000"
echo "on server under: $OS  $VER  $ARCH"
uname -a

# Function to disable a file by appending its name with _disabled
disable_file() {
    mv -f "$1" "$1_disabled_by_fos_streaming" &> /dev/null
}

# Function to save a file
save_file() {
    cp -f "$1" "$1_saved_by_fos_streaming" &> /dev/null
}

passwordgen() {
    l=$1
    [ "$l" == "" ] && l=16
    tr -dc A-Za-z0-9 < /dev/urandom | head -c ${l} | xargs
}

#--- AppArmor must be disabled to avoid problems
    [ -f /etc/init.d/apparmor ]
    if [ $? = "0" ]; then
        echo -e "\n-- Disabling and removing AppArmor, please wait..."
        /etc/init.d/apparmor stop &> /dev/null
        update-rc.d -f apparmor remove &> /dev/null
        apt-get purge -y apparmor* &> /dev/null
        disable_file /etc/init.d/apparmor &> /dev/null
        echo -e "AppArmor has been removed."
    fi
    
mkdir -p "/etc/apt/sources.list.d.save"
cp -Rf "/etc/apt/sources.list.d/*" "/etc/apt/sources.list.d.save" &> /dev/null
rm -rf "/etc/apt/sources.list/*"
save_file "/etc/apt/sources.list"
cat > /etc/apt/sources.list <<EOF
#Depots main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu $(lsb_release -sc) main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu $(lsb_release -sc)-security main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu $(lsb_release -sc)-updates main restricted universe multiverse
EOF


#--- List all already installed packages (may help to debug)
echo -e "\n-- Listing of all packages installed:"
dpkg --get-selection

#--- Ensures that all packages are up to date
echo -e "\n-- Updating+upgrading system, it may take some time..."
apt-get -yqq update
apt-get -yqq dist-upgrade

#--- Install utility packages required by the installer and/or FOS-Streaming.
echo -e "\n-- Downloading and installing required tools..."
echo ""
echo ""
# Disable the DPKG prompts before we run the software install to enable fully automated install.
export DEBIAN_FRONTEND=noninteractive
echo -e "\n-- Downloading and installing libxml2-dev please wait ..."
$PACKAGE_INSTALLER libxml2-dev
echo -e "\n-- Downloading and installing libbz2-dev please wait ..."
$PACKAGE_INSTALLER libbz2-dev
echo -e "\n-- Downloading and installing libcurl4-openssl-dev please wait ..."
$PACKAGE_INSTALLER libcurl4-openssl-dev
echo -e "\n-- Downloading and installing libmcrypt-dev please wait ..."
$PACKAGE_INSTALLER libmcrypt-dev
echo -e "\n-- Downloading and installing libmhash2 please wait ..."
$PACKAGE_INSTALLER libmhash2
echo -e "\n-- Downloading and installing curl please wait ..."
$PACKAGE_INSTALLER curl
echo -e "\n-- Downloading and installing libmhash-dev please wait ..."
$PACKAGE_INSTALLER libmhash-dev
echo -e "\n-- Downloading and installing libpcre3 please wait ..."
$PACKAGE_INSTALLER libpcre3
echo -e "\n-- Downloading and installing libpcre3-dev please wait ..."
$PACKAGE_INSTALLER libpcre3-dev
echo -e "\n-- Downloading and installing make please wait ..."
$PACKAGE_INSTALLER make
echo -e "\n-- Downloading and installing build-essential please wait ..."
$PACKAGE_INSTALLER build-essential
echo -e "\n-- Downloading and installing libxslt1-dev please wait ..."
$PACKAGE_INSTALLER libxslt1-dev
echo -e "\n-- Downloading and installing git please wait ..."
$PACKAGE_INSTALLER git
echo -e "\n-- Downloading and installing libssl-dev please wait ..."
$PACKAGE_INSTALLER libssl-dev
echo -e "\n-- Downloading and installing zip unzip please wait ..."
$PACKAGE_INSTALLER zip unzip
echo -e "\n-- Downloading and installing $HTTP_PCKG please wait ..."
$PACKAGE_INSTALLER $HTTP_PCKG
echo -e "\n-- Downloading and installing $PHP_PCKG please wait ..."
$PACKAGE_INSTALLER $PHP_PCKG
echo -e "\n-- Downloading and installing $DB_PCKG  please wait ..."
# solve problems remove mysql package and database
$PACKAGE_REMOVER $DB_PCKG
rm -rf /var/lib/mysql
$PACKAGE_INSTALLER $DB_PCKG
echo -e "\n-- Downloading and installing python-software-properties please wait ..."
$PACKAGE_INSTALLER python-software-properties
echo -e "\n-- Downloading and installing libpopt0 please wait ..."
$PACKAGE_INSTALLER libpopt0
echo -e "\n-- Downloading and installing libpq-dev please wait ..."
$PACKAGE_INSTALLER libpq-dev
echo -e "\n-- Downloading and installing libpq5 please wait ..."
$PACKAGE_INSTALLER libpq5
echo -e "\n-- Downloading and installing libpspell-dev please wait ..."
$PACKAGE_INSTALLER libpspell-dev
echo -e "\n-- Downloading and installing libpthread-stubs0-dev please wait ..."
$PACKAGE_INSTALLER libpthread-stubs0-dev
echo -e "\n-- Downloading and installing libpython-stdlib please wait ..."
$PACKAGE_INSTALLER libpython-stdlib
echo -e "\n-- Downloading and installing libqdbm-dev please wait ..."
$PACKAGE_INSTALLER libqdbm-dev
echo -e "\n-- Downloading and installing libqdbm14 please wait ..."
$PACKAGE_INSTALLER libqdbm14
echo -e "\n-- Downloading and installing libquadmath0 please wait ..."
$PACKAGE_INSTALLER libquadmath0
echo -e "\n-- Downloading and installing librecode-dev please wait ..."
$PACKAGE_INSTALLER librecode-dev
echo -e "\n-- Downloading and installing librecode0 please wait ..."
$PACKAGE_INSTALLER librecode0
echo -e "\n-- Downloading and installing librtmp-dev please wait ..."
$PACKAGE_INSTALLER librtmp-dev
echo -e "\n-- Downloading and installing librtmp0 please wait ..."
$PACKAGE_INSTALLER librtmp0
echo -e "\n-- Downloading and installing libsasl2-dev please wait ..."
$PACKAGE_INSTALLER libsasl2-dev
echo -e "\n-- Downloading and installing libsasl2-modules please wait ..."
$PACKAGE_INSTALLER libsasl2-modules
echo -e "\n-- Downloading and installing libsctp-dev please wait ..."
$PACKAGE_INSTALLER libsctp-dev
echo -e "\n-- Downloading and installing libsctp1 please wait ..."
$PACKAGE_INSTALLER libsctp1
echo -e "\n-- Downloading and installing libsensors4 please wait ..."
$PACKAGE_INSTALLER libsensors4
echo -e "\n-- Downloading and installing libsensors4-dev please wait ..."
$PACKAGE_INSTALLER libsensors4-dev
echo -e "\n-- Downloading and installing libsm-dev please wait ..."
$PACKAGE_INSTALLER libsm-dev
echo -e "\n-- Downloading and installing libsm6 please wait ..."
$PACKAGE_INSTALLER libsm6
echo -e "\n-- Downloading and installing libsnmp-base please wait ..."
$PACKAGE_INSTALLER libsnmp-base
echo -e "\n-- Downloading and installing libsnmp-dev please wait ..."
$PACKAGE_INSTALLER libsnmp-dev
echo -e "\n-- Downloading and installing libsnmp-perl please wait ..."
$PACKAGE_INSTALLER libsnmp-perl
echo -e "\n-- Downloading and installing libsnmp30 please wait ..."
$PACKAGE_INSTALLER libsnmp30
echo -e "\n-- Downloading and installing libsqlite3-dev please wait ..."
$PACKAGE_INSTALLER libsqlite3-dev
echo -e "\n-- Downloading and installing libssh2-1 please wait ..."
$PACKAGE_INSTALLER libssh2-1
echo -e "\n-- Downloading and installing libssh2-1-dev please wait ..."
$PACKAGE_INSTALLER libssh2-1-dev
echo -e "\n-- Downloading and installing libstdc++-4.8-dev please wait ..."
$PACKAGE_INSTALLER libstdc++-4.8-dev
echo -e "\n-- Downloading and installing libstdc++6-4.7-dev please wait ..."
$PACKAGE_INSTALLER libstdc++6-4.7-dev
echo -e "\n-- Downloading and installing libsybdb5 please wait ..."
$PACKAGE_INSTALLER libsybdb5
echo -e "\n-- Downloading and installing libtasn1-3-dev please wait ..."
$PACKAGE_INSTALLER libtasn1-3-dev
echo -e "\n-- Downloading and installing libtasn1-6-dev please wait ..."
$PACKAGE_INSTALLER libtasn1-6-dev
echo -e "\n-- Downloading and installing libterm-readkey-perl please wait ..."
$PACKAGE_INSTALLER libterm-readkey-perl
echo -e "\n-- Downloading and installing libtidy-0.99-0 please wait ..."
$PACKAGE_INSTALLER libtidy-0.99-0
echo -e "\n-- Downloading and installing libtidy-dev please wait ..."
$PACKAGE_INSTALLER libtidy-dev
echo -e "\n-- Downloading and installing libtiff5 please wait ..."
$PACKAGE_INSTALLER libtiff5
echo -e "\n-- Downloading and installing libtiff5-dev please wait ..."
$PACKAGE_INSTALLER libtiff5-dev
echo -e "\n-- Downloading and installing libtiffxx5 please wait ..."
$PACKAGE_INSTALLER libtiffxx5
echo -e "\n-- Downloading and installing libtimedate-perl please wait ..."
$PACKAGE_INSTALLER libtimedate-perl
echo -e "\n-- Downloading and installing libtinfo-dev please wait ..."
$PACKAGE_INSTALLER libtinfo-dev
echo -e "\n-- Downloading and installing libtool please wait ..."
$PACKAGE_INSTALLER libtool
echo -e "\n-- Downloading and installing libtsan0 please wait ..."
$PACKAGE_INSTALLER libtsan0
echo -e "\n-- Downloading and installing libunistring0 please wait ..."
$PACKAGE_INSTALLER libunistring0
echo -e "\n-- Downloading and installing libvpx-dev please wait ..."
$PACKAGE_INSTALLER libvpx-dev
echo -e "\n-- Downloading and installing libvpx1 please wait ..."
$PACKAGE_INSTALLER libvpx1
echo -e "\n-- Downloading and installing libwrap0-dev please wait ..."
$PACKAGE_INSTALLER libwrap0-dev
echo -e "\n-- Downloading and installing libx11-6 please wait ..."
$PACKAGE_INSTALLER libx11-6
echo -e "\n-- Downloading and installing libx11-data please wait ..."
$PACKAGE_INSTALLER libx11-data
echo -e "\n-- Downloading and installing libx11-dev please wait ..."
$PACKAGE_INSTALLER libx11-dev
echo -e "\n-- Downloading and installing libxau-dev please wait ..."
$PACKAGE_INSTALLER libxau-dev
echo -e "\n-- Downloading and installing libxau6 please wait ..."
$PACKAGE_INSTALLER libxau6
echo -e "\n-- Downloading and installing libxcb1 please wait ..."
$PACKAGE_INSTALLER libxcb1
echo -e "\n-- Downloading and installing libxcb1-dev please wait ..."
$PACKAGE_INSTALLER libxcb1-dev
echo -e "\n-- Downloading and installing libxdmcp-dev please wait ..."
$PACKAGE_INSTALLER libxdmcp-dev
echo -e "\n-- Downloading and installing libxdmcp6 please wait ..."
$PACKAGE_INSTALLER libxdmcp6
echo -e "\n-- Downloading and installing libxmltok1 please wait ..."
$PACKAGE_INSTALLER libxmltok1
echo -e "\n-- Downloading and installing libxmltok1-dev please wait ..."
$PACKAGE_INSTALLER libxmltok1-dev
echo -e "\n-- Downloading and installing libxpm-dev please wait ..."
$PACKAGE_INSTALLER libxpm-dev
echo -e "\n-- Downloading and installing libxpm4 please wait ..."
$PACKAGE_INSTALLER libxpm4
echo -e "\n-- Downloading and installing libxslt1.1 please wait ..."
$PACKAGE_INSTALLER libxslt1.1
echo -e "\n-- Downloading and installing libxt-dev please wait ..."
$PACKAGE_INSTALLER libxt-dev
echo -e "\n-- Downloading and installing libxt6 please wait ..."
$PACKAGE_INSTALLER libxt6
echo -e "\n-- Downloading and installing linux-libc-dev please wait ..."
$PACKAGE_INSTALLER linux-libc-dev
echo -e "\n-- Downloading and installing m4 please wait ..."
$PACKAGE_INSTALLER m4
echo -e "\n-- Downloading and installing man-db please wait ..."
$PACKAGE_INSTALLER man-db
echo -e "\n-- Downloading and installing netcat-openbsd please wait ..."
$PACKAGE_INSTALLER netcat-openbsd
echo -e "\n-- Downloading and installing odbcinst1debian2 please wait ..."
$PACKAGE_INSTALLER odbcinst1debian2
echo -e "\n-- Downloading and installing openssl please wait ..."
$PACKAGE_INSTALLER openssl
echo -e "\n-- Downloading and installing patch please wait ..."
$PACKAGE_INSTALLER patch
echo -e "\n-- Downloading and installing pkg-config please wait ..."
$PACKAGE_INSTALLER pkg-config
echo -e "\n-- Downloading and installing po-debconf please wait ..."
$PACKAGE_INSTALLER po-debconf
echo -e "\n-- Downloading and installing python please wait ..."
$PACKAGE_INSTALLER python
echo -e "\n-- Downloading and installing python-minimal please wait ..."
$PACKAGE_INSTALLER python-minimal
echo -e "\n-- Downloading and installing python2.7 please wait ..."
$PACKAGE_INSTALLER python2.7
echo -e "\n-- Downloading and installing python2.7-minimal please wait ..."
$PACKAGE_INSTALLER python2.7-minimal
echo -e "\n-- Downloading and installing re2c please wait ..."
$PACKAGE_INSTALLER re2c
echo -e "\n-- Downloading and installing unixodbc please wait ..."
$PACKAGE_INSTALLER unixodbc
echo -e "\n-- Downloading and installing unixodbc-dev please wait ..."
$PACKAGE_INSTALLER unixodbc-dev
echo -e "\n-- Downloading and installing uuid-dev please wait ..."
$PACKAGE_INSTALLER uuid-dev
echo -e "\n-- Downloading and installing x11-common please wait ..."
$PACKAGE_INSTALLER x11-common
echo -e "\n-- Downloading and installing x11proto-core-dev please wait ..."
$PACKAGE_INSTALLER x11proto-core-dev
echo -e "\n-- Downloading and installing x11proto-input-dev please wait ..."
$PACKAGE_INSTALLER x11proto-input-dev
echo -e "\n-- Downloading and installing x11proto-kb-dev please wait ..."
$PACKAGE_INSTALLER x11proto-kb-dev
echo -e "\n-- Downloading and installing xorg-sgml-doctools please wait ..."
$PACKAGE_INSTALLER xorg-sgml-doctools
echo -e "\n-- Downloading and installing libjpeg8 please wait ..."
$PACKAGE_INSTALLER libjpeg8
echo -e "\n-- Downloading and installing xtrans-dev please wait ..."
$PACKAGE_INSTALLER xtrans-dev
echo -e "\n-- Downloading and installing zlib1g-dev please wait ..."
$PACKAGE_INSTALLER zlib1g-dev

cd /usr/src/
rm -rf *
#--- Download nginx rtmp module archive from GitHub
echo -e "\n-- Downloading nginx rtmp module, Please wait, this may take several minutes, the installer will continue after this is complete!"
# Get latest sentora
while true; do
    wget -nv -O nginx-rtmp-module-1.1.7.zip https://codeload.github.com/arut/nginx-rtmp-module/zip/v1.1.7
    if [[ -f nginx-rtmp-module-1.1.7.zip ]]; then
        break;
    else
        echo "Failed to download nginx rtmp module from Github"
        echo "If you quit now, you can run again the installer later."
        read -e -p "Press r to retry or q to quit the installer? " resp
        case $resp in
            [Rr]* ) continue;;
            [Qq]* ) exit 3;;
        esac
    fi 
done

unzip nginx-rtmp-module-1.1.7.zip
rm -rf nginx-rtmp-module-1.1.7.zip

#--- Download nginx source archive
echo -e "\n-- Downloading nginx source archive, Please wait, this may take several minutes, the installer will continue after this is complete!"
# Get latest sentora
while true; do
    wget -nv -O nginx-1.9.2.tar.gz http://nginx.org/download/nginx-1.9.2.tar.gz
    if [[ -f nginx-1.9.2.tar.gz ]]; then
        break;
    else
        echo "Failed to download nginx source archive"
        echo "If you quit now, you can run again the installer later."
        read -e -p "Press r to retry or q to quit the installer? " resp
        case $resp in
            [Rr]* ) continue;;
            [Qq]* ) exit 3;;
        esac
    fi 
done

tar -xzf nginx-1.9.2.tar.gz
rm -rf nginx-1.9.2.tar.gz
cd /usr/src/nginx-1.9.2/
./configure --add-module=/usr/src/nginx-rtmp-module-1.1.7 --with-http_ssl_module --with-http_secure_link_module
make
make install


rm -r /usr/local/nginx/conf/nginx.conf
rm - rf /usr/src/nginx-rtmp-module-1.1.7 /usr/src/nginx-1.9.2/
cd /usr/src/
#--- Download FOS-Streaming core archive from GitHub
echo -e "\n-- Downloading FOS-Streaming core, Please wait, this may take several minutes, the installer will continue after this is complete!"
# Get latest FOS-Streaming
while true; do
    wget -nv -O FOS-Streaming-$FOS_STREAMING_CORE_VERSION.zip https://codeload.github.com/zgelici/FOS-Streaming/zip/$FOS_STREAMING_CORE_VERSION
    if [[ -f FOS-Streaming-$FOS_STREAMING_CORE_VERSION.zip ]]; then
        break;
    else
        echo "Failed to download FOS-Streaming core from Github"
        echo "If you quit now, you can run again the installer later."
        read -e -p "Press r to retry or q to quit the installer? " resp
        case $resp in
            [Rr]* ) continue;;
            [Qq]* ) exit 3;;
        esac
    fi 
done
unzip FOS-Streaming-$FOS_STREAMING_CORE_VERSION.zip
rm -f FOS-Streaming-$FOS_STREAMING_CORE_VERSION.zip
#--- Download FOS-Streaming core archive from GitHub
echo -e "\n-- Downloading FOS-Streaming installers, Please wait, this may take several minutes, the installer will continue after this is complete!"
# Get latest FOS-Streaming installers
while true; do
    wget -nv -O FOS-Streaming-installers-$FOS_STREAMING_INSTALLER_VERSION.zip https://codeload.github.com/andykimpe/FOS-Streaming-installers/zip/$FOS_STREAMING_INSTALLER_VERSION
    if [[ -f FOS-Streaming-installers-$FOS_STREAMING_INSTALLER_VERSION.zip ]]; then
        break;
    else
        echo "Failed to download FOS-Streaming installers from Github"
        echo "If you quit now, you can run again the installer later."
        read -e -p "Press r to retry or q to quit the installer? " resp
        case $resp in
            [Rr]* ) continue;;
            [Qq]* ) exit 3;;
        esac
    fi 
done
unzip FOS-Streaming-installers-$FOS_STREAMING_INSTALLER_VERSION.zip
rm -rf FOS-Streaming-installers-$FOS_STREAMING_INSTALLER_VERSION.zip

cd /usr/src/FOS-Streaming-$FOS_STREAMING_CORE_VERSION/
mv /usr/src/FOS-Streaming-installers-$FOS_STREAMING_INSTALLER_VERSION/nginx.conf /usr/local/nginx/conf/nginx.conf
mv /usr/src/FOS-Streaming-$FOS_STREAMING_CORE_VERSION/* /usr/local/nginx/html/
cd /usr/src/
rm -rf /usr/src/FOS-Streaming-$FOS_STREAMING_CORE_VERSION/
curl -sS https://getcomposer.org/installer | php
mv composer.phar /usr/local/bin/composer
cd /usr/local/nginx/html/
composer require illuminate/database
if ! grep -q "www-data ALL = (root) NOPASSWD: /usr/local/bin/ffmpeg" /etc/sudoers; then
    echo "www-data ALL = (root) NOPASSWD: /usr/local/bin/ffmpeg" >> /etc/sudoers;
fi
if ! grep -q "www-data ALL = (root) NOPASSWD: /usr/local/bin/ffprobe" /etc/sudoers; then
    echo "www-data ALL = (root) NOPASSWD: /usr/local/bin/ffprobe" >> /etc/sudoers;
fi
mkdir /usr/local/nginx/html/hl
chmod -R 777 /usr/local/nginx/html/hl
mkdir /usr/local/nginx/html/cache
chmod -R 777 /usr/local/nginx/html/cache
chown www-data:www-data /usr/local/nginx/conf
rm -rf /etc/init.d/nginx
mv /usr/src/FOS-Streaming-installers-$FOS_STREAMING_INSTALLER_VERSION/nginx-init-ubuntu/nginx /etc/init.d/nginx
chmod +x /etc/init.d/nginx
update-rc.d nginx defaults
### database import
service nginx start
echo "done"
echo "##Downloading and configuring ffmpeg##"
cd /usr/src/
wget http://johnvansickle.com/ffmpeg/releases/$FFMPEGFILE
tar -xvf $FFMPEGFILE
rm -rf $FFMPEGFILE
cd ffmpeg*
cp ffmpeg /usr/local/bin/ffmpeg
cp ffprobe /usr/local/bin/ffprobe
chmod 755 /usr/local/bin/ffmpeg
chmod 755 /usr/local/bin/ffprobe
cd /usr/src/
rm -r /usr/src/ffmpeg*
if [ -z "$mysqlpassword" ]; then
    mysqlpassword=$(passwordgen);
    mysqladmin -u root password "$mysqlpassword"
fi

# small cleaning of mysql access
mysql -u root -p"$mysqlpassword" -e "DELETE FROM mysql.user WHERE User='root' AND Host != 'localhost'";
mysql -u root -p"$mysqlpassword" -e "DELETE FROM mysql.user WHERE User=''";
mysql -u root -p"$mysqlpassword" -e "FLUSH PRIVILEGES";

# remove test table that is no longer used
mysql -u root -p"$mysqlpassword" -e "DROP DATABASE IF EXISTS test";

# secure SELECT "hacker-code" INTO OUTFILE 
sed -i "s|\[mysqld\]|&\nsecure-file-priv = /var/tmp|" $MY_CNF_PATH

mysql -u root -p"$mysqlpassword" < /usr/src/FOS-Streaming-installers-$FOS_STREAMING_INSTALLER_VERSION/install.sql
adminpassword=$(passwordgen)
adminpasswordmd5=$(echo -n $adminpassword | md5sum | awk '{print $1}')
rm -rf /usr/local/nginx/html/config.php
mv /usr/src/FOS-Streaming-installers-$FOS_STREAMING_INSTALLER_VERSION/config.php /usr/local/nginx/html/config.php
sed -i "s|YOUR_ROOT_MYSQL_PASSWORD|$mysqlpassword|" /usr/local/nginx/html/config.php
sed -i "s|YOUR_ADMIN_MYSQL_PASSWORD|$adminpasswordmd5|" /usr/src/FOS-Streaming-installers-$FOS_STREAMING_INSTALLER_VERSION/password.sql
mysql -u root -p"$mysqlpassword" < /usr/src/FOS-Streaming-installers-$FOS_STREAMING_INSTALLER_VERSION/password.sql
rm -rf /usr/src/FOS-Streaming-installers-$FOS_STREAMING_INSTALLER_VERSION/

#--- Store the passwords for user reference
echo "Server IP address : $PUBLIC_IP" >> /root/passwords.txt
echo "Panel URL         : http://$PUBLIC_IP:8000" >> /root/passwords.txt
echo "admin Password   : $adminpassword" >> /root/passwords.txt
echo "" >> /root/passwords.txt
echo "MySQL Root Password      : $mysqlpassword" >> /root/passwords.txt

#--- Advise the admin that FOS-Streaming is now installed and accessible.
echo "########################################################"  >/dev/tty
echo " Congratulations FOS-Streaming has now been installed on your" >/dev/tty
echo " server. Please review the log file left in /root/ for " >/dev/tty
echo " any errors encountered during installation." >/dev/tty
echo "" >/dev/tty
echo " Login to FOS-Streaming at http://$PUBLIC_IP:8000" >/dev/tty
echo " FOS-Streaming Username  : admin" >/dev/tty
echo " FOS-Streaming Password  : $adminpassword" >/dev/tty
echo "" >/dev/tty
echo " MySQL Root Password      : $mysqlpassword" >/dev/tty
echo "   (theses passwords are saved in /root/passwords.txt)" >/dev/tty
echo "########################################################" >/dev/tty
echo "" >/dev/tty

# Wait until the user have read before restarts the server...
if [[ "$INSTALL" != "auto" ]] ; then
    while true; do
        read -e -p "Restart your server now to complete the install (y/n)? " rsn
        case $rsn in
            [Yy]* ) break;;
            [Nn]* ) exit;
        esac
    done
    shutdown -r now
fi
