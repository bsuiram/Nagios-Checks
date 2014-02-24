#!/bin/bash

# Get distro and determine witch INDEX to use as package name
distro=$(lsb_release -a 2> /dev/null | awk '/Distributor/ {print $3}')

case ${distro} in
  Ubuntu|Debian )
    index=1
    pkgmgr="dpkg"
    ;;
  RedHat|CentOS|Scientific )
    index=2
    pkgmgr="rpm"
    ;;
  * )
    echo "Unknown Distro: Please fix me.. im broken.."
    exit 1
    ;;
esac

echo "We are running on ${distro}:"
echo "  Using index [${index}] to resolve path to binary"
echo "  and ${pkgmgr} as package manager."

#  Array of psudo binary names to check
checks=( BASH SSHD LOGIN SU SUDO )

# Packages:
# psudo_binary_name=( '/full/path/to/binary' 'deb-package-name' 'rpm-package-name' 'binary_name' )
declare -a BASH=( '/bin/bash' 'bash' 'bash' 'bash' )
declare -a SSHD=( '/usr/sbin/sshd' 'openssh-server' 'openssh-server' 'sshd' )
declare -a LOGIN=( '/bin/login' 'login' 'util-linux' 'login' )
declare -a SU=( '/bin/su' 'login' 'coreutils' 'su' )
declare -a SUDO=( '/usr/bin/sudo' 'sudo' 'sudo' 'sudo' )

dpkg_pkg () {
  # Takes two arguments;
  #  1) binary name from psudo_binary_name array element #3
  #  2) binary path from psudo_binary_name array element #0
  binary_path=${1:1:${#1}} #Remove first char from path.
  package_name=${2}
  binary_name=${3}

  echo "package_name   = ${package_name}"
  echo "binary_path   = ${binary_path} (first char removed on purose)"

  package_md5sum=$(cat /var/lib/dpkg/info/${package_name}.md5sums | egrep "${binary_path}$" | awk '{print $1}')
  echo "package_md5sum = ${package_md5sum}"

  binary_md5sum=$(md5sum /${binary_path} | awk '{print $1}')
  echo "binary_md5sum = ${binary_md5sum}"

  if [ ${binary_md5sum} == ${package_md5sum} ]; then
    echo "Sucess!"
  else
    echo "WTF!?"
  fi
  echo
}

# Check packages
check_pkg () {
  for element in ${checks[@]}; do
    eval "prog=(\${$element[@]})"
    echo "Checking ${prog[0]}"
    #dpkg_pkg binary_path package_name binary_name
    dpkg_pkg ${prog[0]} ${prog[${index}]} ${prog[3]}
  done
}

check_pkg

