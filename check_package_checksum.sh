#!/bin/bash

# Debug true/false
debug="true"

# Get distro and determine witch element to use as package name
distro=$(lsb_release -a 2> /dev/null | awk '/Distributor/ {print $3}')

case ${distro} in
  Ubuntu|Debian )
    #index=1
    pkgmgr="dpkg"
    ;;
  RedHat|CentOS|Scientific )
    #index=2
    distro_majrelease=$(lsb_release -a 2> /dev/null | awk '/Release/ {print $2}' | cut -d"." -f1)
    if [ ${distro_majrelease} -le 5 ]; then
      pkgmgr="rpm_md5"
    else
      pkgmgr="rpm_sha256"
    fi
    ;;
  * )
    echo "Unknown Distro: Please fix me.. im broken.."
    exit 1
    ;;
esac

if [ ${debug} == "true" ]; then
  # I'll make a debug option
  echo "We are running on ${distro}:"
  echo "  Using index [${index}] to resolve path to binary"
  echo "  and ${pkgmgr} as package manager."
fi
#  Array of pseudo binary names to check
checks=( pBASH pSSHD pLOGIN pSU pSUDO )

# Packages:
# arrays of pseudo_binary_name=( '/full/path/to/binary' )
# Might be expanded if needed in future.
pBASH=( '/bin/bash' 'bash' 'bash' 'bash' )
pSSHD=( '/usr/sbin/sshd' 'openssh-server' 'openssh-server' 'sshd' )
pLOGIN=( '/bin/login' 'login' 'util-linux-ng' 'login' )
pSU=( '/bin/su' 'login' 'coreutils' 'su' )
pSUDO=( '/usr/bin/sudo' 'sudo' 'sudo' 'sudo' )

checksum () {
  # Takes 1 arguments;
  #  1) path from pseudo_binary_name array element #1
  #  Returns: 0 if checksums are identical, and 1 if they differ.
  binary_path=${1}

  case ${pkgmgr} in
    dpkg )
      # Remove first char from path (/)
      # as ${package_name}.md5sums contains path without starting /
      binary_path_mod=${binary_path:1:${#binary_path}}

      package_name=$(dpkg -S ${binary_path} | cut -d":" -f1)
      package_checksum=$(cat /var/lib/dpkg/info/${package_name}.md5sums | egrep "${binary_path_mod}$" | awk '{print $1}')
      binary_checksum=$(md5sum ${binary_path} | awk '{print $1}')
      ;;
    rpm_sha256 )
       package_name=$(rpm -qf ${binary_path})
       package_checksum=$(rpm -ql --dump ${package_name} | egrep "^${binary_path} " | awk '{print $4}')
       binary_checksum=$(sha256sum ${binary_path} | awk '{print $1}')
      ;;
    rpm_md5 )
       package_name=$(rpm -qf ${binary_path})
       package_checksum=$(rpm -ql --dump ${package_name} | egrep "^${binary_path} " | awk '{print $4}')
       binary_checksum=$(md5sum ${binary_path} | awk '{print $1}')
      ;;
    * )
      echo "wat?!"
      exit 2
      ;;
  esac

  if [ ${debug} == "true" ]; then
    echo "Package name     = ${package_name}"
    echo "Binary path      = ${binary_path}"
    echo "Package checksum = ${package_checksum}"
    echo "Binary checksum  = ${binary_checksum}"
  fi

  if [ ${binary_checksum} == ${package_checksum} ]; then
    return 0
  else
    return 1
  fi
}

do_checks () {

  failed=0
  not_failed=0

  for element in ${checks[@]}; do
    eval "prog=(\${$element[@]})"

    checksum ${prog[0]} #${prog[${index}]}

    if [ $? -ne 0 ]; then
      failed_binarys[${failed}]=${prog[0]}
      failed_packages[${failed}]=${package_name}
      failed=$((failed+1))

    else
      verified_binaries[${not_failed}]=${prog[0]}
      verified_packages[${not_failed}]=${package_name}
      not_failed=$((not_failed+1))
    fi
  done

  if [ ${failed} -ne 0 ]; then
    echo "CRITICAL: Verification of binary vs. package checksum failed!"
    echo "Affcted binaries : ${failed_binarys[@]}"
    echo "Affected packages: ${failed_packages[@]}"
    exit 2
  else
    echo "OK: Package and binary checksum are identical for ${verified_binaries[@]}"
    echo "Checked packages: ${verified_packages[@]}"
    exit 0
  fi
}

do_checks
