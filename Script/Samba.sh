#!/bin/bash

#Script Installation Samba

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

#Selectionne le ou les diques dur souhaité
selectDisk(){
	#On récupére les lecteurs connectés
	res=`fdisk -l | awk '/sd/ {print $1}' | cut -d'/' -f3`
	if [[ $res != "" ]]; then
		nbDD=0
		text=""
		#On fait la liste des lecteurs
		for lecteur in $res;
		do
			if [[ $lecteur == "sd"* ]] && [[ $lecteur != *":" ]] && [[ $lecteur != *"Extended" ]]; then
				size=`df -h | awk '/'$lecteur'/ {print $2}'`
				nbDD=$nbDD+1
				text=$text"$lecteur $size OFF "
			fi
		done
		#On insére les informations sur un affichage 
		#On demande de choisir
		choix=$(whiptail --clear --title "Checklist Box" --checklist "Quels disque dur voulez-vous utiliser ? (MAX : 2)\nPour selectionner un disque, appuyer sur ESPACE, PUIS sur ENTREE quand vous avez fini de choisir." 15 60 4 $text 3>&1 1>&2 2>&3)
		exitstatus=$?
		if [ $exitstatus = 0 ]; then
			IFS=' ' read -r -a listdisques <<< "$choix"
			if [[ $choix == "" ]]; then
				echo "Vous n'avez pas sélectionné de Disque dur. L'installation s'arrête !"
				exit 1
			elif [[ ${#listdisques[@]} > 2 ]]; then
				echo "ERREUR : Vous avez choisi plus de 2 disques dur"
				exit 1
			fi
		else
			echo "L'installation est annulé !"
			exit 1
		fi
		
		disques=$listdisques
		
	else
		echo "Aucun disque dur de branché, Veuillez brancher un disque dur et relancer le script"
		exit 1
	fi
}

#On configure les diques durs
configuration_dd(){
	listDD=$1
	nbDD=${#listDD[@]}
	if [ ! -d "/media/DD1" ]; then
		mkdir /media/DD1
	fi
	dd1=$(echo ${listDD[0]} | awk -F'"' '{print $2}')
	
	#On demonte le disque dur
	umount /dev/"$dd1"
	verifie_format_disque $dd1
	
	#On monte le disque dur
	mount -t auto /dev/"$dd1" /media/DD1
	
	#On récupére l'UUID du disque dur et on l'insére dans le fichier fstab
	uuid=`blkid /dev/$dd1 |sed -n 's/.* UUID=\"\([^\"]*\)\".*/\1/p'`
	echo "UUID=$uuid /media/DD1 ext4 defaults 0 0" >> /etc/fstab
	
	if [ ! -d "/media/DD1/Videotheque" ]; then
		mkdir /media/DD1/Videotheque
	fi
	if [ ! -d "/media/DD1/Videotheque/Films" ]; then
		mkdir /media/DD1/Videotheque/Films
	fi
	if [ ! -d "/media/DD1/Videotheque/Sèries" ]; then
		mkdir /media/DD1/Videotheque/Sèries
	fi
	if [ ! -d "/media/DD1/Videotheque/Animes" ]; then
		mkdir /media/DD1/Videotheque/Animes
	fi
	
	if [[ $nbDD > 1 ]]; then
		if [ ! -d "/media/DD2" ]; then
			mkdir /media/DD2
		fi
		dd2=$(echo ${listDD[1]} | awk -F'"' '{print $2}')
		umount /dev/"$dd2"
		mount -t auto /dev/"$dd2" /media/DD2
		verifie_format_disque $dd2
		uuid=`blkid /dev/$dd2 |sed -n 's/.* UUID=\"\([^\"]*\)\".*/\1/p'`
		echo "UUID=$uuid /media/DD2 ext4 defaults 0 0" >> /etc/fstab
		if [ ! -d "/media/DD2/Jeux" ]; then
			mkdir /media/DD2/Jeux
		fi
		while read line  
		do   
			if [ ! -d "/media/DD2/Jeux/$line" ]; then
				mkdir /media/DD2/Jeux/$line
			fi
		done < consoles.txt

	else
		if [ ! -d "/media/DD1/Jeux" ]; then
			mkdir /media/DD1/Jeux
		fi
		while read line  
		do   
			if [ ! -d "/media/DD1/Jeux/$line" ]; then
				mkdir /media/DD1/Jeux/$line
			fi
		done < consoles.txt
	fi
}

#On fait les créations de comptes
configuration_utilisateur(){
	#Création du groupe samba
	addgroup samba
	creation_utilisateur 1
	termine=0
	
	#On demande si il faut creer d'autres utilisateurs
	while [[ $termine != 1 ]]; do 
		if (whiptail --title "Création utilisateur" --yesno "Voulez-vous créer un autre utilisateur ?" 10 60) then
			creation_utilisateur 0
		else
			termine=1
		fi
	done
	useradd recalbox -p recalboxroot
	mkdir /home/recalbox
	usermod -g samba recalbox
	smbpasswd -a recalbox recalboxroot
	echo "Fini configuration_utilisateur"
}

#On installe notre configuration Samba
installation_samba(){
	listDD=$1
	nbDD=${#listDD[@]}
	
	chown -R $2:samba "/media/DD1" 
	chmod -R 750 "/media/DD1"
	
	if [[ $nbDD > 1 ]]; then
		chown -R $2:samba "/media/DD2" 
		chmod -R 750 "/media/DD2"
	fi
	
	#On modifie le fichier smb.conf
	mv /etc/samba/smb.conf /etc/samba/smb.conf.old
	echo '[global]'> /etc/samba/smb.conf
	echo 'workgroup = WORKGROUP'>> /etc/samba/smb.conf
	echo 'server string = "Samba"'>>  /etc/samba/smb.conf
	echo 'security = user'>> /etc/samba/smb.conf
	echo ''>> /etc/samba/smb.conf
	echo '[Videotheque]'>> /etc/samba/smb.conf
	echo 'comment = Vidéothèque'>> /etc/samba/smb.conf 
	echo 'path = "/media/DD1/Videotheque"'>> /etc/samba/smb.conf
	echo 'browseable = yes'>> /etc/samba/smb.conf
	echo 'read only = no'>> /etc/samba/smb.conf
	echo 'writable = yes'>> /etc/samba/smb.conf
	echo 'valid users = @samba'>> /etc/samba/smb.conf
	echo 'create mask = 0750'>> /etc/samba/smb.conf
	echo 'directory mask = 0750'>> /etc/samba/smb.conf
	echo " " >> /etc/samba/smb.conf
	echo '[Jeux]'>> /etc/samba/smb.conf
	echo 'comment = Jeux'>> /etc/samba/smb.conf 
	if [[ $nbDD > 1 ]]; then
		echo 'path = "/media/DD2/Jeux"'>> /etc/samba/smb.conf
	else
		echo 'path = "/media/DD1/Jeux"'>> /etc/samba/smb.conf
	fi
	echo 'browseable = yes'>> /etc/samba/smb.conf
	echo 'read only = no'>> /etc/samba/smb.conf
	echo 'writable = yes'>> /etc/samba/smb.conf
	echo 'valid users = @samba'>> /etc/samba/smb.conf
	echo 'create mask = 0750'>> /etc/samba/smb.conf
	echo 'directory mask = 0750'>> /etc/samba/smb.conf
	/etc/init.d/samba start
	whiptail --title "Installation Terminé" --msgbox "L'installation est terminé. Le systéme va redémarrer. Cliquer sur OK." 10 60
	reboot
}

verifie_format_disque(){
	format=`blkid /dev/$1 |sed -n 's/.*TYPE=\"\([^\"]*\)\".*/\1/p'`
	if [[ $format != "ext4" ]]; then 
			if (whiptail --title "Formater Disque dur" --yesno "ATTENTION : Votre disque dur $1 n'est pas au format Linux. Le formatage vous feras perdre toute les données sur le disque dur, voulez-vous le formater en EXT4 ?" 10 60) then
				mkfs.ext4 /dev/"$1"
			else
				echo "Veuillez relancer le script pour recommencer l'installation !"
				exit 1
			fi

		fi		
}

creation_utilisateur(){
	login=$(whiptail --inputbox "Donner un nom d'utilisateur :" 8 78 --title "Création d'un utilisateur" 3>&1 1>&2 2>&3)
	exitstatus=$?
	if [ $exitstatus = 0 ]; then
		if [[ $login == "" ]]; then
			echo "ERREUR : Le nom d'utilisateur ne peut pas être vide !"
			exit 1
		fi
	else
		echo "Vous avez annulé l'installation !"
		exit 1
	fi
	
	password=$(whiptail --passwordbox "Donner un mot de passe pour l'utilsateur $login :" 8 78 --title "Création d'un utilisateur" 3>&1 1>&2 2>&3)
	exitstatus=$?
	if [ $exitstatus = 0 ]; then
		if [[ $password == "" ]]; then
			echo "ERREUR : Le mot de passe de l'utilisateur $login ne peut pas être vide !"
			exit 1
		fi
	else
		echo "Vous avez annulé l'installation !"
		exit 1
	fi
	useradd $login -p $password
	mkdir /home/$login
	usermod -g samba $login
	smbpasswd -a $login $password
	(echo $password; echo $password ) | smbpasswd -s -a $login
	if [[ $1 == 1 ]]; then
		utilisateur_principale=$login
	fi
}

#On efface le terminal pour affichier proprement nos message
clear
#On vérifie que l'utilisaeur a lancé le script avec sudo
verifierRoot
#On mets à jour le système et on installe samba
echo "Avant de commencer l'installation, le système va vèrifier qu'il est à jour"
sleep 5
apt-get update -y
apt-get upgrade -y
apt-get install -y samba samba-common
#On crée des utilisateurs
configuration_utilisateur
#On sélectionne le ou les disque durs voulu
selectDisk
#On configures les diques durs
configuration_dd $disques
#On installe notre système sambapour la vidéothèque
installation_samba $disques $utilisateur_principale

