#!/usr/bin/env bash
# PiVPN: Trivial OpenVPN setup and configuration
# Easiest setup and mangement of OpenVPN on Raspberry Pi
# http://pivpn.io
# Heavily adapted from the pi-hole.net project and...
# https://github.com/StarshipEngineer/OpenVPN-Setup/
#
# Install with this command (from your Pi):
#
# curl -L https://install.pivpn.io | bash
# Make sure you have `curl` installed


######## VARIABLES #########

tmpLog="/tmp/pivpn-install.log"
instalLogLoc="/etc/pivpn/install.log"

### PKG Vars ###
PKG_MANAGER="apt-get"
PKG_CACHE="/var/lib/apt/lists/"
UPDATE_PKG_CACHE="${PKG_MANAGER} update"
PKG_INSTALL="${PKG_MANAGER} --yes --no-install-recommends install"
PKG_COUNT="${PKG_MANAGER} -s -o Debug::NoLocking=true upgrade | grep -c ^Inst || true"
PIVPN_DEPS=( openvpn git dhcpcd5 tar wget grep iptables-persistent dnsutils expect whiptail )
###          ###

pivpnGitUrl="https://github.com/pivpn/pivpn.git"
pivpnFilesDir="/etc/.pivpn"
easyrsaVer="3.0.1-pivpn1"
easyrsaRel="https://github.com/pivpn/easy-rsa/releases/download/${easyrsaVer}/EasyRSA-${easyrsaVer}.tgz"

# Find the rows and columns. Will default to 80x24 if it can not be detected.
screen_size=$(stty size 2>/dev/null || echo 24 80)
rows=$(echo $screen_size | awk '{print $1}')
columns=$(echo $screen_size | awk '{print $2}')

# Divide by two so the dialogs take up half of the screen, which looks nice.
r=$(( rows / 2 ))
c=$(( columns / 2 ))
# Unless the screen is tiny
r=$(( r < 20 ? 20 : r ))
c=$(( c < 70 ? 70 : c ))

# Find IP used to route to outside world

IPv4dev=$(ip route get 8.8.8.8 | awk '{for(i=1;i<=NF;i++)if($i~/dev/)print $(i+1)}')
IPv4addr=$(ip route get 8.8.8.8| awk '{print $7}')
IPv4gw=$(ip route get 8.8.8.8 | awk '{print $3}')

availableInterfaces=$(ip -o link | grep "state UP" | awk '{print $2}' | cut -d':' -f1 | cut -d'@' -f1)
dhcpcdFile=/etc/dhcpcd.conf

######## FIRST CHECK ########
# Must be root to install
echo ":::"
if [[ $EUID -eq 0 ]];then
    echo "::: You are root."
else
    echo "::: sudo will be used for the install."
    # Check if it is actually installed
    # If it isn't, exit because the install cannot complete
    if [[ $(dpkg-query -s sudo) ]];then
        export SUDO="sudo"
        export SUDOE="sudo -E"
    else
        echo "::: Please install sudo or run this as root."
        exit 1
    fi
fi

# Next see if we are on a tested and supported OS
function noOS_Support() {
    whiptail --msgbox --backtitle "OS INVALID DETECTE" --title "OS non valide" "Nous n'avons pas été en mesure de détecter un OS pris en charge.
Actuellement, ce programme d'installation supporte Raspbian jessie, Ubuntu 14.04 et Ubuntu 16.04 (xenial).
Si vous pensez avoir reçu ce message par erreur, vous pouvez poster un problème sur le GitHub à l'adresse https://github.com/pivpn/pivpn/issues." ${r} ${c}
    exit 1
}

