#!/bin/sh

#Script installation du scriopt démarrage des connexions distant.

clear

echo "Donner l'adresse IP du serveur Samba :"
read ip
echo
echo "Donner un utilisateur pour se connecter au serveur Samba :"
read user
echo
echo "Donner le mot de passe de l'utilisateur"
read mdp

sed -i -e "s/a_changer_par_ip_serveur/$ip/g" S93Mount
sed -i -e "s/a_changer_par_user/$user/g" S93Mount
sed -i -e "s/a_changer_par_password/$mdp/g" S93Mount

echo
echo "Copie en cours"
mount -o remount, rw /
cp -f S93Mount /etc/init.d
cp -f consoles.txt /etc/init.d
chmod 755 /etc/init.d/S93Mount
echo "Copie terminé"

