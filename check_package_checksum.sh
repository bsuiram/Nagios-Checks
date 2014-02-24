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

echo "We are running on ${distro}:"
echo "  Using index [${index}] to resolve path to binary"
echo "  and ${pkgmgr} as package manager."

#  Array of psudo binary names to check
checks=( BASH SSHD LOGIN SU SUDO )

# Packages:
# psudo_binary_name=( '/full/path/to/binary' 'deb-package-name' 'rpm-package-name' 'binary_name' )
declare -a BASH=( '/bin/bash' 'bash' 'bash' 'bash' )
declare -a SSHD=( '/usr/sbin/sshd' 'openssh-server' 'openssh-server' 'sshd' )
declare -a LOGIN=( '/bin/login' 'login' 'util-linux-ng' 'login' )
declare -a SU=( '/bin/su' 'login' 'coreutils' 'su' )
declare -a SUDO=( '/usr/bin/sudo' 'sudo' 'sudo' 'sudo' )

check_dpkg () {
  # Takes 3 arguments;
  #  1) path from psudo_binary_name array element #1
  #  2) package name from psudo_binary_name array determined by distribution ${index}
  #  3) binary name from psudo_binary_name array element #3
  binary_path=${1:1:${#1}} #Remove first char from path (/) as ${package_name}.md5sums contains path without starting /.
  package_name=${2}
  binary_name=${3}

  #echo "package_name   = ${package_name}"
  #echo "binary_path   = ${binary_path} (first char removed on purose)"

  package_md5sum=$(cat /var/lib/dpkg/info/${package_name}.md5sums | egrep "${binary_path}$" | awk '{print $1}')
  #echo "package_md5sum = ${package_md5sum}"

  binary_md5sum=$(md5sum /${binary_path} | awk '{print $1}')
  #echo "binary_md5sum = ${binary_md5sum}"

  if [ ${binary_md5sum} == ${package_md5sum} ]; then
    # echo "Ok!"
    return 0
  else
    # echo "Signature verification failed!"
    return 1
  fi
  echo
}

check_rpm () {
  # Takes 3 arguments;
  #  1) path from psudo_binary_name array element #1
  #  2) package name from psudo_binary_name array determined by distribution, ${index}
  #  3) binary name from psudo_binary_name array element #3 (not used)
  binary_path=${1}
  package_name=${2}
  binary_name=${3}

  #echo "package_name   = ${package_name}"
  #echo "binary_path   = ${binary_path}"

  package_sha256sum=$(rpm -ql --dump ${package_name} | grep "${binary_path} " | awk '{print $4}')
  #echo "rpm -ql --dump ${package_name} | grep "${binary_path} " | awk '{print $4}'"
  #echo "package_sha256sum = ${package_sha256sum}"

  binary_sha256sum=$(sha256sum ${binary_path} | awk '{print $1}')
  #echo "binary_sha256sum = $binary_sha256sum"

  if [ ${binary_sha256sum} == ${package_sha256sum} ]; then
    # echo "Ok!"
    return 0
  else
    # echo "Signature verification failed!"
    return 1
  fi
  echo
}

# Check sums of binarys against package
do_checks () {
  failed=0
  not_failed=0
  for element in ${checks[@]}; do
    eval "prog=(\${$element[@]})"
    #echo "Checking ${prog[0]}"
    #${pkgmgr} binary_path package_name binary_name
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
  echo failed
  if [ ${failed} -ne 0 ]; then
    echo "ERROR: Checksum verification of ${failed_binarys[@]} failed!"
    exit 1
  else
    echo "OK: Package and binary checksum are identical for ${not_failed_binarys[@]}."
    exit 0
  fi
}

do_checks