function maybeOS_Support() {
    if (whiptail --backtitle "OS Non Pris En Charge" --title "OS non pris en charge" --yesno "Vous êtes sur un OS que nous n'avons pas testé, mais PEUT travailler.
                 Actuellement, ce programme d'installation supporte Raspbian jessie, Ubuntu 14.04 (fidèle) et Ubuntu 16.04 (xenial).
                 Voulez-vous continuer de toute façon?" ${r} ${c}) then
                echo "::: N'a pas détecté un système d'exploitation parfaitement compatible mais,"
                echo "::: Peut poursuivre l'installation à vos propres risques ..."
            else
                echo "::: Quitter en raison de l'OS non pris en charge"
                exit 1
            fi
}

# if lsb_release command is on their system
if hash lsb_release 2>/dev/null; then
    PLAT=$(lsb_release -si)
    OSCN=$(lsb_release -sc) # We want this to be trusty xenial or jessie

    if [[ $PLAT == "Ubuntu" || $PLAT == "Raspbian" || $PLAT == "Debian" ]]; then
        if [[ $OSCN != "trusty" && $OSCN != "xenial" && $OSCN != "jessie" ]]; then
            maybeOS_Support
        fi
    else
        noOS_Support
    fi
# else get info from os-release
elif grep -q debian /etc/os-release; then
    if grep -q jessie /etc/os-release; then
        PLAT="Raspbian"
        OSCN="jessie"
    else
        PLAT="Ubuntu"
        OSCN="unknown"
        maybeOS_Support
    fi
# else we prob don't want to install
else
    noOS_Support
fi

echo "${PLAT}" > /tmp/DET_PLATFORM

####### FUNCTIONS ##########
spinner()
{
    local pid=$1
    local delay=0.50
    local spinstr='/-\|'
    while [ "$(ps a | awk '{print $1}' | grep "${pid}")" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "${spinstr}"
        local spinstr=${temp}${spinstr%"$temp"}
        sleep ${delay}
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

welcomeDialogs() {
    # Display the welcome dialog
    whiptail --msgbox --backtitle "Bienvenu" --title "PiVPN Automate Installeur" "Ce programme d'installation transformera votre Raspberry Pi en un serveur OpenVPN!" ${r} ${c}

    # Explain the need for a static address
    whiptail --msgbox --backtitle "Initialisation Interface réseau" --title "IP Statique Nécessaire" "Le PiVPN est un SERVEUR VPN, il doit donc avoir une ADRESSE IP STATIQUE pour fonctionner correctement.

Dans la section suivante, vous pouvez choisir d'utiliser vos paramètres de réseau actuels (DHCP) ou de les modifier manuellement." ${r} ${c}
}

chooseUser() {
    # Explain the local user
    whiptail --msgbox --backtitle "Analyse de la liste des utilisateurs" --title "Utilisateurs locaux" "Choisissez un utilisateur local qui aura vos configurations ovpn." ${r} ${c}
    # First, let's check if there is a user available.
    numUsers=$(awk -F':' 'BEGIN {count=0} $3>=500 && $3<=60000 { count++ } END{ print count }' /etc/passwd)
    if [ "$numUsers" -eq 0 ]
    then
        # We don't have a user, let's ask to add one.
        if userToAdd=$(whiptail --title "Choisissez un utilisateur" --inputbox "Aucun compte utilisateur non root n'a été trouvé. Tapez un nouveau nom d'utilisateur." ${r} ${c} 3>&1 1>&2 2>&3)
        then
            # See http://askubuntu.com/a/667842/459815
            PASSWORD=$(whiptail  --title "Boide de dialogue de mot de passe" --passwordbox "Entrez le nouveau mot de passe de l'utilisateur" ${r} ${c} 3>&1 1>&2 2>&3)
            CRYPT=$(perl -e 'printf("%s\n", crypt($ARGV[0], "password"))' "${PASSWORD}")
            $SUDO useradd -m -p "${CRYPT}" -s /bin/bash "${userToAdd}"
            if [[ $? = 0 ]]; then
                echo "Succeeded"
                ((numUsers+=1))
            else
                exit 1
            fi
        else
            exit 1
        fi
    fi
    availableUsers=$(awk -F':' '$3>=500 && $3<=60000 {print $1}' /etc/passwd)
    local userArray=()
    local firstloop=1

    while read -r line
    do
        mode="OFF"
        if [[ $firstloop -eq 1 ]]; then
            firstloop=0
            mode="ON"
        fi
        userArray+=("${line}" "" "${mode}")
    done <<< "${availableUsers}"
    chooseUserCmd=(whiptail --title "Choisissez un utilisateur" --separate-output --radiolist "Choisissez:" ${r} ${c} ${numUsers})
    chooseUserOptions=$("${chooseUserCmd[@]}" "${userArray[@]}" 2>&1 >/dev/tty)
    if [[ $? = 0 ]]; then
        for desiredUser in ${chooseUserOptions}; do
            pivpnUser=${desiredUser}
            echo "::: Utilisation de l'utilisateur : $pivpnUser"
            echo "${pivpnUser}" > /tmp/pivpnUSR
        done
    else
        echo "::: Cancel selected, exiting...."
        exit 1
    fi
}

verifyFreeDiskSpace() {
    # If user installs unattended-upgrades we'd need about 60MB so will check for 75MB free
    echo "::: Vérification de l'espace disque libre..."
    local required_free_kilobytes=76800
    local existing_free_kilobytes=$(df -Pk | grep -m1 '\/$' | awk '{print $4}')

    # - Unknown free disk space , not a integer
    if ! [[ "${existing_free_kilobytes}" =~ ^([0-9])+$ ]]; then
        echo "::: Espace disque libre inconnu!"
        echo "::: Nous n'avons pas pu déterminer l'espace disque libre disponible sur ce système."
        echo "::: Vous pouvez continuer avec l'installation, mais il n'est pas recommandé."
        read -r -p "::: Si vous êtes sûr de vouloir continuer, tapez OUI et appuyez sur Entrée :: " response
        case $response in
            [O][U][I])
                ;;
            *)
                echo "::: Confirmation non reçue, sortie ..."
                exit 1
                ;;
        esac
    # - Insufficient free disk space
    elif [[ ${existing_free_kilobytes} -lt ${required_free_kilobytes} ]]; then
        echo "::: Espace disque insuffisant !"
        echo "::: Votre système n'a pas assez d'espace disque. PiVPN recommande un minimum de $required_free_kilobytes KiloBytes."
        echo "::: Vous n'avez que ${existing_free_kilobytes} KiloBytes de libre."
        echo "::: S'il s'agit d'une nouvelle installation sur un Raspberry Pi, vous devrez peut-être développer votre disque."
        echo "::: Essayez d'exécuter 'sudo raspi-config', et choisissez l'option 'expand file system'"
        echo "::: Après le redémarrage, exécutez cette installation à nouveau."

        echo "Espace libre insuffisant, sortie ..."
        exit 1
    fi
}


chooseInterface() {
    # Turn the available interfaces into an array so it can be used with a whiptail dialog
    local interfacesArray=()
    # Number of available interfaces
    local interfaceCount
    # Whiptail variable storage
    local chooseInterfaceCmd
    # Temporary Whiptail options storage
    local chooseInterfaceOptions
    # Loop sentinel variable
    local firstLoop=1

    if [[ $(echo "${availableInterfaces}" | wc -l) -eq 1 ]]; then
      pivpnInterface="${availableInterfaces}"
      echo "${pivpnInterface}" > /tmp/pivpnINT
      return
    fi

    while read -r line; do
        mode="OFF"
        if [[ ${firstloop} -eq 1 ]]; then
            firstloop=0
            mode="ON"
        fi
        interfacesArray+=("${line}" "available" "${mode}")
    done <<< "${availableInterfaces}"

    # Find out how many interfaces are available to choose from
    interfaceCount=$(echo "${availableInterfaces}" | wc -l)
    chooseInterfaceCmd=(whiptail --separate-output --radiolist "Choisissez une interface (appuyez sur l'espace pour sélectionner)" ${r} ${c} ${interfaceCount})
    chooseInterfaceOptions=$("${chooseInterfaceCmd[@]}" "${interfacesArray[@]}" 2>&1 >/dev/tty)
    if [[ $? = 0 ]]; then
        for desiredInterface in ${chooseInterfaceOptions}; do
            pivpnInterface=${desiredInterface}
            echo "::: Utilisation de l'interface: $pivpnInterface"
            echo "${pivpnInterface}" > /tmp/pivpnINT
        done
    else
        echo "::: Annuler sélectionné, sorti...."
        exit 1
    fi
}

avoidStaticIPv4Ubuntu() {
    # If we are in Ubuntu then they need to have previously set their network, so just use what you have.
    whiptail --msgbox --backtitle "IP Information" --title "IP Information" "Comme nous pensons que vous n'utilisez pas Raspbian, nous ne configurerons pas une IP statique pour vous.
Si vous êtes sur Amazon, vous ne pouvez pas configurer une IP statique de toute façon. Assurez-vous que, avant l'installation de ce programme, vous avez configuré une IP statique sur votre instance." ${r} ${c}
}

getStaticIPv4Settings() {
    # Grab their current DNS Server
    IPv4dns=$(nslookup 127.0.0.1 | grep Server: | awk '{print $2}')
    # Ask if the user wants to use DHCP settings as their static IP
    if (whiptail --backtitle "Calibrage de l'interface réseau" --title "Adresse IP statique" --yesno "Voulez-vous utiliser vos paramètres réseau actuels comme une adresse statique?
                     Adresse IP: 	${IPv4addr}
                     Passerelle: 	${IPv4gw}" ${r} ${c}); then
        # If they choose yes, let the user know that the IP address will not be available via DHCP and may cause a conflict.
        whiptail --msgbox --backtitle "IP information" --title "FYI: conflit d'IP" "Il est possible que votre routeur puisse toujours essayer d'attribuer cette IP à un périphérique, ce qui entraînerait un conflit. Mais dans la plupart des cas, le routeur est assez intelligent pour ne pas le faire.
Si vous êtes inquiet, définissez manuellement l'adresse ou modifiez le pool de réservation DHCP, de sorte qu'il n'inclut pas l'adresse IP souhaitée.
Il est également possible d'utiliser une réservation DHCP, mais si vous allez le faire, vous pouvez également définir une adresse statique." ${r} ${c}
        # Nothing else to do since the variables are already set above
    else
        # Otherwise, we need to ask the user to input their desired settings.
        # Start by getting the IPv4 address (pre-filling it with info gathered from DHCP)
        # Start a loop to let the user enter their information with the chance to go back and edit it if necessary
        until [[ ${ipSettingsCorrect} = True ]]; do
            # Ask for the IPv4 address
            IPv4addr=$(whiptail --backtitle "Calibrage de l'interface réseau" --title "Adresse IPv4" --inputbox "Entrez votre adresse IPv4 souhaitée" ${r} ${c} "${IPv4addr}" 3>&1 1>&2 2>&3)
            if [[ $? = 0 ]]; then
            echo "::: Votre adresse IPv4 statique:    ${IPv4addr}"
            # Ask for the gateway
            IPv4gw=$(whiptail --backtitle "Calibrage de l'interface réseau" --title "IPv4 gateway (router)" --inputbox "Entrez votre passerelle par défaut IPv4 souhaitée" ${r} ${c} "${IPv4gw}" 3>&1 1>&2 2>&3)
            if [[ $? = 0 ]]; then
                echo "::: Votre passerelle statique IPv4:    ${IPv4gw}"
                # Give the user a chance to review their settings before moving on
                if (whiptail --backtitle "Calibrage de l'interface réseau" --title "Adresse IP statique" --yesno "Ces paramètres sont-ils corrects ?
                    Adresse IP:    ${IPv4addr}
                    Passerelle:    ${IPv4gw}" ${r} ${c}); then
                    # If the settings are correct, then we need to set the pivpnIP
                    echo "${IPv4addr%/*}" > /tmp/pivpnIP
                    echo "$pivpnInterface" > /tmp/pivpnINT
                    # After that's done, the loop ends and we move on
                    ipSettingsCorrect=True
                else
                    # If the settings are wrong, the loop continues
                    ipSettingsCorrect=False
                fi
            else
                # Cancelling gateway settings window
                ipSettingsCorrect=False
                echo "::: Annuler sélectionné. En sortant ..."
                exit 1
            fi
        else
            # Cancelling IPv4 settings window
            ipSettingsCorrect=False
            echo "::: Annuler sélectionné. En sortant ..."
            exit 1
        fi
        done
        # End the if statement for DHCP vs. static
    fi
}

setDHCPCD() {
    # Append these lines to dhcpcd.conf to enable a static IP
    echo "interface ${pivpnInterface}
    static ip_address=${IPv4addr}
    static routers=${IPv4gw}
    static domain_name_servers=${IPv4dns}" | $SUDO tee -a ${dhcpcdFile} >/dev/null
}

setStaticIPv4() {
    # Tries to set the IPv4 address
    if [[ -f /etc/dhcpcd.conf ]]; then
        if grep -q "${IPv4addr}" ${dhcpcdFile}; then
            echo "::: IP statique déjà configurée."
            :
        else
            setDHCPCD
            $SUDO ip addr replace dev "${pivpnInterface}" "${IPv4addr}"
            echo ":::"
            echo "::: Définir IP à ${IPv4addr}. Vous devrez peut-être redémarrer une fois l'installation terminée."
            echo ":::"
        fi
    else
        echo "::: Critique: Impossible de localiser le fichier de configuration pour définir l'adresse statique IPv4!"
        exit 1
    fi
}

setNetwork() {
    # Sets the Network IP and Mask correctly
    LOCALMASK=$(ifconfig "${pivpnInterface}" | awk '/Mask:/{ print $4;} ' | cut -c6-)
    LOCALIP=$(ifconfig "${pivpnInterface}" | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*')
    IFS=. read -r i1 i2 i3 i4 <<< "$LOCALIP"
    IFS=. read -r m1 m2 m3 m4 <<< "$LOCALMASK"
    LOCALNET=$(printf "%d.%d.%d.%d\n" "$((i1 & m1))" "$((i2 & m2))" "$((i3 & m3))" "$((i4 & m4))")
}

function valid_ip()
{
    local  ip=$1
    local  stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
        && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

installScripts() {
    # Install the scripts from /etc/.pivpn to their various locations
    $SUDO echo ":::"
    $SUDO echo -n "::: Installation de scripts dans /opt/pivpn ..."
    if [ ! -d /opt/pivpn ]; then
        $SUDO mkdir /opt/pivpn
        $SUDO chown "$pivpnUser":root /opt/pivpn
        $SUDO chmod u+srwx /opt/pivpn
    fi
    $SUDO cp /etc/.pivpn/scripts/makeOVPN.sh /opt/pivpn/makeOVPN.sh
    $SUDO cp /etc/.pivpn/scripts/clientStat.sh /opt/pivpn/clientStat.sh
    $SUDO cp /etc/.pivpn/scripts/listOVPN.sh /opt/pivpn/listOVPN.sh
    $SUDO cp /etc/.pivpn/scripts/removeOVPN.sh /opt/pivpn/removeOVPN.sh
    $SUDO cp /etc/.pivpn/scripts/uninstall.sh /opt/pivpn/uninstall.sh
    $SUDO cp /etc/.pivpn/scripts/pivpnDebug.sh /opt/pivpn/pivpnDebug.sh
    $SUDO cp /etc/.pivpn/scripts/fix_iptables.sh /opt/pivpn/fix_iptables.sh
    $SUDO chmod 0755 /opt/pivpn/{makeOVPN,clientStat,listOVPN,removeOVPN,uninstall,pivpnDebug,fix_iptables}.sh
    $SUDO cp /etc/.pivpn/pivpn /usr/local/bin/pivpn
    $SUDO chmod 0755 /usr/local/bin/pivpn
    $SUDO cp /etc/.pivpn/scripts/bash-completion /etc/bash_completion.d/pivpn
    . /etc/bash_completion.d/pivpn
    # Copy interface setting for debug
    $SUDO cp /tmp/pivpnINT /etc/pivpn/pivpnINTERFACE

    $SUDO echo " done."
}

package_check_install() {
    dpkg-query -W -f='${Status}' "${1}" 2>/dev/null | grep -c "ok installed" || ${PKG_INSTALL} "${1}"
}

update_package_cache() {
  #Running apt-get update/upgrade with minimal output can cause some issues with
  #requiring user input

  #Check to see if apt-get update has already been run today
  #it needs to have been run at least once on new installs!
  timestamp=$(stat -c %Y ${PKG_CACHE})
  timestampAsDate=$(date -d @"${timestamp}" "+%b %e")
  today=$(date "+%b %e")

  if [[ ${PLAT} == "Ubuntu" || ${PLAT} == "Debian" ]]; then
    if [[ ${OSCN} == "trusty" || ${OSCN} == "jessie" || ${OSCN} == "wheezy" ]]; then
      wget -O - https://swupdate.openvpn.net/repos/repo-public.gpg| $SUDO apt-key add -
      echo "deb http://swupdate.openvpn.net/apt $OSCN main" | $SUDO tee /etc/apt/sources.list.d/swupdate.openvpn.net.list > /dev/null
      echo -n "::: Ajout du correctif OpenVPN pour $PLAT $OSCN ..."
      $SUDO apt-get -qq update & spinner $!
      echo " done!"
    fi
  fi

  if [ ! "${today}" == "${timestampAsDate}" ]; then
    #update package lists
    echo ":::"
    echo -n "::: ${PKG_MANAGER} La mise à jour n'a pas été exécutée aujourd'hui. En cours d'exécution..."
    $SUDO ${UPDATE_PKG_CACHE} &> /dev/null
    echo " done!"
  fi
}

notify_package_updates_available() {
  # Let user know if they have outdated packages on their system and
  # advise them to run a package update at soonest possible.
  echo ":::"
  echo -n "::: Vérification de ${PKG_MANAGER} pour les packages mis à niveau ...."
  updatesToInstall=$(eval "${PKG_COUNT}")
  echo " done!"
  echo ":::"
  if [[ ${updatesToInstall} -eq "0" ]]; then
    echo "::: Votre système est à jour! Continuer avec l'installation de PiVPN ..."
  else
    echo "::: Il y a des mises à jour ${updatesToInstall} disponibles pour votre système!"
    echo "::: Nous vous recommandons de mettre à jour votre système après avoir installé PiVPN! "
    echo ":::"
  fi
}

install_dependent_packages() {
  # Install packages passed in via argument array
  # No spinner - conflicts with set -e
  declare -a argArray1=("${!1}")

  echo iptables-persistent iptables-persistent/autosave_v4 boolean true | $SUDO debconf-set-selections
  echo iptables-persistent iptables-persistent/autosave_v6 boolean false | $SUDO debconf-set-selections

  if command -v debconf-apt-progress &> /dev/null; then
    $SUDO debconf-apt-progress -- ${PKG_INSTALL} "${argArray1[@]}"
  else
    for i in "${argArray1[@]}"; do
      echo -n ":::    Vérification pour $i..."
      $SUDO package_check_install "${i}" &> /dev/null
      echo " installée!
"
    done
  fi
}

unattendedUpgrades() {
    whiptail --msgbox --backtitle "Mises à jour de sécurité" --title "Mises à jour sans surveillance" "Étant donné que ce serveur aura au moins un port ouvert sur Internet, il est recommandé d'activer les mises à niveau sans assistance.\nCette fonctionnalité vérifie quotidiennement les mises à jour des paquets de sécurité et applique-les au besoin.\nIl ne redémarrera pas automatiquement le serveur pour Appliquez pleinement certaines mises à jour que vous devriez réinitialiser périodiquement." ${r} ${c}

    if (whiptail --backtitle "Mises à jour de sécurité" --title "Mises à jour sans surveillance" --yesno "Voulez-vous activer les mises à niveau sans assistance des correctifs de sécurité sur ce serveur?" ${r} ${c}) then
        UNATTUPG="unattended-upgrades"
        $SUDO apt-get --yes --quiet --no-install-recommends install "$UNATTUPG" > /dev/null & spinner $!
    else
        UNATTUPG=""
    fi
}

stopServices() {
    # Stop openvpn
    $SUDO echo ":::"
    $SUDO echo -n "::: Arrêt du service OpenVPN ..."
    if [[ $PLAT == "Ubuntu" || $PLAT == "Debian" ]]; then
        $SUDO service openvpn stop || true
    else
        $SUDO systemctl stop openvpn.service || true
    fi
    $SUDO echo " done."
}

checkForDependencies() {
    #Running apt-get update/upgrade with minimal output can cause some issues with
    #requiring user input (e.g password for phpmyadmin see #218)
    #We'll change the logic up here, to check to see if there are any updates available and
    # if so, advise the user to run apt-get update/upgrade at their own discretion
    #Check to see if apt-get update has already been run today
    # it needs to have been run at least once on new installs!

    timestamp=$(stat -c %Y /var/cache/apt/)
    timestampAsDate=$(date -d @"$timestamp" "+%b %e")
    today=$(date "+%b %e")

    if [[ $PLAT == "Ubuntu" || $PLAT == "Debian" ]]; then
        if [[ $OSCN == "trusty" || $OSCN == "jessie" || $OSCN == "wheezy" ]]; then
            wget -O - https://swupdate.openvpn.net/repos/repo-public.gpg| $SUDO apt-key add -
            echo "deb http://swupdate.openvpn.net/apt $OSCN main" | $SUDO tee /etc/apt/sources.list.d/swupdate.openvpn.net.list > /dev/null
            echo -n "::: Ajout du correctif OpenVPN pour $PLAT $OSCN ..."
            $SUDO apt-get -qq update & spinner $!
            echo " done!"
        fi
    fi

    if [ ! "$today" == "$timestampAsDate" ]; then
        #update package lists
        echo ":::"
        echo -n "::: apt-get update n'a pas été exécuté aujourd'hui. En cours d'exécution ..."
        $SUDO apt-get -qq update & spinner $!
        echo " done!"
    fi
    echo ":::"
    echo -n "::: Vérification de mise à jour de paquets par l'apt-get ...."
    updatesToInstall=$($SUDO apt-get -s -o Debug::NoLocking=true upgrade | grep -c ^Inst)
    echo " done!"
    echo ":::"
    if [[ $updatesToInstall -eq "0" ]]; then
        echo "::: Votre pi est à jour! Continuer avec l'installation de PiVPN ..."
    else
        echo "::: Il y a $updatesToInstall mises à jour disponibles pour votre pi!"
        echo "::: Nous vous recommandons d'exécuter 'sudo apt-get upgrade' après l'installation de PiVPN!"
        echo ":::"
    fi
    echo ":::"
    echo "::: Vérification des dépendances:"

    dependencies=( openvpn git dhcpcd5 tar wget grep iptables-persistent dnsutils expect whiptail )
    for i in "${dependencies[@]}"; do
        echo -n ":::    Vérification pour $i..."
        if [ "$(dpkg-query -W -f='${Status}' "$i" 2>/dev/null | grep -c "ok installed")" -eq 0 ]; then
            echo -n " Pas trouvé! Installation ..."
            #Supply answers to the questions so we don't prompt user
            if [[ $i = "iptables-persistent" ]]; then
                echo iptables-persistent iptables-persistent/autosave_v4 boolean true | $SUDO debconf-set-selections
                echo iptables-persistent iptables-persistent/autosave_v6 boolean false | $SUDO debconf-set-selections
            fi
            if [[ $i == "expect" ]] || [[ $i == "openvpn" ]]; then
                ($SUDO apt-get --yes --quiet --no-install-recommends install "$i" > /dev/null || echo "L'installation a échoué!" && fixApt) & spinner $!
            else
                ($SUDO apt-get --yes --quiet install "$i" > /dev/null || echo "L'installation a échoué!" && fixApt) & spinner $!
            fi
            echo " terminé!"
        else
            echo " déjà installé!"
        fi
    done
}

getGitFiles() {
    # Setup git repos for base files
    echo ":::"
    echo "::: Vérification des fichiers de base existants ..."
    if is_repo "${1}"; then
        update_repo "${1}"
    else
        make_repo "${1}" "${2}"
    fi
}

is_repo() {
    # If the directory does not have a .git folder it is not a repo
    echo -n ":::    Vérification $1 est un repo..."
    cd "${1}" &> /dev/null || return 1
    $SUDO git status &> /dev/null && echo " OK!"; return 0 || echo " not found!"; return 1
}

make_repo() {
    # Remove the non-repos interface and clone the interface
    echo -n ":::    Clonage de $2 en $1 ..."
    $SUDO rm -rf "${1}"
    $SUDO git clone -q "${2}" "${1}" > /dev/null & spinner $!
    if [ -z "${TESTING+x}" ]; then
        :
    else
        $SUDO git -C "${1}" checkout test
    fi
    echo " done!"
}

update_repo() {
    # Pull the latest commits
    echo -n ":::     Mise à jour du repository dans $1..."
    cd "${1}" || exit 1
    $SUDO git stash -q > /dev/null & spinner $!
    $SUDO git pull -q > /dev/null & spinner $!
    if [ -z "${TESTING+x}" ]; then
        :
    else
        ${SUDOE} git checkout test
    fi
    echo " done!"
}

setCustomProto() {
  # Set the available protocols into an array so it can be used with a whiptail dialog
  if protocol=$(whiptail --title "Protocol" --radiolist \
  "Choisissez un protocole. S'il vous plaît, choisissez simplement TCP si vous savez pourquoi vous avez besoin de TCP." ${r} ${c} 2 \
  "UDP" "" ON \
  "TCP" "" OFF 3>&1 1>&2 2>&3)
  then
      # Convert option into lowercase (UDP->udp)
      pivpnProto="${protocol,,}"
      echo "::: Utilisation du protocole: $pivpnProto"
      echo "${pivpnProto}" > /tmp/pivpnPROTO
  else
      echo "::: Annuler sélectionné, sortir...."
      exit 1
  fi
    # write out the PROTO
    PROTO=$pivpnProto
    $SUDO cp /tmp/pivpnPROTO /etc/pivpn/INSTALL_PROTO
}


setCustomPort() {
    until [[ $PORTNumCorrect = True ]]
        do
            portInvalid="Invalide"

            PROTO=$(cat /etc/pivpn/INSTALL_PROTO)
            if [ "$PROTO" = "udp" ]; then
              DEFAULT_PORT=1194
            else
              DEFAULT_PORT=443
            fi
            if PORT=$(whiptail --title "Port OpenVPN par défaut" --inputbox "Vous pouvez modifier le port OpenVPN par défaut. \nEntrez une nouvelle valeur ou appuyez sur 'Entree' pour conserver le port par défaut" ${r} ${c} $DEFAULT_PORT 3>&1 1>&2 2>&3)
            then
                if [[ "$PORT" =~ ^[0-9]+$ ]] && [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ]; then
                    :
                else
                    PORT=$portInvalid
                fi
            else
                echo "::: Annuler sélectionné, sortie...."
                exit 1
            fi

            if [[ $PORT == "$portInvalid" ]]; then
                whiptail --msgbox --backtitle "Invalide Port" --title "Invalide Port" "Vous avez entré un numéro de port invalide.\n Entrez un numéro de 1 à 65535.\n Si vous n'êtes pas sûr, maintenez la valeur par défaut." ${r} ${c}
                PORTNumCorrect=False
            else
                if (whiptail --backtitle "Spécifiez le port personnalisé" --title "Confirmer le numéro de port personnalisé" --yesno "Ces paramètres sont-ils corrects?\n    PORT:   $PORT" ${r} ${c}) then
                    PORTNumCorrect=True
                else
                    # If the settings are wrong, the loop continues
                    PORTNumCorrect=False
                fi
            fi
        done
    # write out the port
    echo ${PORT} > /tmp/INSTALL_PORT
    $SUDO cp /tmp/INSTALL_PORT /etc/pivpn/INSTALL_PORT
}

setClientDNS() {
    DNSChoseCmd=(whiptail --separate-output --radiolist "Sélectionnez le fournisseur DNS pour vos clients VPN. Pour utiliser le vôtre, sélectionnez Personnalisé." ${r} ${c} 6)
    DNSChooseOptions=(Google "" on
            OpenDNS "" off
            Level3 "" off
            DNS.WATCH "" off
            Norton "" off
            Custom "" off)

    if DNSchoices=$("${DNSChoseCmd[@]}" "${DNSChooseOptions[@]}" 2>&1 >/dev/tty)
    then
        case ${DNSchoices} in
        Google)
            echo "::: Utilisation des serveurs DNS Google."
            OVPNDNS1="8.8.8.8"
            OVPNDNS2="8.8.4.4"
            # These are already in the file
            ;;
        OpenDNS)
            echo "::: Utilisation des serveurs OpenDNS."
            OVPNDNS1="208.67.222.222"
            OVPNDNS2="208.67.220.220"
            $SUDO sed -i '0,/\(dhcp-option DNS \)/ s/\(dhcp-option DNS \).*/\1'${OVPNDNS1}'\"/' /etc/openvpn/server.conf
            $SUDO sed -i '0,/\(dhcp-option DNS \)/! s/\(dhcp-option DNS \).*/\1'${OVPNDNS2}'\"/' /etc/openvpn/server.conf
            ;;
        Level3)
            echo "::: Utilisation des serveurs Level3."
            OVPNDNS1="209.244.0.3"
            OVPNDNS2="209.244.0.4"
            $SUDO sed -i '0,/\(dhcp-option DNS \)/ s/\(dhcp-option DNS \).*/\1'${OVPNDNS1}'\"/' /etc/openvpn/server.conf
            $SUDO sed -i '0,/\(dhcp-option DNS \)/! s/\(dhcp-option DNS \).*/\1'${OVPNDNS2}'\"/' /etc/openvpn/server.conf
            ;;
        DNS.WATCH)
            echo "::: Utilisation des serveurs DNS.WATCH."
            OVPNDNS1="84.200.69.80"
            OVPNDNS2="84.200.70.40"
            $SUDO sed -i '0,/\(dhcp-option DNS \)/ s/\(dhcp-option DNS \).*/\1'${OVPNDNS1}'\"/' /etc/openvpn/server.conf
            $SUDO sed -i '0,/\(dhcp-option DNS \)/! s/\(dhcp-option DNS \).*/\1'${OVPNDNS2}'\"/' /etc/openvpn/server.conf
            ;;
        Norton)
            echo "::: Utilisation des serveurs Norton ConnectSafe."
            OVPNDNS1="199.85.126.10"
            OVPNDNS2="199.85.127.10"
            $SUDO sed -i '0,/\(dhcp-option DNS \)/ s/\(dhcp-option DNS \).*/\1'${OVPNDNS1}'\"/' /etc/openvpn/server.conf
            $SUDO sed -i '0,/\(dhcp-option DNS \)/! s/\(dhcp-option DNS \).*/\1'${OVPNDNS2}'\"/' /etc/openvpn/server.conf
            ;;
        Custom)
            until [[ $DNSSettingsCorrect = True ]]
            do
                strInvalid="Invalide"

                if OVPNDNS=$(whiptail --backtitle "Specify Upstream DNS Provider(s)"  --inputbox "Entrez votre (vos) fournisseur (s) DNS en amont désiré, séparé par une virgule.\n\nPar exemple '8.8.8.8, 8.8.4.4'" ${r} ${c} "" 3>&1 1>&2 2>&3)
                then
                    OVPNDNS1=$(echo "$OVPNDNS" | sed 's/[, \t]\+/,/g' | awk -F, '{print$1}')
                    OVPNDNS2=$(echo "$OVPNDNS" | sed 's/[, \t]\+/,/g' | awk -F, '{print$2}')
                    if ! valid_ip "$OVPNDNS1" || [ ! "$OVPNDNS1" ]; then
                        OVPNDNS1=$strInvalid
                    fi
                    if ! valid_ip "$OVPNDNS2" && [ "$OVPNDNS2" ]; then
                        OVPNDNS2=$strInvalid
                    fi
                else
                    echo "::: Annuler sélectionné, sortir ..."
                    exit 1
                fi
                if [[ $OVPNDNS1 == "$strInvalid" ]] || [[ $OVPNDNS2 == "$strInvalid" ]]; then
                    whiptail --msgbox --backtitle "Invalide IP" --title "Invalide IP" "Une ou les deux adresses IP saisies étaient invalides. Veuillez réessayer.\n\n	Serveur DNS 1: $OVPNDNS1\n Serveur DNS 2: $OVPNDNS2" ${r} ${c}
                    if [[ $OVPNDNS1 == "$strInvalid" ]]; then
                        OVPNDNS1=""
                    fi
                    if [[ $OVPNDNS2 == "$strInvalid" ]]; then
                        OVPNDNS2=""
                    fi
                    DNSSettingsCorrect=False
                else
                    if (whiptail --backtitle "Spécifiez le (s) fournisseur (s) DNS DNS en amont" --title "Fournisseur(s) DNS en amont" --yesno "Ces paramètres sont-ils corrects?\n  Serveur DNS 1: $OVPNDNS1\n Serveur DNS 2: $OVPNDNS2" ${r} ${c}) then
                        DNSSettingsCorrect=True
                        $SUDO sed -i '0,/\(dhcp-option DNS \)/ s/\(dhcp-option DNS \).*/\1'${OVPNDNS1}'\"/' /etc/openvpn/server.conf
                        if [ -z ${OVPNDNS2} ]; then
                            $SUDO sed -i '/\(dhcp-option DNS \)/{n;N;d}' /etc/openvpn/server.conf
                        else
                            $SUDO sed -i '0,/\(dhcp-option DNS \)/! s/\(dhcp-option DNS \).*/\1'${OVPNDNS2}'\"/' /etc/openvpn/server.conf
                        fi
                    else
                        # If the settings are wrong, the loop continues
                        DNSSettingsCorrect=False
                    fi
                fi
        done
        ;;
    esac
    else
        echo "::: Annuler sélectionné. Sortie ..."
        exit 1
    fi
}

