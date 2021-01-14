#!/bin/bash

# DISCLAIMER: It is not a good idea to store large amounts of Bitcoin on a VPS,
# ideally you should use this as a watch-only wallet. This script is experimental
# and has not been widely tested. 
# The creators are not responsible for loss of
# funds. If you are not familiar with running a node or how Bitcoin works then we
# urge you to use this in testnet so that you can use it as a learning tool.

# This script installs the latest stable version of Tor, Bitcoin Core,
# Uncomplicated Firewall (UFW), debian updates, enables automatic updates for
# debian for good security practices, installs a random number generator, and
# optionally a QR encoder and an image displayer.

# The script will display the uri in plain text which you can convert to a QR Code
# yourself. It is highly recommended to add a Tor V3 pubkey for cookie authentication
# so that even if your QR code is compromised an attacker would not be able to access
# your node.

# StandUp.sh sets Tor and Bitcoin Core up as systemd services so that they start
# automatically after crashes or reboots. By default it sets up a pruned testnet node,
# a Tor V3 hidden service controlling your rpcports and enables the firewall to only
# allow incoming connections for SSH. If you supply a SSH_KEY in the arguments
# it allows you to easily access your node via SSH using your rsa pubkey, if you add
# SYS_SSH_IP's your VPS will only accept SSH connections from those IP's.

# StandUp.sh will create a user called standup, and assign the optional password you
# give it in the arguments.

# StandUp.sh will create two logs in your root directory, to read them run:
# $ cat standup.err
# $ cat standup.log

####
#0. Prerequisites
####

# In order to run this script you need to be logged in as root, and enter in the commands
# listed below:

# (the $ represents a terminal commmand prompt, do not actually type in a $)

# First you need to give the root user a password:
# $ sudo passwd

# Then you need to switch to the root user:
# $ su - root

# Then create the file for the script:
# $ nano standup.sh

# Nano is a text editor that works in a terminal, you need to paste the entire contents
# of this script into your terminal after running the above command,
# then you can type:
# control x (this starts to exit nano)
# y (this confirms you want to save the file)
# return (just press enter to confirm you want to save and exit)
# git clone https://github.com/matthiasdebernardini/Bitcoin-Standup-Scripts.git

# Then we need to make sure the script can be executable with:
# $ chmod +x standup.sh
# chmod +x Bitcoin-Standup-Scripts/Scripts/StandUp.sh
# ./Bitcoin-Standup-Scripts/Scripts/StandUp.sh "" "Pruned Testnet" "" "" "79ff6f0c9c1c"

# After that you can run the script with the optional arguments like so:
# $ ./standup.sh "insert pubkey" "insert node type (see options below)" "insert ssh key" "insert ssh allowed IP's" "insert password for standup user"

####
# 1. Set Initial Variables from command line arguments
####

# The arguments are read as per the below variables:
# ./standup.sh "PUBKEY" "BTCTYPE" "SSH_KEY" "SYS_SSH_IP" "USERPASSWORD"

# If you want to omit an argument then input empty qoutes in its place for example:
# ./standup "" "Mainnet" "" "" "aPasswordForTheUser"

# If you do not want to add any arguments and run everything as per the defaults simply run:
# ./standup.sh

# For Tor V3 client authentication (optional), you can run standup.sh like:
# ./standup.sh "descriptor:x25519:NWJNEFU487H2BI3JFNKJENFKJWI3"
# and it will automatically add the pubkey to the authorized_clients directory, which
# means the user is Tor authenticated before the node is even installed.
PUBKEY=$1

# Can be one of the following: "Mainnet", "Pruned Mainnet", "Testnet", "Pruned Testnet", or "Private Regtest", default is "Pruned Testnet"
BTCTYPE=$2

# Optional key for automated SSH logins to standup non-privileged account - if you do not want to add one add "" as an argument
SSH_KEY=$3

# Optional comma separated list of IPs that can use SSH - if you do not want to add any add "" as an argument
SYS_SSH_IP=$4

