source /etc/profile
cd deploygentoo-master
scriptdir=$(pwd)
cd ..
LIGHTGREEN='\033[1;32m'
LIGHTBLUE='\033[1;34m'
##printf ${LIGHTBLUE}"Enter the disk name you want to install gentoo on (ex, sda)\n>"
##read disk
#disk="${disk,,}"
#printf ${LIGHTBLUE}"Enter the username for your NON ROOT user\n>"
##There is a possibility this won't work since the handbook creates a user after rebooting and logging as root
#read username
#username="${username,,}"
#printf ${LIGHTBLUE}"Enter Yes to make a kernel from scratch, edit to edit the hardened config, or No to use the default hardened config\n>"
#read kernelanswer
#kernelanswer="${kernelanswer,,}"
#printf ${LIGHTBLUE}"Enter the Hostname you want to use\n>"
#read hostname
#printf ${LIGHTBLUE}"Do you want to replace LibreSSL with OpenSSL in your system?(yes or no)\n>"
#read sslanswer
#sslanswer="${sslanswer,,}"
#mount /dev/sda1 /boot
install_vars=/mnt/gentoo/install_vars
disk=$(sed '1q;d' install_vars)
username=$(sed '2q;d' install_vars)
kernelanswer=$(sed '3q;d' install_vars)
hostname=$(sed '4q;d' install_vars)
sslanswer=$(sed '5q;d' install_vars)
cpus=$(sed '6q;d' install_vars)
part_3=$(sed '7q;d' install_vars)
part_1=$(sed '8q;d' install_vars)
part_2=$(sed '9q;d' install_vars)
part_4=$(sed '10q;d' install_vars)
dev_sd=("/dev/$disk")
mount $part_2 /boot
jobs=("-j${cpus}")
printf "%s jobs equals \n" % $jobs
printf "mounted boot\n"
#TODO everything below this point fails on musl, figure out why, error is Your current profile is invalid
#emerge-webrsync
#printf "webrsync complete\n"
emerge --sync --quiet
printf "sync complete\n"
sleep 10
filename=gentootype.txt
line=$(head -n 1 $filename)
#Checks what type of stage was used, and installs necessary overlays
case $line in
  latest-stage3-amd64-hardened)
    #TODO put stuff specific to gcc hardened here
    emerge --verbose --update --deep --newuse @world
    printf "big emerge complete\n"
    ;;
  latest-stage3-amd64-musl-hardened)
    eselect profile set --force 31
    echo "dev-vcs/git -gpg" >> /etc/portage/package.use
    emerge app-portage/layman dev-vcs/git
    layman -a musl
    emerge -uvNDq @world
    ;;
  latest-stage3-amd64-musl-vanilla)
    eselect profile set --force 30
    echo "dev-vcs/git -gpg" >> /etc/portage/package.use
    emerge app-portage/layman dev-vcs/git
    layman -a musl
    emerge -uvNDq @world
    ;;
esac


printf "preparing to do big emerge\n"

printf "America/New_York\n" > /etc/timezone
emerge --config sys-libs/timezone-data
printf "timezone data emerged\n"
#en_US.UTF-8 UTF-8
printf "en_US.UTF-8 UTF-8\n" >> /etc/locale.gen
locale-gen
mv deploygentoo-master/layman /var/lib/
cd /var/lib/layman
#git clone https://github.com/gentoo/libressl
printf "script complete\n"
eselect locale set 4
env-update && source /etc/profile

#Installs the kernel
printf "preparing to emerge kernel sources\n"
emerge sys-kernel/gentoo-sources
sleep 10
ls -l /usr/src/linux
cd /usr/src/linux
emerge sys-apps/pciutils
emerge app-arch/lzop
emerge app-arch/lz4
if [ $kernelanswer = "no" ]; then
	cp deploygentoo-master/gentoo/kernel/gentoohardenedminimal /usr/src/linux
	mv gentoohardenedminimal .config
	make olddefconfig
	make $jobs && make modules_install
	make install
	printf "Kernel installed\n"
elif [ $kernelanswer = "edit" ]; then
	cp /deploygentoo-master/gentoo/kernel/gentoohardenedminimal /usr/src/linux
	mv gentoohardenedminimal .config
	make menuconfig
	make $jobs && make modules_install
	make install
	printf "Kernel installed\n"
else
	printf "time to configure your own kernel\n"
	make menuconfig
	make $jobs && make modules_installl
	make install
	printf "Kernel installed\n"
fi

