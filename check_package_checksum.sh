#!/bin/bash

# Array of files to check
checks=( \
'/tmp/orphaned' '/bin/bash' '/usr/sbin/sshd' '/bin/login' \
'/bin/su' '/usr/bin/sudo' '/usr/sbin/httpd' '/home/marius/blatti' \
'/nfs-home/home/marius/orphaned' \
)

# Debug true/false
debug="false"
debug_verbose="false"

while getopts "dvh" OPTION; do
  case ${OPTION} in
    d )
      debug="true"
      ;;
    v )
      debug="true"
      debug_verbose="true"
      ;;
    h|?|* )
      usage
      exit 0
      ;;
  esac
done

usage () {
  cat << EOF
  ${0} checks checksums for files against local package database
  Usage: ${0} [-dvh]

    Options:
      -d = debug
      -v = verbose (impies -d)
      -h = Prints this list
EOF
}

check_distro () {
  # Get distro and determine what checksum to use
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
    echo
    echo "function \"${FUNCNAME}\" - debug:"
    echo "  Distro        = ${distro}"
    echo "  Major release = ${distro_majrelease}"
    echo "  Checksum util = \"${pkgmgr}\""
    echo
  fi

  return 0
}

check_file_exists () {
  # Check if file exists, if not, delete it from array.
  index=0
  for file in ${checks[@]}; do
    if [ ! -f ${file} ]; then
      skiped_files[${index}]=${file}
      unset checks[${index}]
    fi
    let index=index+1
  done

  # Debug
  if [ ${debug} == "true" ]; then
    echo "function \"${FUNCNAME}\" - debug:"
    echo "  Files to check:"
    for file in ${checks[@]}; do
      echo "    ${file}"
    done
    echo
    echo "  Missing files:"
    for missing in ${skiped_files[@]}; do
      echo "    ${missing}"
    done
    echo
  fi

  return 0
}

get_package_name () {
  # Check if file is handled by package manager
  # Returns package name if claimd by package
  # Returns 1 and sets ${package_name} = "orpahned" if not
  file=$1

  case ${pkgmgr} in
    dpkg )
      package_name=$(dpkg -S ${file} | cut -d":" -f1) 2> /dev/null
      if [ ${PIPESTATUS[0]} -ne 0 ]; then
        package_name="orphaned"
      fi
      ;;
    rpm_* )
      package_name=$(rpm -qf ${file}) 2> /dev/null
      if [ $? -ne 0 ]; then
        package_name="orphaned"
      fi
      ;;
    * )
      echo "Oh lordi lord! function \"${FUNCNAME}\" failed hard, there may be not be a god!"
      exit 2
      ;;
  esac

  # Debug
   if [ ${debug} == "true" ]; then
     if [ ${package_name} == "orphaned" ]; then
       echo "function \"${FUNCNAME}\" - debug:"
       echo "  \"${file}\" is orphaned, no package claims to own it."
       echo
     fi
   if [ ${debug_verbose} == "true" ]; then
       echo "function \"${FUNCNAME}\" - debug:"
       echo "  \"${file}\" is claimend by \"${package_name}\""
       echo
     fi
   fi

   if [ ${package_name} == "orphaned" ]; then
     orphaned_files+=( ${file} )
     return 1
   else
     return 0
   fi
}