# Optional password for the standup non-privileged account - if you do not want to add one add "" as an argument
USERPASSWORD=$5

# Force check for root, if you are not logged in as root then the script will not execute
if ! [ "$(id -u)" = 0 ]
then

  echo "$0 - You need to be logged in as root!"
  exit 1

fi

# Output stdout and stderr to ~root files
exec > >(tee -a /root/standup.log) 2> >(tee -a /root/standup.log /root/standup.err >&2)

####
# 2. Bring Debian Up To Date
####

echo "$0 - Starting Debian updates; this will take a while!"

# Make sure all packages are up-to-date
apt-get update
apt-get upgrade -y
apt-get dist-upgrade -y

# Install haveged (a random number generator)
apt-get install haveged -y

# Install GPG
apt-get install gnupg -y

# Install dirmngr
apt-get install dirmng -y

# Set system to automatically update
echo "unattended-upgrades unattended-upgrades/enable_auto_updates boolean true" | debconf-set-selections
apt-get install unattended-upgrades -y

echo "$0 - Updated Debian Packages"

# get uncomplicated firewall and deny all incoming connections except SSH
sudo apt-get install ufw 
ufw allow ssh
ufw enable

####
# 3. Set Up User
####

# Create "standup" user with optional password and give them sudo capability
/usr/sbin/useradd -m -p `perl -e 'printf("%s\n",crypt($ARGV[0],"password"))' "$USERPASSWORD"` -g sudo -s /bin/bash standup
/usr/sbin/adduser standup sudo

echo "$0 - Setup standup with sudo access."

# Setup SSH Key if the user added one as an argument
if [ -n "$SSH_KEY" ]
then

   mkdir ~standup/.ssh
   echo "$SSH_KEY" >> ~standup/.ssh/authorized_keys
   chown -R standup ~standup/.ssh

   echo "$0 - Added .ssh key to standup."

fi

# Setup SSH allowed IP's if the user added any as an argument
if [ -n "$SYS_SSH_IP" ]
then

  echo "sshd: $SYS_SSH_IP" >> /etc/hosts.allow
  echo "sshd: ALL" >> /etc/hosts.deny
  echo "$0 - Limited SSH access."

else

  echo "$0 - WARNING: Your SSH access is not limited; this is a major security hole!"

fi

####
# 4. Install latest stable tor
####

# Download tor

#  To use source lines with https:// in /etc/apt/sources.list the apt-transport-https package is required. Install it with:
sudo apt install apt-transport-https

# We need to set up our package repository before you can fetch Tor. First, you need to figure out the name of your distribution:
DEBIAN_VERSION=$(lsb_release -c | awk '{ print $2 }')

# You need to add the following entries to /etc/apt/sources.list:
cat >> /etc/apt/sources.list << EOF
deb https://deb.torproject.org/torproject.org $DEBIAN_VERSION main
deb-src https://deb.torproject.org/torproject.org $DEBIAN_VERSION main
EOF

# Then add the gpg key used to sign the packages by running:
sudo apt-key adv --recv-keys --keyserver keys.gnupg.net  74A941BA219EC810
sudo wget -qO- https://deb.torproject.org/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc | gpg --import
sudo gpg --export A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89 | apt-key add -

# Update system, install and run tor as a service
sudo apt update
sudo apt install tor deb.torproject.org-keyring

# Setup hidden service
sed -i -e 's/#ControlPort 9051/ControlPort 9051/g' /etc/tor/torrc
sed -i -e 's/#CookieAuthentication 1/CookieAuthentication 1/g' /etc/tor/torrc
sed -i -e 's/## address y:z./## address y:z.\
\
HiddenServiceDir \/var\/lib\/tor\/standup\/\
HiddenServiceVersion 3\
HiddenServicePort 1309 127.0.0.1:18332\
HiddenServicePort 1309 127.0.0.1:18443\
HiddenServicePort 1309 127.0.0.1:8332/g' /etc/tor/torrc
mkdir /var/lib/tor/standup
chown -R debian-tor:debian-tor /var/lib/tor/standup
chmod 700 /var/lib/tor/standup

