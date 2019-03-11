#!/bin/bash

PROG="$(basename "${0}")"
SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
BASE_IMAGE=""
HOSTNAME=""
SSH_PUB_KEY_FILE=""
META_DATA_FILE="${SCRIPT_DIR}/data/meta-data"
USER_DATA_FILE="${SCRIPT_DIR}/data/user-data"
NETWORK_INTERFACES_FILE=""
POST_CONFIG_INTERFACES_FILE=""
AUTO_START="true"
VBOXMANAGE=`which VBoxManage`
GENISOIMAGE=`which genisoimage`
SED=`which sed`
UUIDGEN=`which uuidgen`
POSTCONFIGURE=${SCRIPT_DIR}/post-configure.sh

usage() {
  echo -e "USAGE: ${PROG} [--base-image <BASE_IMAGE>] [--hostname <HOSTNAME>]
        [--ssh-pub-keyfile <SSH_PUB_KEY_FILE>] [--meta-data <META_DATA_FILE>] 
        [--user-data <USER_DATA_FILE>] [--networ-interfaces <NETWORK_INTERFACES_FILE>]
        [--auto-start true|false]\n"
}

help_exit() {
  usage
  echo "This is a utility script for create image using cloud-init.
Options:
  -b, --base-image BASE_IMAGE
              Name of VistualBox base image.
  -o, --hostname HOSTNAME
              Hostname of new image
  -s, --ssh-pub-keyfile SSH_PUB_KEY_FILE
              Path to an SSH public key.
  -m, --meta-data META_DATA_FILE
              Path to an meta data file. Default is '${META_DATA_FILE}'.
  -u, --user-data USER_DATA_FILE
              Path to an user data file. Default is '${USER_DATA_FILE}'.
  -n, --network-interfaces NETWORK_INTERFACES_FILE
              Path to an network interface data file.
  -p, --post-config-interfaces POST_CONFIG_INTERFACES_FILE
              Path to an post config interface data file.
  -a, --auto-start true|false
              Auto start vm. Default is true.
  -h, --help  Output this help message.
"
  exit 0
}

assign() {
  key="${1}"
  value="${key#*=}"
  if [[ "${value}" != "${key}" ]]; then
    # key was of the form 'key=value'
    echo "${value}"
    return 0
  elif [[ "x${2}" != "x" ]]; then
    echo "${2}"
    return 2
  else
    output "Required parameter for '-${key}' not specified.\n"
    usage
    exit 1
  fi
  keypos=$keylen
}

while [[ $# -ge 1 ]]; do
  key="${1}"

  case $key in
    -*)
    keylen=${#key}
    keypos=1
    while [[ $keypos -lt $keylen ]]; do
      case ${key:${keypos}} in
        b|-base-image)
        BASE_IMAGE=$(assign "${key:${keypos}}" "${2}")
        if [[ $? -eq 2 ]]; then shift; fi
        keypos=$keylen
        ;;
        o|-hostname)
        HOSTNAME=$(assign "${key:${keypos}}" "${2}")
        HOSTNAME=`echo ${HOSTNAME} | tr '[:upper:]' '[:lower:]'`
        if [[ $? -eq 2 ]]; then shift; fi
        keypos=$keylen
        ;;
        s|-ssh-pub-keyfile)
        SSH_PUB_KEY_FILE=$(assign "${key:${keypos}}" "${2}")
        SSH_PUB_KEY_FILE_CONTENT=`cat ${SSH_PUB_KEY_FILE}`
        if [[ $? -eq 2 ]]; then shift; fi
        keypos=$keylen
        ;;
        m|-meta-data)
        META_DATA_FILE=$(assign "${key:${keypos}}" "${2}")
        if [[ $? -eq 2 ]]; then shift; fi
        keypos=$keylen
        ;;
        u|-user-data)
        USER_DATA_FILE=$(assign "${key:${keypos}}" "${2}")
        if [[ $? -eq 2 ]]; then shift; fi
        keypos=$keylen
        ;;
        n|-network-interfaces)
        NETWORK_INTERFACES_FILE=$(assign "${key:${keypos}}" "${2}")
        if [[ $? -eq 2 ]]; then shift; fi
        keypos=$keylen
        ;;
        p|-post-config-interfaces)
        POST_CONFIG_INTERFACES_FILE=$(assign "${key:${keypos}}" "${2}")
        if [[ $? -eq 2 ]]; then shift; fi
        keypos=$keylen
        ;;           
        a|-auto-start)
        AUTO_START=$(assign "${key:${keypos}}" "${2}")
        if [[ $? -eq 2 ]]; then shift; fi
        keypos=$keylen
        ;;
        h*|-help)
        help_exit
        ;;
        *)
        output "Unknown option '${key:${keypos}}'.\n"
        usage
        exit 1
        ;;
      esac
      ((keypos++))
    done
    ;;
  esac
  shift
