#!/bin/bash

#Script Installation DLNA

utilisateur_principale=""
disques=""

#Vérifie que l'utilisateur est en root
verifierRoot(){
	if [ "$UID" -ne "0" ]
	then
	   echo "Vous n'est pas en root"
	   echo "Veuillez mettre \"sudo\" devant le script ou faire \"sudo su\""
	   exit 1
	fi
}


#Installation des ressources

installationRessources(){

	if (whiptail --title "Installation de DLNA" --yesno "Voulez vous installer DLNA ?" 8 78) then
		apt-get install minidlna
	else
    		echo "Echec de l'installation de DLNA"
	fi

}


#Modification du fichier minidlna.conf

modifDLNA(){

	sed -i -e "s/media_dir=\/var\/lib\/minidlna/media_dir=V,\/media\/DD1\/Videotheque/g" /etc/minidlna.conf
	sed -i -e "s/#root_container=./root_container=B/g" /etc/minidlna.conf
	sed -i -e "s/#friendly_name=/friendly_name=RaspberryPi/g" /etc/minidlna.conf
	sed -i -e "s/#inotify=yes/inotify=yes/g" /etc/minidlna.conf
	sed -i -e "s/#user=minidlna/user=minidlna/g" /etc/minidlna.conf
	sed -i -e "s/#USER=\"minidlna\"/USER=\"minidlna\"/g" /etc/default/minidlna
	sed -i -e "s/#GROUP=\"minidlna\"/GROUP=\"samba\"/g" /etc/default/minidlna
	sed -i -e "s/#CONFIGFILE=\"\/etc\/minidlna.conf\"/CONFIGFILE=\"\/etc\/minidlna.conf\"/g" /etc/default/minidlna
	sed -i -e "s/#notify_interval=895/notify_interval=5/g" /etc/minidlna.conf

}

modifDroit(){
	usermod -g samba minidlna
}



clear
verifierRoot
installationRessources
modifDLNA
modifDroit
service minidlna restart
service minidlna force-reload