confOpenVPN() {
    # Ask user if want to modify default port
    SERVER_NAME="server"

    # Ask user for desired level of encryption
    ENCRYPT=$(whiptail --backtitle "Configuration OpenVPN" --title "Force de cryptage" --radiolist \
    "Choisissez le niveau de chiffrement souhaité:\n Il s'agit d'une clé de cryptage qui sera générée sur votre système. Plus la clé est grande, plus il faudra de temps. Pour la plupart des applications, il est recommandé d'utiliser 2048 bits. Si vous testez ou que vous voulez simplement passer à plus vite, vous pouvez utiliser 1024. Si vous êtes paranoïaque ... des choses ... puis prenez une coupe de joe et choisissez 4096." ${r} ${c} 3 \
    "2048" "Utilisez le cryptage 2048 bits. Niveau recommandé." ON \
    "1024" "Utilisez le cryptage 1024 bits. Niveau de test." OFF \
    "4096" "Utiliser un chiffrement 4096 bits. Niveau paranoïaque." OFF 3>&1 1>&2 2>&3)

    exitstatus=$?
    if [ $exitstatus != 0 ]; then
        echo "::: Annuler sélectionné. Sortie ..."
        exit 1
    fi

    # If easy-rsa exists, remove it
    if [[ -d /etc/openvpn/easy-rsa/ ]]; then
        $SUDO rm -rf /etc/openvpn/easy-rsa/
    fi

    # Get the PiVPN easy-rsa
    wget -q -O - "${easyrsaRel}" | $SUDO tar xz -C /etc/openvpn && $SUDO mv /etc/openvpn/EasyRSA-${easyrsaVer} /etc/openvpn/easy-rsa
    # fix ownership
    $SUDO chown -R root:root /etc/openvpn/easy-rsa
    $SUDO mkdir /etc/openvpn/easy-rsa/pki

    # Write out new vars file
    IFS= read -d '' String <<"EOF"
if [ -z "$EASYRSA_CALLER" ]; then
    echo "Nope." >&2
    return 1
fi
set_var EASYRSA            "/etc/openvpn/easy-rsa"
set_var EASYRSA_PKI        "$EASYRSA/pki"
set_var EASYRSA_KEY_SIZE   2048
set_var EASYRSA_ALGO       rsa
set_var EASYRSA_CURVE      secp384r1
EOF

echo "${String}" | $SUDO tee /etc/openvpn/easy-rsa/vars >/dev/null

    # Edit the KEY_SIZE variable in the vars file to set user chosen key size
    cd /etc/openvpn/easy-rsa || exit
    $SUDO sed -i "s/\(KEY_SIZE\).*/\1   ${ENCRYPT}/" vars

    # Remove any previous keys
    ${SUDOE} ./easyrsa --batch init-pki

    # Build the certificate authority
    printf "::: Gènèration du CA ...\n"
    ${SUDOE} ./easyrsa --batch build-ca nopass
    printf "\n::: CA Complete.\n"

    whiptail --msgbox --backtitle "Configuration OpenVPN" --title "Informations sur le serveur" "La clé du serveur, la clé Diffie-Hellman et la clé HMAC seront maintenant générées." ${r} ${c}

    # Build the server
    ${SUDOE} ./easyrsa build-server-full server nopass

    if ([ "$ENCRYPT" -ge "4096" ] && whiptail --backtitle "Configuration OpenVPN" --title "Télécharger les paramètres de Diffie-Hellman" --yesno --defaultno "Téléchargez les paramètres Diffie-Hellman à partir d'un service public de génération de paramètres DH?\n\nGénérer des paramètres DH pour un $ENCRYPT-bit La clé peut prendre plusieurs heures sur un Raspberry Pi. Vous pouvez alors télécharger les paramètres DH à partir de \"2 Ton Digital\" qui sont générés à intervalles réguliers dans le cadre d'un service public. Les paramètres DH téléchargés seront sélectionnés au hasard dans un pool des 128 derniers générés.\nVous trouverez plus d'informations sur ce service ici: https://2ton.com.au/dhtool/\n\nSi vous êtes paranoïaque, choisissez 'Non' et les paramètres de Diffie-Hellman seront générés sur votre appareil." ${r} ${c})
then
    # Downloading parameters
    RANDOM_INDEX=$(( RANDOM % 128 ))
    ${SUDOE} curl "https://2ton.com.au/dhparam/${ENCRYPT}/${RANDOM_INDEX}" -o "/etc/openvpn/easy-rsa/pki/dh${ENCRYPT}.pem"
else
    # Generate Diffie-Hellman key exchange
    ${SUDOE} ./easyrsa gen-dh
    ${SUDOE} mv pki/dh.pem pki/dh${ENCRYPT}.pem
fi

    # Generate static HMAC key to defend against DDoS
    ${SUDOE} openvpn --genkey --secret pki/ta.key

    # Write config file for server using the template .txt file
    $SUDO cp /etc/.pivpn/server_config.txt /etc/openvpn/server.conf

    $SUDO sed -i "s/LOCALNET/${LOCALNET}/g" /etc/openvpn/server.conf
    $SUDO sed -i "s/LOCALMASK/${LOCALMASK}/g" /etc/openvpn/server.conf

    # Set the user encryption key size
    $SUDO sed -i "s/\(dh \/etc\/openvpn\/easy-rsa\/pki\/dh\).*/\1${ENCRYPT}.pem/" /etc/openvpn/server.conf

    # if they modified port put value in server.conf
    if [ $PORT != 1194 ]; then
        $SUDO sed -i "s/1194/${PORT}/g" /etc/openvpn/server.conf
    fi

    # if they modified protocol put value in server.conf
    if [ "$PROTO" != "udp" ]; then
        $SUDO sed -i "s/proto udp/proto tcp/g" /etc/openvpn/server.conf
    fi

    # write out server certs to conf file
    $SUDO sed -i "s/\(key \/etc\/openvpn\/easy-rsa\/pki\/private\/\).*/\1${SERVER_NAME}.key/" /etc/openvpn/server.conf
    $SUDO sed -i "s/\(cert \/etc\/openvpn\/easy-rsa\/pki\/issued\/\).*/\1${SERVER_NAME}.crt/" /etc/openvpn/server.conf
}

