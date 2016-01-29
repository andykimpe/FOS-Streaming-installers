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
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.
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
    
    DB_PCKG="mysql-server"
    HTTP_PCKG="apache2"
    PHP_PCKG="apache2-mod-php5"

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

if [[ "$tz" == "" && "$PUBLIC_IP" == "" ]] ; then
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
            read -e -p "All is ok. Do you want to install Sentora now (y/n)? " yn
            case $yn in
                [Yy]* ) break;;
                [Nn]* ) exit;;
            esac
        fi
    done
fi

echo "install in progress"
exit

# ***************************************
# Installation really starts here

#--- Set custom logging methods so we create a log file in the current working directory.
logfile=$(date +%Y-%m-%d_%H.%M.%S_fos_streaming_install.log)
touch "$logfile"
exec > >(tee "$logfile")
exec 2>&1

echo "Installer version $FOS_STREAMING_INSTALLER_VERSION"
echo "Sentora core version $FOS_STREAMING_CORE_VERSION"
echo ""
echo "Installing Sentora $FOS_STREAMING_CORE_VERSION at http://$PUBLIC_IP:8000"
echo "on server under: $OS  $VER  $ARCH"
uname -a

# Function to disable a file by appending its name with _disabled
disable_file() {
    mv "$1" "$1_disabled_by_fos_streaming" &> /dev/null
}

# Function to save a file
save_file() {
    cp "$1" "$1_saved_by_fos_streaming" &> /dev/null
}

