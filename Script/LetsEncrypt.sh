#!/bin/bash

#Script d'installation des protocoles HTTPS

#Vérifie que l'utilisateur est en root
verifierRoot(){
	if [ "$UID" -ne "0" ]
	then
	   echo "Vous n'est pas en root"
	   echo "Veuillez mettre \"sudo\" devant le script ou faire \"sudo su\""
	   exit 1
	fi
}

installationLets(){

	echo "Téléchargement de Let's Encrypt"
	git clone https://github.com/letsencrypt/letsencrypt /opt/letsencrypt
	cd /opt/letsencrypt
}


InstallationProtocoles(){

	domaine=$(whiptail --inputbox "Quel est votre nom de domaine" 8 78 --title "Nom de domaine" 3>&1 1>&2 2>&3)
	echo $domaine
	./letsencrypt-auto --apache -w /var/www/html/owncloud -d $domaine
	
}


verifierRoot
installationLets
installationProtocoles