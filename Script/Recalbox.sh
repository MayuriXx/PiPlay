#!/bin/bash

# Script montage Recalbox

ip_serveur="a_changer_par_ip_serveur"
user="a_changer_par_user"
password="a_changer_par_password"

function start(){
	ping $ip_serveur -c5 -q
	
	if [[ $? != 1 ]]; then
		mount -o remount, rw /
		if [ ! -d "/media/samba" ]; then
			mkdir /media/samba
		fi
		mount.cifs //$ip_serveur/Jeux /media/samba -o username=$user,password=$password
		while read line  
		do   
			if [ -d "/recalbox/share/roms/$line" ]; then
				ln -s /media/samba/$line /recalbox/share/roms/$line/distant
			fi
		done < consoles.txt
	else
		echo "Montage des jeux non démarré"
	fi
}

function stop(){
	while read line  
	do   
		if [ -d "/recalbox/share/roms/$line" ]; then
			unlink /recalbox/share/roms/$line/distant
		fi
	done < consoles.txt
	if [ -d "/media/samba" ]; then
		umount /media/samba
	fi
}

function restart(){
	stop
	start
}

mount -o remount, rw /
echo "$(date) Script executer" >> log.txt 
case $1 in
	start)
		start
		;;
	stop)
		stop
		;;
	retart)
		restart
		;;
	*)
		echo "Usage: {start|stop|restart}"
		start	
		;;	
esac

exit 0