done

if [[ -z ${BASE_IMAGE} ]]; then
  echo "Base image not found"
  exit 1
fi

if [[ -z ${HOSTNAME} ]]; then
  echo "Hostname not set"
  exit 1
fi

if [[ -z ${SSH_PUB_KEY_FILE} || ! -f ${SSH_PUB_KEY_FILE} ]]; then
  echo "SSH public key File not found!"
  exit 1
fi

if [[ -z ${META_DATA_FILE} || ! -f ${META_DATA_FILE} ]]; then
  echo "Meta data File not found!"
  exit 1
fi

if [[ -z ${USER_DATA_FILE} || ! -f ${USER_DATA_FILE} ]]; then
  echo "User data File not found!"
  exit 1
fi

mkdir -p ${SCRIPT_DIR}/vms/${HOSTNAME}

UUID=`${UUIDGEN}`

FILES="${SCRIPT_DIR}/vms/${HOSTNAME}/user-data ${SCRIPT_DIR}/vms/${HOSTNAME}/meta-data"

${SED} -e "s|#HOSTNAME#|${HOSTNAME}|g" -e "s|#UUID#|${UUID}|g" ${META_DATA_FILE} > ${SCRIPT_DIR}/vms/${HOSTNAME}/meta-data
${SED} -e "s|#SSH-PUB-KEY#|${SSH_PUB_KEY_FILE_CONTENT}|g" ${USER_DATA_FILE} > ${SCRIPT_DIR}/vms/${HOSTNAME}/user-data

if [[ -f ${NETWORK_INTERFACES_FILE} ]]; then
  ${SED} -e "s|#HOSTNAME#|${HOSTNAME}|g" -e "s|#UUID#|${UUID}|g" ${NETWORK_INTERFACES_FILE} > ${SCRIPT_DIR}/vms/${HOSTNAME}/network-config
  FILES="${SCRIPT_DIR}/vms/${HOSTNAME}/user-data ${SCRIPT_DIR}/vms/${HOSTNAME}/meta-data ${SCRIPT_DIR}/vms/${HOSTNAME}/network-config"
fi

${GENISOIMAGE} -input-charset utf-8 \
  -output ${SCRIPT_DIR}/vms/${HOSTNAME}/${HOSTNAME}-cidata.iso \
  -volid cidata -joliet -rock ${FILES}

${VBOXMANAGE} clonevm ${BASE_IMAGE} --mode all --name ${HOSTNAME} --register

${VBOXMANAGE} storageattach ${HOSTNAME} --storagectl "IDE" --port 1 --device 0 \
    --type dvddrive --medium ${SCRIPT_DIR}/vms/${HOSTNAME}/${HOSTNAME}-cidata.iso

if [[ -f ${NETWORK_INTERFACES_FILE} ]]; then
  ${POSTCONFIGURE} -v ${HOSTNAME} -p ${POST_CONFIG_INTERFACES_FILE}
fi

if [[ "${AUTO_START}" = "true" ]]; then
  ${VBOXMANAGE} startvm ${HOSTNAME} --type headless
fi