confUnattendedUpgrades() {
    if [[ $UNATTUPG == "unattended-upgrades" ]]; then
        if [[ $PLAT == "Ubuntu" ]]; then
            # Ubuntu 50unattended-upgrades should already just have security enabled
            # so we just need to configure the 10periodic file
            cat << EOT | $SUDO tee /etc/apt/apt.conf.d/10periodic >/dev/null
    APT::Periodic::Update-Package-Lists "1";
    APT::Periodic::Download-Upgradeable-Packages "1";
    APT::Periodic::AutocleanInterval "5";
    APT::Periodic::Unattended-Upgrade "1";
EOT
        else
            $SUDO sed -i '/\(o=Raspbian,n=jessie\)/c\"o=Raspbian,n=jessie,l=Raspbian-Security";\' /etc/apt/apt.conf.d/50unattended-upgrades
            cat << EOT | $SUDO tee /etc/apt/apt.conf.d/02periodic >/dev/null
    APT::Periodic::Enable "1";
    APT::Periodic::Update-Package-Lists "1";
    APT::Periodic::Download-Upgradeable-Packages "1";
    APT::Periodic::Unattended-Upgrade "1";
    APT::Periodic::AutocleanInterval "7";
    APT::Periodic::Verbose "0";
EOT
        fi
    fi

}