checksum () {
  # Takes 2 arguments;
  #  1) path from pseudo_file_name array element
  #  2) package_name from get_package_name()
  #  Returns: 0 if checksums are identical, and 1 if they differ.

  local file_path=${1}
  package_name=${2}

  case ${pkgmgr} in
    dpkg )
      # Remove first char from path (/)
      # as ${package_name}.md5sums contains path without starting /
      file_path_mod=${file_path:1:${#file_path}}

      package_checksum=$(cat /var/lib/dpkg/info/${package_name}.md5sums | egrep "${file_path_mod}$" | awk '{print $1}')
      file_checksum=$(md5sum ${file_path} | awk '{print $1}')
      ;;
    rpm_sha256 )
       package_checksum=$(rpm -ql --dump ${package_name} | egrep "^${file_path} " | awk '{print $4}')
       file_checksum=$(sha256sum ${file_path} | awk '{print $1}')
      ;;
    rpm_md5 )
       package_checksum=$(rpm -ql --dump ${package_name} | egrep "^${file_path} " | awk '{print $4}')
       file_checksum=$(md5sum ${file_path} | awk '{print $1}')
      ;;
    * )
      echo "Wat?! function \"${FUNCNAME}\" failed hard, this should NOT happen.."
      exit 2
      ;;
  esac

  if [ ${debug_verbose} == "true" ]; then
    echo "function \"${FUNCNAME}\" - verbose debug:"
    echo "  Package name     = ${package_name}"
    echo "  File path      = ${file_path}"
    echo "  Package checksum = ${package_checksum}"
    echo "  File checksum  = ${file_checksum}"
    echo
  fi

  if [ ${file_checksum} == ${package_checksum} ]; then
    return 0
  else
    return 1
  fi
}

do_checks () {
  # Itterates ${checks} array over checsum() function
  # and populates failed and verified arrays

  local failed=0
  local verified=0

  for file in ${checks[@]}; do
    get_package_name ${file}
    if [ $? -eq 0 ]; then
      checksum ${file} ${package_name}
      if [ $? -ne 0 ]; then
        failed_files[${failed}]=${file}
        failed_packages[${failed}]=${package_name}
        failed=$((failed+1))
      else
        verified_files[${verified}]=${file}
        verified_packages[${verified}]=${package_name}
        verified=$((verified+1))
      fi
    fi
  done

  # Debug
  if [ ${debug_verbose} == "true" ]; then
    echo "function \"${FUNCNAME}\" - verbose debug:"
    echo "  #failed              = ${failed}"
    echo
    echo "  failed_files[@]   ="
    for i in ${failed_files[@]}; do
      echo "    ${i}"
    done
    echo
    echo "  failed_packages[@]   ="
    for i in ${failed_packages[@]}; do
      echo "    ${i}"
    done
    echo
    echo "  #verified            = ${verified}"
    echo
    echo "  verified_files[@] ="
    for i in ${verified_files[@]}; do
      echo "    ${i}"
    done
    echo
    echo "  verified_packages[@] ="
    for i in ${verified_packages[@]}; do
      echo "    ${i}"
    done
    echo
    echo " orhpaned_files[@] ="
    for i in ${orphaned_files[@]}; do
      echo "    ${i}"
    done
    echo
  fi

  return 0
}

output () {

  nagios_error=0

  if [ ${#failed_files[@]} -ne "0" ]; then
    echo "CRITICAL: Verification of file vs. package checksum failed!"
    for i in ${failed_files[@]}; do
        echo " ${failed_files[${count}]} doen not match ${failed_packages[${count}]}"
    done
    nagios_error=2
  elif [ ${#orphaned_files[@]} -ne "0" ]; then
    echo "WARNING: Trying to checksum orphaned files, run \"$(basename $0) --debug\" for more info"
    nagios_error=1
  else
    echo "OK: Package and file checksum are identical"
  fi

  # Debug
  if [ ${debug_verbose} == "true" ] ; then
    echo
    echo "function \"${FUNCNAME}\" - verbose debug:"
    echo "  nagios_error = ${nagios_error}"
    echo
  fi

  return ${nagiso_error}
}

debug_output () {
  local count_failed=0
  local count_verified=0

  if [ ${debug} == "true" ]; then
    echo "function \"${FUNCNAME}\" - debug:"
    echo "  Affcted files/packages:"
    for i in ${failed_files[@]}; do
      echo "    \"${failed_files[${count_failed}]}\" does not match \"${failed_packages[${count_failed}]}\""
      let count_failed=count_failed+1
    done
    echo

    echo "  Verified files/packages:"
    for i in ${verified_files[@]}; do
      echo "    \"${verified_files[${count_verified}]}\" matches \"${verified_packages[${count_verified}]}\""
      let count_verified=count_verified+1
    done
    echo
  fi

  return 0
}

check_distro
check_file_exists
do_checks
debug_output
output
exit ${nagios_error}