# Add standup to the tor group so that the tor authentication cookie can be read by bitcoind
sudo usermod -a -G debian-tor standup

# Restart tor to create the HiddenServiceDir
sudo systemctl restart tor.service


# add V3 authorized_clients public key if one exists
if ! [ "$PUBKEY" == "" ]
then

  # create the directory manually incase tor.service did not restart quickly enough
  mkdir /var/lib/tor/standup/authorized_clients

  # need to assign the owner
  chown -R debian-tor:debian-tor /var/lib/tor/standup/authorized_clients

  # Create the file for the pubkey
  sudo touch /var/lib/tor/standup/authorized_clients/fullynoded.auth

  # Write the pubkey to the file
  sudo echo "$PUBKEY" > /var/lib/tor/standup/authorized_clients/fullynoded.auth

  # Restart tor for authentication to take effect
  sudo systemctl restart tor.service

  echo "$0 - Successfully added Tor V3 authentication"

else

  echo "$0 - No Tor V3 authentication, anyone who gets access to your QR code can have full access to your node, ensure you do not store more then you are willing to lose and better yet use the node as a watch-only wallet"

fi

####
# 5. Install Bitcoin
####

# Download Bitcoin
echo "$0 - Downloading Bitcoin; this will also take a while!"

# CURRENT BITCOIN RELEASE:
# Change as necessary
export BITCOIN="bitcoin-core-0.20.1"
export BITCOINPLAIN=`echo $BITCOIN | sed 's/bitcoin-core/bitcoin/'`

sudo -u standup wget https://bitcoincore.org/bin/$BITCOIN/$BITCOINPLAIN-x86_64-linux-gnu.tar.gz -O ~standup/$BITCOINPLAIN-x86_64-linux-gnu.tar.gz
sudo -u standup wget https://bitcoincore.org/bin/$BITCOIN/SHA256SUMS.asc -O ~standup/SHA256SUMS.asc
sudo -u standup wget https://bitcoin.org/laanwj-releases.asc -O ~standup/laanwj-releases.asc

# Verifying Bitcoin: Signature
echo "$0 - Verifying Bitcoin."

sudo -u standup /usr/bin/gpg --no-tty --import ~standup/laanwj-releases.asc
export SHASIG=`sudo -u standup /usr/bin/gpg --no-tty --verify ~standup/SHA256SUMS.asc 2>&1 | grep "Good signature"`
echo "SHASIG is $SHASIG"

if [[ "$SHASIG" ]]
then

    echo "$0 - VERIFICATION SUCCESS / SIG: $SHASIG"

else

    (>&2 echo "$0 - VERIFICATION ERROR: Signature for Bitcoin did not verify!")

fi

# Verify Bitcoin: SHA
export TARSHA256=`/usr/bin/sha256sum ~standup/$BITCOINPLAIN-x86_64-linux-gnu.tar.gz | awk '{print $1}'`
export EXPECTEDSHA256=`cat ~standup/SHA256SUMS.asc | grep $BITCOINPLAIN-x86_64-linux-gnu.tar.gz | awk '{print $1}'`

if [ "$TARSHA256" == "$EXPECTEDSHA256" ]
then

   echo "$0 - VERIFICATION SUCCESS / SHA: $TARSHA256"

else

    (>&2 echo "$0 - VERIFICATION ERROR: SHA for Bitcoin did not match!")

fi

# Install Bitcoin
echo "$0 - Installinging Bitcoin."