confNetwork() {
    # Enable forwarding of internet traffic
    $SUDO sed -i '/net.ipv4.ip_forward=1/s/^#//g' /etc/sysctl.conf
    $SUDO sysctl -p

    # if ufw enabled, configure that
    if hash ufw 2>/dev/null; then
        if $SUDO ufw status | grep -q inactive
        then
            noUFW=1
        else
            echo "::: UFW détecté est activé."
            echo "::: Ajout de règles UFW..."
            $SUDO cp /etc/.pivpn/ufw_add.txt /tmp/ufw_add.txt
            $SUDO sed -i 's/IPv4dev/'"$IPv4dev"'/' /tmp/ufw_add.txt
            $SUDO sed -i "s/\(DEFAULT_FORWARD_POLICY=\).*/\1\"ACCEPT\"/" /etc/default/ufw
            $SUDO sed -i -e '/delete these required/r /tmp/ufw_add.txt' -e//N /etc/ufw/before.rules
            $SUDO ufw allow "${PORT}/${PROTO}"
            $SUDO ufw allow from 10.8.0.0/24
            $SUDO ufw reload
            echo "::: La configuration UFW est terminée."
        fi
    else
        noUFW=1
    fi
    # else configure iptables
    if [[ $noUFW -eq 1 ]]; then
        echo 1 > /tmp/noUFW
        $SUDO iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o "$IPv4dev" -j MASQUERADE
        if [[ $PLAT == "Ubuntu" || $PLAT == "Debian" ]]; then
            $SUDO iptables-save | $SUDO tee /etc/iptables/rules.v4 > /dev/null
        else
            $SUDO netfilter-persistent save
        fi
    else
        echo 0 > /tmp/noUFW
    fi

    $SUDO cp /tmp/noUFW /etc/pivpn/NO_UFW
}