#enables DHCP
sed -i -e "s/localhost/$hostname/g" /etc/conf.d/hostname
emerge --noreplace net-misc/netifrc
printf "config_enp0s3=\"dhcp\"\n" >> /etc/conf.d/net
UUID2=$(blkid -s UUID -o value $part_2)
UUID2=("UUID=${UUID2}")
UUID3=$(blkid -s UUID -o value $part_3)
UUID3=("UUID=${UUID3}")
UUID4=$(blkid -s UUID -o value $part_4)
UUID4=("UUID=${UUID4}")
printf "%s\t\t/boot/efi\tvfat\t\tdefaults\t0 2\n" $UUID2 >> /etc/fstab
SUB_STR='/dev/'
if [[ "$part_3" == *"$SUB_STR"* ]]; then
    printf "%s\t\tnone\t swap\t\tsw\t\t0 0\n" $UUID3 >> /etc/fstab
fi
printf "%s\t\t/\t\text4\t\tnoatime\t0 1\n" $UUID4 >> /etc/fstab
cd /etc/init.d
ln -s net.lo net.enp0s3
rc-update add net.enp0s3 default
#printf "dhcp enabled\n"
emerge app-admin/sysklogd
emerge app-admin/sudo
#printf "just emerged sudo\n"
rm -rf /etc/sudoers
cd $scriptdir
cp sudoers /etc/
printf "installed sudo and enabled it for wheel group\n"
rc-update add sysklogd default
emerge sys-apps/mlocate
emerge net-misc/dhcpcd

#installs grub
emerge --verbose sys-boot/grub:2
#grub-install /dev/sda
grub-install $dev_sd
grub-mkconfig -o /boot/grub/grub.cfg
#printf "updated grub\n"
useradd -m -G users,wheel,audio -s /bin/bash $username
#printf "just tried to add our user\n"
cd ..
#printf "cleaning up\n"
mv deploygentoo-master.zip /home/$username
#rm -rf /deploygentoo-master
stage3=$(ls stage3*)
rm -rf $stage3
if [ $sslanswer = "yes" ]; then
	emerge gentoolkit
	mkdir -p /etc/portage/profile
	echo "-libressl" >> /etc/portage/profile/use.stable.mask
	echo "dev-libs/openssl" >> /etc/portage/package.mask
	echo "dev-libs/libressl" >> /etc/portage/package.accept_keywords
	emerge -f libressl
	emerge -C openssl
	emerge -1q libressl
	emerge -1q openssh wget python:2.7 python:3.6 iputils
	emerge -q @preserved-rebuild
else
	printf "nothing to do here\n"
fi

printf "preparing to exit the system, run the following commands and then reboot without the CD\n"
printf "you should now have a working Gentoo installation, dont forget to set your root and user passwords!\n"
#if [ $(id -u) -eq 0 ]; then
#	read -s -p "Enter your users password : " password
#    read -s -p "Enter your root password : " rootpassword
#	egrep "^$username" /etc/passwd >/dev/null
#	if [ $? -eq 0 ]; then
#		echo "$username exists!"
#		exit 1
#	else
#		pass=$(perl -e 'print crypt($ARGV[0], "password")' $password)
#        echo $password | passwd --stdin $username
#        echo $rootpassword | passwd --stdin root
#		[ $? -eq 0 ] && echo "User password has been updated" || echo "Failed to add a user!"
#	fi
#else
#	echo "Only root may add a user to the system"
#	exit 2
#fi
mv /mnt/gentoo/deploygentoo-master.zip /home/kenny/
while true; do
    printf ${LIGHTGREEN}"enter the password for your root user\n>"
    read $password
    printf ${LIGHTGREEN}"re-enter the password for your root user\n>"
    read $password_compare
    if [ "$password" = "$password_compare" ]; then
        echo "$password" | passwd root --stdin
        break
    else
        printf ${LIGHTRED}"passwords do not match, re enter them\n"
        printf ${WHITE}".\n"
        sleep 5
        clear
    fi
done
while true; do
    printf ${LIGHTGREEN}"enter the password for your user %s\n>" $username
    read $password
    printf ${LIGHTGREEN}"re-enter the password for %s\n>" $username
    read $password_compare
    if [ "$password" = "$password_compare" ]; then
        echo "$password" | passwd "$username" --stdin
        break
    else
        printf ${LIGHTRED}"passwords do not match, re enter them\n"
        printf ${WHITE}".\n"
        sleep 5
        clear
    fi
done
#printf ${LIGHTGREEN}"chroot /mnt/gentoo\n ONLY IF PASSWD %s doesn't work!!\n" $username
#printf ${LIGHTGREEN}"passwd\n"
#printf ${LIGHTGREEN}"passwd %s\n" $username
#printf ${LIGHTGREEN}"exit\n"
#printf ${LIGHTGREEN}"cd\n"
#printf ${LIGHTGREEN}"umount -l /mnt/gentoo/dev{/shm,/pts,}\n"
#printf ${LIGHTGREEN}"umount -R /mnt/gentoo\n"
printf ${LIGHTGREEN}"You now have a completed gentoo installation system, reboot and remove the installation media to load it\n"
printf ${LIGHTGREEN}"reboot\n"
rm -rf /post_chroot.sh
#exit
