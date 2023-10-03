#!/bin/bash
# Copyright Epic Games, Inc. All Rights Reserved.
BASH_LOCATION=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
NODE_VERSION=v18.17.0

pushd "${BASH_LOCATION}" > /dev/null

source common_utils.sh

use_args $@
# Azure specific fix to allow installing NodeJS from NodeSource
if test -f "/etc/apt/sources.list.d/azure-cli.list"; then
	sudo touch /etc/apt/sources.list.d/nodesource.list
	sudo touch /usr/share/keyrings/nodesource.gpg
	sudo chmod 644 /etc/apt/sources.list.d/nodesource.list
	sudo chmod 644 /usr/share/keyrings/nodesource.gpg
	sudo chmod 644 /etc/apt/sources.list.d/azure-cli.list
fi

function check_version() { #current_version #min_version
	#check if same string
	if [ -z "$2" ] || [ "$1" = "$2" ]; then
		return 0
	fi

	local i current minimum

	IFS="." read -r -a current <<< $1
	IFS="." read -r -a minimum <<< $2

	# fill empty fields in current with zeros
	for ((i=${#current[@]}; i<${#minimum[@]}; i++))
	do
		current[i]=0
	done

	for ((i=0; i<${#current[@]}; i++))
	do
		if [[ -z ${minimum[i]} ]]; then
			# fill empty fields in minimum with zeros
			minimum[i]=0
	fi

		if ((10#${current[i]} > 10#${minimum[i]})); then
			return 1
	fi

		if ((10#${current[i]} < 10#${minimum[i]})); then
			return 2
	fi
	done

	# if got this far string is the same once we added missing 0
	return 0
}

function check_and_install() { #dep_name #get_version_string #version_min #install_command
	local is_installed=0

	log_msg "Checking for required $1 install"

	local current=$(echo $2 | sed -E 's/[^0-9.]//g')
	local minimum=$(echo $3 | sed -E 's/[^0-9.]//g')

	if [ $# -ne 4 ]; then
		log_msg "check_and_install expects 4 args (dep_name get_version_string version_min install_command) got $#"
		return -1
	fi

	if [ ! -z $current ]; then
		log_msg "Current version: $current checking >= $minimum"
		check_version "$current" "$minimum"
		if [ "$?" -lt 2 ]; then
			log_msg "$1 is installed."
			return 0
		else
			log_msg "Required install of $1 not found installing"
		fi
	fi

	if [ $is_installed -ne 1 ]; then
		echo "$1 installation not found installing..."

		start_process $4

		if [ $? -ge 1 ]; then
			echo "Installation of $1 failed try running `export VERBOSE=1` then run this script again for more details"
		fi
	fi
}

function setup_frontend() {
	# navigate to root
	pushd ${BASH_LOCATION}/../../.. > /dev/null
	export PATH="../../SignallingWebServer/platform_scripts/bash/node/bin:$PATH"
	# If player.html doesn't exist, or --build passed as arg, rebuild the frontend
	if [ ! -f SignallingWebServer/Public/player.html ] || [ ! -z "$FORCE_BUILD" ] ; then
		echo "Building Typescript Frontend."
		# Using our bundled NodeJS, build the web frontend files
		pushd ${BASH_LOCATION}/../../../Frontend/library > /dev/null
		../../SignallingWebServer/platform_scripts/bash/node/bin/npm install
		../../SignallingWebServer/platform_scripts/bash/node/bin/npm run build-dev
		popd
		pushd ${BASH_LOCATION}/../../../Frontend/ui-library > /dev/null
		../../SignallingWebServer/platform_scripts/bash/node/bin/npm install
		../../SignallingWebServer/platform_scripts/bash/node/bin/npm link ../library
		../../SignallingWebServer/platform_scripts/bash/node/bin/npm run build-dev
		popd

		pushd ${BASH_LOCATION}/../../../Frontend/implementations/typescript > /dev/null
		../../../SignallingWebServer/platform_scripts/bash/node/bin/npm install
		../../../SignallingWebServer/platform_scripts/bash/node/bin/npm link ../../library ../../ui-library
		../../../SignallingWebServer/platform_scripts/bash/node/bin/npm run build-dev
		popd
	else
		echo 'Skipping building Frontend because files already exist. Please run with "--build" to force a rebuild'
	fi

	popd > /dev/null # root
}


echo "Checking Pixel Streaming Server dependencies."

# navigate to SignallingWebServer root
pushd ${BASH_LOCATION}/../.. > /dev/null

node_version=""
if [[ -f "${BASH_LOCATION}/node/bin/node" ]]; then
	node_version=$("${BASH_LOCATION}/node/bin/node" --version)
fi

node_url=""
if [ "$(uname)" == "Darwin" ]; then
	arch=$(uname -m)
	if [[ $arch == x86_64* ]]; then
		node_url="https://nodejs.org/dist/$NODE_VERSION/node-$NODE_VERSION-darwin-x64.tar.gz"
	elif  [[ $arch == arm* ]]; then
	    node_url="https://nodejs.org/dist/$NODE_VERSION/node-$NODE_VERSION-darwin-arm64.tar.gz"
	else
		echo 'Incompatible architecture. Only x86_64 and ARM64 are supported'
		exit -1
	fi
elif [ "$(expr substr $(uname -s) 1 5)" == "Linux" ]; then
	node_url="https://nodejs.org/dist/$NODE_VERSION/node-$NODE_VERSION-linux-x64.tar.gz"
else
	echo 'Incorrect OS for use with setup.sh'
	exit -1
fi
check_and_install "node" "$node_version" "$NODE_VERSION" "curl $node_url --output node.tar.xz
													&& tar -xf node.tar.xz
													&& rm node.tar.xz
													&& mv node-v*-*-* \"${BASH_LOCATION}/node\""

PATH="${BASH_LOCATION}/node/bin:$PATH"
"${BASH_LOCATION}/node/lib/node_modules/npm/bin/npm-cli.js" install

popd > /dev/null # SignallingWebServer

# Trigger Frontend Build if needed or requested
# This has to be done after check_and_install "node"
setup_frontend

popd > /dev/null # BASH_SOURCE

if [ "$(uname)" == "Darwin" ]; then
	if [ -d "${BASH_LOCATION}/coturn" ]; then
		echo 'CoTURN directory found...skipping install.'
	else
		echo 'CoTURN directory not found...beginning CoTURN download for Mac.'	
		coturn_url=""
		if [[ $arch == x86_64* ]]; then
			coturn_url="https://github.com/Belchy06/coturn/releases/download/v4.6.2-mac-x84_64/turnserver.zip"
		elif  [[ $arch == arm* ]]; then
	    	coturn_url="https://github.com/Belchy06/coturn/releases/download/v4.6.2-mac-arm64/turnserver.zip"
		fi
		curl -L -o ./turnserver.zip "$coturn_url"
		mkdir "${BASH_LOCATION}/coturn" 
		tar -xf turnserver.zip -C "${BASH_LOCATION}/coturn"
		rm turnserver.zip
	fi
elif [ "$(expr substr $(uname -s) 1 5)" == "Linux" ]; then
    #command #dep_name #get_version_string #version_min #install command
	coturn_version=$(if command -v turnserver &> /dev/null; then echo 1; else echo 0; fi)
	if [ $coturn_version -eq 0 ]; then
		if ! command -v apt-get &> /dev/null; then
			echo "Setup for the scripts is designed for use with distros that use the apt-get package manager" \
				 "if you are seeing this message you will have to update \"${BASH_LOCATION}/setup.sh\" with\n" \
				 "a package manger and the equivalent packages for your distribution. Please follow the\n" \
				 "instructions found at https://pkgs.org/search/?q=coturn to install Coturn for your specific distribution"
			exit 1
		else
			if [ `id -u` -eq 0 ]; then
				check_and_install "coturn" "$coturn_version" "1" "apt-get install -y coturn"
			else
				check_and_install "coturn" "$coturn_version" "1" "sudo apt-get install -y coturn"
			fi
		fi
	fi
fi