confOVPN() {
    if ! IPv4pub=$(dig +short myip.opendns.com @resolver1.opendns.com)
    then
        echo "dig failed, now trying to curl eth0.me"
        if ! IPv4pub=$(curl eth0.me)
        then
            echo "eth0.me failed, please check your internet connection/DNS"
            exit $?
        fi
    fi
    $SUDO cp /tmp/pivpnUSR /etc/pivpn/INSTALL_USER
    $SUDO cp /tmp/DET_PLATFORM /etc/pivpn/DET_PLATFORM

    # Set status that no certs have been revoked
    echo 0 > /tmp/REVOKE_STATUS
    $SUDO cp /tmp/REVOKE_STATUS /etc/pivpn/REVOKE_STATUS

    METH=$(whiptail --title "IP Public ou DNS" --radiolist "Les clients utiliseront-ils un nom de Domaine ou une adresse IP pour se connecter à votre serveur?" ${r} ${c} 2 \
    "$IPv4pub" "Utilisez cette adresse IP publique" "ON" \
    "Entréer DNS" "Utilisez un DNS public" "OFF" 3>&1 1>&2 2>&3)

    exitstatus=$?
    if [ $exitstatus != 0 ]; then
        echo "::: Annuler sélectionné. Sortie ..."
        exit 1
    fi

    $SUDO cp /etc/.pivpn/Default.txt /etc/openvpn/easy-rsa/pki/Default.txt

    if [ "$METH" == "$IPv4pub" ]; then
        $SUDO sed -i 's/IPv4pub/'"$IPv4pub"'/' /etc/openvpn/easy-rsa/pki/Default.txt
    else
        until [[ $publicDNSCorrect = True ]]
        do
            PUBLICDNS=$(whiptail --title "Configuration PiVPN" --inputbox "Quel est le nom DNS public de ce serveur?" ${r} ${c} 3>&1 1>&2 2>&3)
            exitstatus=$?
            if [ $exitstatus != 0 ]; then
            echo "::: Annuler sélectionné. Sortie..."
            exit 1
            fi
            if (whiptail --backtitle "Confirmer le nom DNS" --title "Confirmer le nom DNS" --yesno "Est-ce correct?\n\n Nom DNS public:  $PUBLICDNS" ${r} ${c}) then
                publicDNSCorrect=True
                $SUDO sed -i 's/IPv4pub/'"$PUBLICDNS"'/' /etc/openvpn/easy-rsa/pki/Default.txt
            else
                publicDNSCorrect=False

            fi
        done
    fi

    # if they modified port put value in Default.txt for clients to use
    if [ $PORT != 1194 ]; then
        $SUDO sed -i -e "s/1194/${PORT}/g" /etc/openvpn/easy-rsa/pki/Default.txt
    fi

    # if they modified protocol put value in Default.txt for clients to use
    if [ "$PROTO" != "udp" ]; then
        $SUDO sed -i -e "s/proto udp/proto tcp/g" /etc/openvpn/easy-rsa/pki/Default.txt
    fi

    # verify server name to strengthen security
    $SUDO sed -i "s/SRVRNAME/${SERVER_NAME}/" /etc/openvpn/easy-rsa/pki/Default.txt

    $SUDO mkdir "/home/$pivpnUser/ovpns"
    $SUDO chmod 0777 -R "/home/$pivpnUser/ovpns"
}

