#!/bin/bash

# set -u

normal=$(tput sgr0)
red=$(tput setaf 1)
yellow=$(tput setaf 2)

error(){
	echo "	${red} ERROR: " $1 ${normal}
}

warn() {
	echo "	${yellow} WARN: " $1 ${normal}
}

info() {
	echo "	INFO: " $1
}

is_su() {
	if [[ $EUID -ne 0 ]]; then
		return 1
	fi
}

require_su() {
	if [ ! is_su ]; then
		error "This script must be run with su privileges! Try $ sudo bash."
	fi	
}

update_sys() {
	if [ $UPDATE_SYS ]; then
		yum update -y -q
	fi
}

script_dir() {
	"$( cd "$( dirname "$0" )" && pwd )" 	# The current script directory.
}

chown_file() {
	if [ -e $1 ]; then
		info "Setting permissions on $1 for user $2..."
		chown $2:$2 $1
		chmod 640 $1
		chmod 750 $1
	fi
}

make_file() {
	if [ ! -e $1 ]; then
		info "Making file $1..."
		touch $1
		if [ id -u $2 ]; then
			chown_file $1 $2
		fi
	fi
}

make_backup() {
	if [ -e $1 ]; then
		local tmp=$(mktemp -t $1.bak.XXXX)
		info "Backing up $1 to $tmp..."
		cp $1 $tmp
	fi
}

make_dir() {
	info "Making directory $1..."
	mkdir -p $1
}

make_dir_cd() {
	make_dir $1
	cd $1
}

make_link() {
	if [ ! -L /usr/bin/$1 ]; then
		info "Making slink for $1..."
		ln -s /usr/local/bin/$1 /usr/bin/$1
	fi
}

install_n() {
	which n
	if [ $? -ne 0 ]; then
		make_dir_cd /usr/share/src

		rm -rf n-master master.zip

		info "Downloading n..."
		wget https://github.com/visionmedia/n/archive/master.zip
		unzip master.zip && cd n-master
		make install && make_link n && info "installed n at: $(which n)." \
			|| error "n was not installed!"
	else
		info "n already installed at: $(which n)."
	fi
}

install_node() {
	info "Checking if Node.js is installed..."
	n $NODE_VERSION
	make_link "node"
	which node && info "node is installed at: $(which node)." \
		|| error "node was not installed!"
}

install_npm() {
	make_link "npm"
	which npm && info "npm is installed at: $(which npm)." \
		|| error "npm was not installed!"
	
}

install_nodejs() {
	install_n && install_node && install_npm
	export NODE=$(node --version)
	info "The installed version of node is: $NODE."
}

make_user() {
	id -u $1
	if [ $? -eq 0 ]; then
		return
	fi
	info "Creating user $1..."
	useradd -m $1
	if [ $? -ne 0 ]; then
		error "Could not create user $1!"
	fi
	info "User $1 created."

	cat /etc/passwd | grep $CLOUD_USER
	if [ $? -eq 0 ]; then
		info "Adding $CLOUD_USER user to $APP group to enable accessing logs..."
		usermod -a -G $APP $CLOUD_USER
	fi
}

make_app_dirs() {
	make_dir $LOG_DIR
	make_dir $DATA_DIR
	make_dir $RUN_DIR

	info "Setting directory permissions..."
	chown $USER:$USER $APP_DIR
	chown $USER:$USER $RUN_DIR
	chown $USER:$USER $DATA_DIR
	chown $USER:$USER $LOG_DIR
	chmod 750 $APP_DIR
	chmod 750 $RUN_DIR
	chmod 750 $DATA_DIR
	chmod 750 $LOG_DIR
}

app_status() {
	warn "Checking $APP status..."
	initctl status $APP
}

app_stop() {
	local cmd=$(initctl status $APP | grep "start/running")
	if [ cmd ]; then
		info "Stopping $APP..."
		initctl stop $APP
		sleep 5	
	fi
}

app_start() {
	local cmd=$(initctl status $APP | grep "stop/waiting")
	if [ cmd ]; then
		info "Starting $APP. Please wait..."
		initctl start $APP
		sleep 5
	fi
}

app_verify() {
	info "Testing $APP health..."
	curl http://127.0.0.1:$PORT/health
}

app_install() {
	local PWD=$(pwd)
	info "Copying files from $PWD directory to $RUN_DIR..."
	cp -a . $RUN_DIR
	
	cd $RUN_DIR

	if [ -L $CURRENT_DIR ]; then
		app_stop
		info "Moving symlink $CURRENT_DIR to $RUN_DIR..."
		ln -sfn $RUN_DIR $CURRENT_DIR
#		local tmp=$(mktemp -d -t current.XXXX)
#		ln -s $RUN_DIR $tmp && mv -Tf $tmp $CURRENT_DIR
	else
		info "Create symlink $CURRENT_DIR to $RUN_DIR..."
		ln -s $RUN_DIR $CURRENT_DIR
	fi
}

make_upstart_conf() {
  if [ ! -e $UPSTART ]; then
    info "Creating upstart job for $APP..."

cat <<- EOF > $UPSTART

start on (local-filesystems and net-device-up IFACE=eth0)
stop on shutdown

respawn

chdir $CURRENT_DIR

exec /usr/bin/node $START_FILE
EOF
    info "Upstart file is: $UPSTART."
  	initctl reload-configuration	
  fi
}

install_node_app() {
	APP=$1
	VERSION=$2

	PACKAGE=$APP-$VERSION.zip
	CLOUD_USER=${CLOUD_USER:-ubuntu}
	USER=$APP
	HOME=/home/$USER
	APP_DIR=$HOME/app
	RUN_DIR=$APP_DIR/$APP-$VERSION
	CURRENT_DIR=$APP_DIR/current
	START_FILE=$CURRENT_DIR/index.js
	LOG_DIR=$HOME/log
	LOG_FILE=$LOG_DIR/$APP.log
	DATA_DIR=$HOME/data
	UPSTART=/etc/init/$APP.conf
	NODE_VERSION=stable

	require_su
	echo "Deploying $APP..."
	install_nodejs
	make_user $USER
	make_app_dirs
	make_file $LOG_FILE $USER
	make_upstart_conf
	app_install
	app_start
	app_verify
	echo "...done!"
	echo "Bye!"		
}