PS3='Please enter your choice: '
options=("Install full 32bit" "Install full 64bit" "Quit")
select system in "${options[@]}"
do
    case $system in
        "Install full 32bit")
	echo "##Update and upgrade system##"
		apt-get update && apt-get upgrade -y
		echo "done"
		echo "##Installing needed files##"
		rm -r /usr/src/FOS-Streaming
		apt-get install libxml2-dev libbz2-dev libcurl4-openssl-dev libmcrypt-dev libmhash2 curl -y
		apt-get install libmhash-dev libpcre3 libpcre3-dev make build-essential libxslt1-dev git -y
		apt-get install libssl-dev -y
		apt-get install git -y
		apt-get install apache2 libapache2-mod-php5 php5 php5-mysql mysql-server phpmyadmin php5-fpm php5-curl unzip -y
		echo "done"
	    echo "##Installing and configuring nginx and the FOS-Streaming panel##"
		#**************if you already have nginx remove it from this line**************#
		cd /usr/src/
		git clone https://github.com/arut/nginx-rtmp-module.git
		wget http://nginx.org/download/nginx-1.9.2.tar.gz
		tar -xzf nginx-1.9.2.tar.gz
		cd /usr/src/nginx-1.9.2/
		./configure --add-module=/usr/src/nginx-rtmp-module --with-http_ssl_module --with-http_secure_link_module
		make
		make install
		#cp /usr/src/nginx-rtmp-module/stat.xsl /usr/local/nginx
		 #**************NGINX INSTALL END LINE**************#
		rm -r /usr/local/nginx/conf/nginx.conf
		cd /usr/src/
		git clone https://github.com/zgelici/FOS-Streaming.git
		cd /usr/src/FOS-Streaming/
		mv /usr/src/FOS-Streaming/nginx.conf /usr/local/nginx/conf/nginx.conf
		mv /usr/src/FOS-Streaming/* /usr/local/nginx/html/
		cd /usr/src/
		curl -sS https://getcomposer.org/installer | php
		mv composer.phar /usr/local/bin/composer
		cd /usr/local/nginx/html/
		composer require illuminate/database
		echo 'www-data ALL = (root) NOPASSWD: /usr/local/bin/ffmpeg' >> /etc/sudoers
		echo 'www-data ALL = (root) NOPASSWD: /usr/local/bin/ffprobe' >> /etc/sudoers	
		sed --in-place '/exit 0/d' /etc/rc.local
		echo "sleep 10" >> /etc/rc.local
		echo "/usr/local/nginx/sbin/nginx" >> /etc/rc.local
		echo "exit 0" >> /etc/rc.local
		mkdir /usr/local/nginx/html/hl
		chmod -R 777 /usr/local/nginx/html/hl
		mkdir /usr/local/nginx/html/cache
		chmod -R 777 /usr/local/nginx/html/cache
		chown www-data:www-data /usr/local/nginx/conf
		wget https://raw.github.com/JasonGiedymin/nginx-init-ubuntu/master/nginx -O /etc/init.d/nginx
        chmod +x /etc/init.d/nginx
        update-rc.d nginx defaults
		### database import
		/usr/local/nginx/sbin/nginx
		echo "done"
            	echo "##Downloading and configuring ffmpeg 32bit##"
		cd /usr/src/
		wget http://johnvansickle.com/ffmpeg/builds/ffmpeg-git-32bit-static.tar.xz
		tar -xJf ffmpeg-git-32bit-static.tar.xz
		cd ffmpeg*
		cp ffmpeg /usr/local/bin/ffmpeg
		cp ffprobe /usr/local/bin/ffprobe
		chmod 755 /usr/local/bin/ffmpeg
		chmod 755 /usr/local/bin/ffprobe
		cd /usr/src/
		rm -r /usr/src/ffmpeg*
		echo "installation finshed."
		echo "go to http://host/phpmyadmin and upload the database.sql file which is located in /usr/local/nginx/html/"
		echo "configure /usr/local/nginx/html/config.php"
		echo "login: http://host:8000 username: admin - password: admin"
		echo "After login go to settings and change web ip port to your public server ip"
		exit
            ;;
        "Install full 64bit")
		echo "##Update and upgrade system##"
		apt-get update && apt-get upgrade -y
		echo "done"
		echo "##Installing needed files##"
		rm -r /usr/src/FOS-Streaming
		apt-get install libxml2-dev libbz2-dev libcurl4-openssl-dev libmcrypt-dev libmhash2 curl -y
		apt-get install libmhash-dev libpcre3 libpcre3-dev make build-essential libxslt1-dev git -y
		apt-get install libssl-dev -y
		apt-get install git -y
		apt-get install apache2 libapache2-mod-php5 php5 php5-mysql mysql-server phpmyadmin php5-fpm php5-curl unzip -y
		echo "done"
	    echo "##Installing and configuring nginx and the FOS-Streaming panel##"
		#**************if you already have nginx remove it from this line**************#
		cd /usr/src/
		git clone https://github.com/arut/nginx-rtmp-module.git
		wget http://nginx.org/download/nginx-1.9.2.tar.gz
		tar -xzf nginx-1.9.2.tar.gz
		cd /usr/src/nginx-1.9.2/
		./configure --add-module=/usr/src/nginx-rtmp-module --with-http_ssl_module --with-http_secure_link_module
		make
		make install
		#cp /usr/src/nginx-rtmp-module/stat.xsl /usr/local/nginx
		 #**************NGINX INSTALL END LINE**************#
		rm -r /usr/local/nginx/conf/nginx.conf
		cd /usr/src/
		git clone https://github.com/zgelici/FOS-Streaming.git
		cd /usr/src/FOS-Streaming/
		mv /usr/src/FOS-Streaming/nginx.conf /usr/local/nginx/conf/nginx.conf
		mv /usr/src/FOS-Streaming/* /usr/local/nginx/html/
		cd /usr/src/
		curl -sS https://getcomposer.org/installer | php
		mv composer.phar /usr/local/bin/composer
		cd /usr/local/nginx/html/
		composer require illuminate/database
		echo 'www-data ALL = (root) NOPASSWD: /usr/local/bin/ffmpeg' >> /etc/sudoers
		echo 'www-data ALL = (root) NOPASSWD: /usr/local/bin/ffprobe' >> /etc/sudoers	
		sed --in-place '/exit 0/d' /etc/rc.local
		echo "sleep 10" >> /etc/rc.local
		echo "/usr/local/nginx/sbin/nginx" >> /etc/rc.local
		echo "exit 0" >> /etc/rc.local
		
		mkdir /usr/local/nginx/html/hl
		chmod -R 777 /usr/local/nginx/html/hl
		mkdir /usr/local/nginx/html/cache
		chmod -R 777 /usr/local/nginx/html/cache
		chown www-data:www-data /usr/local/nginx/conf
		wget https://raw.github.com/JasonGiedymin/nginx-init-ubuntu/master/nginx -O /etc/init.d/nginx
        chmod +x /etc/init.d/nginx
        update-rc.d nginx defaults
		### database import
		/usr/local/nginx/sbin/nginx
		echo "done"
               echo "Downloading and configuring ffmpeg 64bit"
		cd /usr/src/
		wget http://johnvansickle.com/ffmpeg/releases/ffmpeg-release-64bit-static.tar.xz
		tar -xJf ffmpeg-release-64bit-static.tar.xz
		cd ffmpeg*
		cp ffmpeg /usr/local/bin/ffmpeg
		cp ffprobe /usr/local/bin/ffprobe
		chmod 755 /usr/local/bin/ffmpeg
		chmod 755 /usr/local/bin/ffprobe
		chown www-data:root /usr/local/nginx/html
		cd /usr/src/
		rm -r /usr/src/ffmpeg*
		echo "installation finshed."
		echo "go to http://host/phpmyadmin and upload the database.sql file which is located in /usr/local/nginx/html/"
		echo "configure /usr/local/nginx/html/config.php"
		echo "login: http://host:8000 username: admin - password: admin"
		echo "After login go to settings and change web ip port to your public server ip"
		exit
            ;;
        "Quit")
            break
            ;;
        *) echo invalid option;;
    esac
done