sudo -u standup /bin/tar xzf ~standup/$BITCOINPLAIN-x86_64-linux-gnu.tar.gz -C ~standup
/usr/bin/install -m 0755 -o root -g root -t /usr/local/bin ~standup/$BITCOINPLAIN/bin/*
/bin/rm -rf ~standup/$BITCOINPLAIN/

# Start Up Bitcoin
echo "$0 - Configuring Bitcoin."

sudo -u standup /bin/mkdir ~standup/.bitcoin

# The only variation between Mainnet and Testnet is that Testnet has the "testnet=1" variable
# The only variation between Regular and Pruned is that Pruned has the "prune=550" variable, which is the smallest possible prune
RPCPASSWORD=$(xxd -l 16 -p /dev/urandom)

cat >> ~standup/.bitcoin/bitcoin.conf << EOF
# [core]
# Only download and relay blocks - ignore unconfirmed transaction
blocksonly=1
blockfilterindex=1
dbcache=50
maxsigcachesize=4 
maxconnections=4 
rpcthreads=1
banscore=1

server=1
rpcuser=StandUp
rpcpassword=$RPCPASSWORD
rpcallowip=127.0.0.1
debug=tor

# [network]
# Maintain at most N connections to peers.
maxconnections=20
# Tries to keep outbound traffic under the given target (in MiB per 24h), 0 = no limit.
maxuploadtarget=500
EOF



if [ "$BTCTYPE" == "Mainnet" ]; then

cat >> ~standup/.bitcoin/bitcoin.conf << EOF
txindex=1
EOF

elif [ "$BTCTYPE" == "Pruned Mainnet" ]; then

cat >> ~standup/.bitcoin/bitcoin.conf << EOF
prune=550

EOF

elif [ "$BTCTYPE" == "Testnet" ]; then

cat >> ~standup/.bitcoin/bitcoin.conf << EOF
txindex=1
testnet=1
EOF

elif [ "$BTCTYPE" == "Pruned Testnet" ]; then

cat >> ~standup/.bitcoin/bitcoin.conf << EOF
prune=550
testnet=1
EOF


elif [ "$BTCTYPE" == "Private Regtest" ]; then

cat >> ~standup/.bitcoin/bitcoin.conf << EOF
regtest=1
txindex=1
EOF

else

  (>&2 echo "$0 - ERROR: Somehow you managed to select no Bitcoin Installation Type, so Bitcoin hasn't been properly setup. Whoops!")
  exit 1

fi

cat >> ~standup/.bitcoin/bitcoin.conf << EOF
[test]
rpcbind=127.0.0.1
rpcport=18332
[main]
rpcbind=127.0.0.1
rpcport=8332
[regtest]
rpcbind=127.0.0.1
rpcport=18443
EOF

/bin/chown standup ~standup/.bitcoin/bitcoin.conf
/bin/chmod 600 ~standup/.bitcoin/bitcoin.conf

# Setup bitcoind as a service that requires Tor
echo "$0 - Setting up Bitcoin as a systemd service."

sudo cat > /etc/systemd/system/bitcoind.service << EOF
# It is not recommended to modify this file in-place, because it will
# be overwritten during package upgrades. If you want to add further
# options or overwrite existing ones then use;
# $ systemctl edit bitcoind.service
# See "man systemd.service" for details.
# Note that almost all daemon options could be specified in
# /etc/bitcoin/bitcoin.conf, except for those explicitly specified as arguments
# in ExecStart=
[Unit]
Description=Bitcoin daemon
After=tor.service
Requires=tor.service
[Service]
ExecStart=/usr/local/bin/bitcoind -conf=/home/standup/.bitcoin/bitcoin.conf
# Process management
####################
Type=simple
PIDFile=/run/bitcoind/bitcoind.pid
Restart=on-failure
# Directory creation and permissions
####################################
# Run as bitcoin:bitcoin
User=standup
Group=sudo
# /run/bitcoind
RuntimeDirectory=bitcoind
RuntimeDirectoryMode=0710

# Hardening measures
####################
# Provide a private /tmp and /var/tmp.
PrivateTmp=true
# Mount /usr, /boot/ and /etc read-only for the process.
ProtectSystem=full
# Disallow the process and all of its children to gain
# new privileges through execve().
NoNewPrivileges=true
# Use a new /dev namespace only populated with API pseudo devices
# such as /dev/null, /dev/zero and /dev/random.
PrivateDevices=true
# Deny the creation of writeable and executeable memory mappings.
MemoryDenyWriteExecute=true
[Install]
WantedBy=multi-user.target
EOF

echo "$0 - Starting bitcoind service"


####
# 6. Install QR encoder and displayer, and show the btcstandup:// uri in plain text in case the QR Code does not display
####

# Get the Tor onion address for the QR code
HS_HOSTNAME=$(sudo cat /var/lib/tor/standup/hostname)

# Create the QR string
QR="btcstandup://StandUp:$RPCPASSWORD@$HS_HOSTNAME:1309/?label=StandUp.sh"

# Display the uri text in case QR code does not work
echo "$0 - **************************************************************************************************************"
echo "$0 - This is your btcstandup:// uri to convert into a QR which can be scanned with FullyNoded to connect remotely:"
echo $QR
echo "$0 - **************************************************************************************************************"
echo "$0 - Bitcoin and Tor is setup as a service and will automatically start if your VPS reboots"
echo "$0 - You can manually stop/start Bitcoin with: sudo systemctl stop/start bitcoind.service"
echo "$0 - Remember to cleanup all side-effects"
echo "$0 - To see a running log of the status"
echo "$0 - $ tail -f -n 100 /home/standup/.bitcoin/testnet3/debug.log"


# standup script - install c-lightning
export MESSAGE_PREFIX="message prefix"
echo "
----------------
  $MESSAGE_PREFIX installing c-lightning
----------------
"

export CLN_VERSION="v0.9.2"
export LIGHTNING_DIR="/home/standup/.lightning"
export FULL_BTC_DATA_DIR="/home/standup/.bitcoin"

echo "

$MESSAGE_PREFIX installing c-lightning dependencies

"

apt-get install -y \
autoconf automake build-essential git libtool libgmp-dev \
libsqlite3-dev python3 python3-mako net-tools zlib1g-dev \
libsodium-dev gettext valgrind python3-pip libpq-dev

echo "
$MESSAGE_PREFIX downloading & Installing c-lightning
"
# get & compile clightning from github
sudo -u standup git clone https://github.com/ElementsProject/lightning.git ~standup/lightning
cd ~standup/lightning
git checkout $CLN_VERSION
python3 -m pip install -r requirements.txt
./configure
make -j$(nproc --ignore=1) --quiet
sudo make install

# get back to script directory
cd "$SCRIPTS_DIR"

# lightningd config
mkdir -m 760 "$LIGHTNING_DIR"
chown standup -R "$LIGHTNING_DIR"
cat >> "$LIGHTNING_DIR"/config << EOF
alias=StandUp

log-level=debug:plugin
log-prefix=standup

bitcoin-datadir=$FULL_BTC_DATA_DIR
# bitcoin-rpcuser=****
# bitcoin-rpcpassword=****
# bitcoin-rpcconnect=127.0.0.1
# bitcoin-rpcport=8332

# outgoing Tor connection
proxy=127.0.0.1:9050
# listen on all interfaces
bind-addr=
# listen only clearnet
bind-addr=127.0.0.1:9735
addr=statictor:127.0.0.1:9051
# only use Tor for outgoing communication
always-use-proxy=true
EOF

/bin/chmod 640 "$LIGHTNING_DIR"/config

# create log file
touch "$LIGHTNING_DIR"/lightning.log

# add tor configuration to torrc
sed -i -e 's/HiddenServicePort 1309 127.0.0.1:8332/HiddenServicePort 1309 127.0.0.1:8332\
\
HiddenServiceDir \/var\/lib\/tor\/standup\/lightningd-service_v3\/\
HiddenServiceVersion 3\
HiddenServicePort 1234 127.0.0.1:9735/g' /etc/tor/torrc

#################
# add http-plugin
#################
if "$CLN_HTTP_PLUGIN"; then
  echo "
  $MESSAGE_PREFIX installing Rust lang.
  "
  cd ~standup
  /usr/sbin/runuser -l standup -c 'curl https://sh.rustup.rs -sSf | sh -s -- -y'
  source ~standup/.cargo/env
  echo "
  $MESSAGE_PREFIX $(runsuer -l standup rustc - version) installed.
  "
  # get back to script directory & create plugins direcotry
  cd "$SCRIPTS_DIR"
  mkdir "$LIGHTNING_DIR"/plugins/

  # get http-plugin & build
  echo "
  $MESSAGE_PREFIX getting c-lightning http-plugin.
  "
  sudo -u standup git clone https://github.com/Start9Labs/c-lightning-http-plugin.git "$LIGHTNING_DIR"/plugings/
  cd "$LIGHTNING_DIR"/plugings/c-lightning-http-plugin/
  cargo build --release
  chmod a+x /home/you/.lightning/plugins/c-lightning-http-plugin/target/release/c-lightning-http-plugin
  if [[ -z "$HTTP_PASS" ]]; then
    while [[ -z "$HTTP_PASS" ]]; do
      read -rp "Provide a strong password for https-plugin" HTTP_PASS
    done
  fi

  # add config options
  echo "
plugin=/home/standup/.lightning/plugins/c-lightning-http-plugin/target/release/c-lightning-http-plugin
http-pass=$HTTP_PASS
https-port=1312
" >> "$LIGHTNING_DIR"/config

  # create HS for plugin
  sed -i -e 's/HiddenServicePort 1234 127.0.0.1:9735/HiddenServicePort 1234 127.0.0.1:9735\
HiddenServiceDir \/var\/lib\/tor\/standup\/lightningd-http-plugin_v3\/\
HiddenServiceVersion 3\
HiddenServicePort 1312 127.0.0.1:1312/g' /etc/tor/torrc
fi

echo "
$MESSAGE_PREFIX Setting up c-lightning as a systemd service.
"

cat > /etc/systemd/system/lightningd.service << EOF
# It is not recommended to modify this file in-place, because it will
# be overwritten during package upgrades. If you want to add further
# options or overwrite existing ones then use
# $ systemctl edit bitcoind.service
# See "man systemd.service" for details.
# Note that almost all daemon options could be specified in
# /etc/lightning/config, except for those explicitly specified as arguments
# in ExecStart=
[Unit]
Description=c-lightning daemon
After=tor.service
Requires=tor.service
[Service]
ExecStart=/usr/local/bin/lightningd -conf=/home/standup/.lightning/config
# Process management
####################
Type=simple
PIDFile=/run/lightning/lightningd.pid
Restart=on-failure
# Directory creation and permissions
####################################
# Run as lightningd:lightningd
User=standup
Group=standup
# /run/lightningd
RuntimeDirectory=lightningd
RuntimeDirectoryMode=0710
# Hardening measures
####################
# Provide a private /tmp and /var/tmp.
PrivateTmp=true
# Mount /usr, /boot/ and /etc read-only for the process.
ProtectSystem=full
# Disallow the process and all of its children to gain
# new privileges through execve().
NoNewPrivileges=true
# Use a new /dev namespace only populated with API pseudo devices
# such as /dev/null, /dev/zero and /dev/random.
PrivateDevices=true
# Deny the creation of writable and executable memory mappings.
MemoryDenyWriteExecute=true
[Install]
WantedBy=multi-user.target
EOF

# enable lightnind service
sudo systemctl restart tor
sleep 15
sudo systemctl enable bitcoind.service
sudo systemctl start bitcoind.service
sleep 15
sudo systemctl enable lightningd.service
sudo systemctl start lightningd.service

if [ $(systemctl status lightningd | grep active | awk '{print $2}') = "active" ]; then
  echo "
$MESSAGE_PREFIX c-lightning Installed and started
  Wait for the bitcoind to fully sync with the blockchain and then interact with lightningd.
  "
else
  echo "
$MESSAGE_PREFIX c-lightning not yet active.
  "
fi
