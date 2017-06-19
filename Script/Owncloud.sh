#!/bin/bash

#Script Installation Owncloud

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

	if (whiptail --title "Installation de Owncloud" --yesno "Voulez vous installer Owncloud ?" 8 78) then
		apt-get install apache2 php5 php5-gd php-xml-parser php5-intl
		apt-get install php5-sqlite php5-mysql smbclient curl libcurl3 php5-curl
		cd  /home/pi/Downloads
		sudo wget http://download.owncloud.org/community/owncloud-10.0.2.tar.bz2
		tar -xjf owncloud-10.0.2.tar.bz2
		echo "Déplacement de owncloud dans le dossier html"
		sudo cp -r owncloud /var/www/html/
		sudo chown -R www-data:www-data /var/www/html/owncloud 
	else
    		echo "Echec de l'installation de Owncloud"
	fi

}


#Modification du fichier apache2.conf

modifApache2(){

	
		ligneA=$(sed -n '/<Directory \/>/=' /etc/apache2/apache2.conf)
		echo "Ligne de la première balise Directory :" $ligneA
		ligneB=$(sed -n '/<\/Directory\>/=' /etc/apache2/apache2.conf)
		ligneB=$(echo $ligneB | cut -d " " -f 1)
		echo "Ligne de la deuxieme balise Directory : " $ligneB
		sed -i "$ligneA,$ligneB s/AllowOverride None/AllowOverride All/g" /etc/apache2/apache2.conf

}


#Vérification du fichier htaccess
verifFichier(){

	if [ -f /var/www/html/owncloud/.htaccess ]
	then
        	echo "Le fichier .htaccess est bien présent"
	else
        	echo "Le fichier n'est pas présent"
        	touch .htaccess
        	chown www-data:www-data .htaccess
	fi
	a2enmod rewrite
	a2enmod headers

}


#Mettre owncloud sur le disque dur
copieVersDD(){
	
	sudo service apache2 stop
	echo "Arrêt d'apache2"
	cd /media/DD1/
	mkdir /media/DD1/Owncloud/
	sudo mv /var/www/html/owncloud/data /media/DD1/Owncloud/data
	sudo ln -s /media/DD1/Owncloud/data /var/www/html/owncloud/data
	sudo mv /var/www/html/owncloud/config /media/DD1/Owncloud/config
	sudo ln -s /media/DD1/Owncloud/config /var/www/html/owncloud/config
	sudo chown -R www-data:www-data /media/DD1/Owncloud

}


clear
verifierRoot
clear
installationRessources
clear
sleep 5
modifApache2
clear
verifFichier
sudo service apache2 restart
copieVersDD
echo "Redémarrage d'Apache2"
service apache2 restart 

