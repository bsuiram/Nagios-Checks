#!/bin/bash

# Get distro and determine witch element to use as package name
distro=$(lsb_release -a 2> /dev/null | awk '/Distributor/ {print $3}')

case ${distro} in
  Ubuntu|Debian )
    index=1
    pkgmgr="check_dpkg"
    ;;
  RedHat|CentOS|Scientific )
    index=2
    pkgmgr="check_rpm"
    ;;
  * )
    echo "Unknown Distro: Please fix me.. im broken.."
    exit 1
    ;;
esac

# I'll make a debug option
#echo "We are running on ${distro}:"
#echo "  Using index [${index}] to resolve path to binary"
#echo "  and ${pkgmgr} as package manager."

#  Array of pseudo binary names to check
checks=( BASH SSHD LOGIN SU SUDO )

# Packages:
# pseudo_binary_name=( '/full/path/to/binary' 'deb-package-name' 'rpm-package-name' 'binary_name' )
BASH=( '/bin/bash' 'bash' 'bash' 'bash' )
SSHD=( '/usr/sbin/sshd' 'openssh-server' 'openssh-server' 'sshd' )
LOGIN=( '/bin/login' 'login' 'util-linux-ng' 'login' )
SU=( '/bin/su' 'login' 'coreutils' 'su' )
SUDO=( '/usr/bin/sudo' 'sudo' 'sudo' 'sudo' )

check_dpkg () {
  # Takes 2 arguments;
  #  1) path from pseudo_binary_name array element #1
  #  2) package name from pseudo_binary_name array determined by distribution ${index}
  #  3) binary name from pseudo_binary_name array element #3 (not used, remove)
  binary_path=${1:1:${#1}} #Remove first char from path (/) as ${package_name}.md5sums contains path without starting /.
  package_name=${2}
  #binary_name=${3} # Not used remove

  package_md5sum=$(cat /var/lib/dpkg/info/${package_name}.md5sums | egrep "${binary_path}$" | awk '{print $1}')
  binary_md5sum=$(md5sum /${binary_path} | awk '{print $1}')

  if [ ${binary_md5sum} == ${package_md5sum} ]; then
    return 0
  else
    return 1
  fi
}

check_rpm () {
  # Takes 2 arguments;
  #  1) path from pseudo_binary_name array element #1
  #  2) package name from pseudo_binary_name array determined by distribution, ${index}
  #  3) binary name from pseudo_binary_name array element #3 (not used)
  binary_path=${1}
  package_name=${2}
  #binary_name=${3} # Not used remove

  package_sha256sum=$(rpm -ql --dump ${package_name} | grep "${binary_path} " | awk '{print $4}')
  binary_sha256sum=$(sha256sum ${binary_path} | awk '{print $1}')

  if [ ${binary_sha256sum} == ${package_sha256sum} ]; then
    return 0
  else
    return 1
  fi
}

# Check sums of binarys against package.
do_checks () {

  failed=0
  not_failed=0

  for element in ${checks[@]}; do
    eval "prog=(\${$element[@]})"

    ${pkgmgr} ${prog[0]} ${prog[${index}]} ${prog[3]}
    if [ $? -ne 0 ]; then
      failed_binarys[${failed}]=${prog[0]}
      failed=$((failed+1))
      echo "ERROR: Package and binary checksum differs for ${prog[0]} in package \"${prog[${index}]}\"!"
    else
      not_failed_binarys[${not_failed}]=${prog[0]}
      not_failed=$((not_failed+1))
    fi
  done

  if [ ${failed} -ne 0 ]; then
    echo "CRITICAL: Verification of binary/package checksum failed for ${failed_binarys[@]}!"
    exit 2
  else
    echo "OK: Package and binary checksum are identical for ${not_failed_binarys[@]}."
    exit 0
  fi
}

do_checks