installPiVPN() {
    stopServices
    confUnattendedUpgrades
    $SUDO mkdir -p /etc/pivpn/
    getGitFiles ${pivpnFilesDir} ${pivpnGitUrl}
    installScripts
    setCustomProto
    setCustomPort
    confOpenVPN
    confNetwork
    confOVPN
    setClientDNS
}

displayFinalMessage() {
    # Final completion message to user
    if [[ $PLAT == "Ubuntu" || $PLAT == "Debian" ]]; then
        $SUDO service openvpn start
    else
        $SUDO systemctl enable openvpn.service
        $SUDO systemctl start openvpn.service
    fi

    whiptail --msgbox --backtitle "Faire en sorte." --title "Installation complète!" "Maintenant, exécutez 'pivpn add' pour créer les profils ovpn.
Exécutez 'pivpn help' pour voir quoi d'autre vous pouvez faire!
Le journal d'installation se trouve dans /etc/pivpn." ${r} ${c}
    if (whiptail --title "Redémarrer" --yesno --defaultno "Il est fortement recommandé de redémarrer après l'installation. Voulez-vous redémarrer maintenant?" ${r} ${c}); then
        whiptail --title "Redémarrage" --msgbox "Le système va maintenant redémarrer." ${r} ${c}
        printf "\nRedémarrage du système...\n"
        $SUDO sleep 3
        $SUDO shutdown -r now
    fi
}

######## SCRIPT ############
# Verify there is enough disk space for the install
verifyFreeDiskSpace

# Install the packages (we do this first because we need whiptail)
#checkForDependencies
update_package_cache

notify_package_updates_available

install_dependent_packages PIVPN_DEPS[@]

# Start the installer
welcomeDialogs

# Find interfaces and let the user choose one
chooseInterface

# Only try to set static on Raspbian, otherwise let user do it
if [[ $PLAT != "Raspbian" ]]; then
    avoidStaticIPv4Ubuntu
else
    getStaticIPv4Settings
    setStaticIPv4
fi

setNetwork

# Choose the user for the ovpns
chooseUser

# Ask if unattended-upgrades will be enabled
unattendedUpgrades

# Install
installPiVPN | tee ${tmpLog}

#Move the install log into /etc/pivpn for storage
$SUDO mv ${tmpLog} ${instalLogLoc}

displayFinalMessage

echo "::: Install Complete..."
