#!/bin/bash

# Debug true/false
debug="false"

# Get distro and determine witch element to use as package name
distro=$(lsb_release -a 2> /dev/null | awk '/Distributor/ {print $3}')

case ${distro} in
  Ubuntu|Debian )
    pkgmgr="dpkg"
    ;;
  RedHat|CentOS|Scientific )
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
  echo "We are running on ${distro} with major release ${distro_majrelease}"
  echo "  Using ${pkgmgr} to verify checksums."
  echo
fi

# Array of binaries to check.
checks=(
  '/bin/bash'
  '/usr/sbin/sshd'
  '/bin/login'
  '/bin/su'
  '/usr/bin/sudo'
  '/usr/sbin/httpd'
)

checksum () {
  # Takes 1 argument;
  #  1) path from pseudo_binary_name array element
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
    echo
  fi

  if [ ${binary_checksum} == ${package_checksum} ]; then
    return 0
  else
    return 1
  fi
}

do_checks () {
  failed=0
  verified=0

  for element in ${checks[@]}; do
    eval "prog=(\${$element[@]})"

    checksum ${prog[0]}

    if [ $? -ne 0 ]; then
      failed_binarys[${failed}]=${prog[0]}
      failed_packages[${failed}]=${package_name}
      failed=$((failed+1))

    else
      verified_binaries[${verified}]=${prog[0]}
      verified_packages[${verified}]=${package_name}
      verified=$((verified+1))
    fi
  done
}

output () {
  if [ ${failed} -ne 0 ]; then
    echo "CRITICAL: Verification of binary vs. package checksum failed!"
    for i in ${failed_binarys[@]}; do
        echo " ${failed_binarys[${count}]} doen not match ${failed_packages[${count}]}"
    done
    nagios_error=2
    return 2
  else
    echo "OK: Package and binary checksum are identical"
    nagios_error=0
    return 0
  fi
}

debug_output () {
  if [ ${debug} == "true" ]; then
    echo
    echo "Affcted binaries/packages:"
    count_failed=0
    for i in ${failed_binarys[@]}; do
      echo " ${failed_binarys[${count}]} doen not match ${failed_packages[${count}]}"
    done
    echo

    echo "Verified binarys/packages:"
    count_verified=0
    for i in ${verified_binaries[@]}; do
      echo -e "  OK: ${verified_binaries[${count}]} matches ${verified_packages[${count}]}"
      let count=count+1
    done
  fi
}

do_checks
output
debug_output

exit ${nagios_error}
