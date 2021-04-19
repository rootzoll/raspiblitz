#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "Interim optional Bitcoin Core updates between RaspiBlitz releases."
 echo "bitcoin.update.sh [info|tested|reckless]"
 echo "info -> get actual state and possible actions"
 echo "tested -> only do recommended updates by the RaspiBlitz team"
 echo " binary will be checked by signature and checksum"
 echo "reckless -> the update was not tested by the RaspiBlitz team"
 echo " binary will be checked by signature and checksum"
 exit 1
fi

source /home/admin/raspiblitz.info

# 1. parameter [info|tested|reckless]
mode="$1"

# RECOMMENDED UPDATE BY RASPIBLITZ TEAM
# comment will be shown as "BEWARE Info" when option is choosen (can be multiple lines) 
bitcoinVersion="0.21.0"

# needed to check code signing
laanwjPGP="01EA5486DE18A882D4C2684590C8019E36C2E964"

# GATHER DATA

# setting download directory
downloadDir="/home/admin/download"

# detect CPU architecture & fitting download link
if [ $(uname -m | grep -c 'arm') -eq 1 ] ; then
  bitcoinOSversion="arm-linux-gnueabihf"
fi
if [ $(uname -m | grep -c 'aarch64') -eq 1 ] ; then
  bitcoinOSversion="aarch64-linux-gnu"
fi
if [ $(uname -m | grep -c 'x86_64') -eq 1 ] ; then
  bitcoinOSversion="x86_64-linux-gnu"
fi

# installed version
installedVersion=$(sudo -u bitcoin bitcoind --version | head -n1| cut -d" " -f4|cut -c 2-)

# test if the installed version already the tested/recommended update version
updateInstalled=$(echo "${installedVersion}" | grep -c "${bitcoinVersion}")

# get latest release from GitHub releases
gitHubLatestReleaseJSON="$(curl -s https://api.github.com/repos/bitcoin/bitcoin/releases | jq '.[0]')"
latestVersion=$(echo "${gitHubLatestReleaseJSON}"|jq -r '.tag_name'|cut -c 2-)

# INFO
function displayInfo() {
  echo "# basic data"
  echo "installedVersion='${installedVersion}'"
  echo "bitcoinOSversion='${bitcoinOSversion}'"

  echo "# the tested/recommended update option"
  echo "updateInstalled='${updateInstalled}'"
  echo "bitcoinVersion='${bitcoinVersion}'"

  echo "# reckless update option (latest Bitcoin Core release from GitHub)"
  echo "latestVersion='${latestVersion}'"
}

if [ "${mode}" = "info" ]; then
  displayInfo
  exit 1
fi

# tested
if [ "${mode}" = "tested" ]; then

  echo "# bitcoin.update.sh tested"

  # check for optional second parameter: forced update version
  # --> only does the tested update if its the given version
  # this is needed for recovery/update. 
  fixedBitcoinVersion="$2"
  if [ ${#fixedBitcoinVersion} -gt 0 ]; then
    echo "# checking for fixed version update: askedFor(${bitcoinVersion}) available(${bitcoinVersion})"
    if [ "${fixedBitcoinVersion}" != "${bitcoinVersion}" ]; then
      echo "# warn='required update version does not match'"
      echo "# this is normal when the recovery script of a new RaspiBlitz version checks for an old update - just ignore"
      exit 1
    else
      echo "# OK - update version is matching"
    fi
  fi

elif [ "${mode}" = "reckless" ]; then
  # RECKLESS
  # this mode is just for people running test and development nodes - its not recommended
  # for production nodes. In a update/recovery scenario it will not install a fixed version
  # it will always pick the latest release from the github
  echo "# bitcoin.update.sh reckless"
  bitcoinVersion=${latestVersion}
fi

# JOINED INSTALL (tested & RECKLESS)
if [ "${mode}" = "tested" ] || [ "${mode}" = "reckless" ]; then
  
  displayInfo

  if [ $installedVersion = $bitcoinVersion ];then
    echo "# installedVersion = bitcoinVersion"
    echo "# exiting script"
    exit 0
  fi

  echo 
  echo "# clean & change into download directory"
  sudo rm -r ${downloadDir}/*
  cd "${downloadDir}" || exit 1

  echo
  # download, check and import signer key
  sudo -u admin wget https://bitcoin.org/laanwj-releases.asc
  if [ ! -f "./laanwj-releases.asc" ]
  then
    echo "# !!! FAIL !!! Download laanwj-releases.asc not success."
    exit 1
  fi
  gpg ./laanwj-releases.asc
  fingerprint=$(gpg ./laanwj-releases.asc 2>/dev/null | grep "${laanwjPGP}" -c)
  if [ ${fingerprint} -lt 1 ]; then
    echo
    echo "# !!! BUILD WARNING --> Bitcoin PGP author not as expected"
    echo "# Should contain laanwjPGP: ${laanwjPGP}"
    echo "# PRESS ENTER to TAKE THE RISK if you think all is OK"
    read key
  fi
  gpg --import ./laanwj-releases.asc

  # download signed binary sha256 hash sum file and check
  sudo -u admin wget https://bitcoin.org/bin/bitcoin-core-${bitcoinVersion}/SHA256SUMS.asc
  verifyResult=$(gpg --verify SHA256SUMS.asc 2>&1)
  goodSignature=$(echo ${verifyResult} | grep 'Good signature' -c)
  echo "goodSignature(${goodSignature})"
  correctKey=$(echo ${verifyResult} |  grep "using RSA key ${laanwjPGP: -16}" -c)
  echo "correctKey(${correctKey})"
  if [ ${correctKey} -lt 1 ] || [ ${goodSignature} -lt 1 ]; then
    echo
    echo "# !!! BUILD FAILED --> PGP Verify not OK / signature(${goodSignature}) verify(${correctKey})"
    exit 1
  else
    echo
    echo "# OK --> BITCOIN MANIFEST IS CORRECT"
    echo
  fi

  # get the sha256 value for the corresponding platform from signed hash sum file
  bitcoinSHA256=$(grep -i "$bitcoinOSversion" SHA256SUMS.asc | cut -d " " -f1)

  echo
  echo "# BITCOIN v${bitcoinVersion} for ${bitcoinOSversion}"

  # download resources
  binaryName="bitcoin-${bitcoinVersion}-${bitcoinOSversion}.tar.gz"
  sudo -u admin wget https://bitcoin.org/bin/bitcoin-core-${bitcoinVersion}/${binaryName}
  if [ ! -f "./${binaryName}" ]
  then
      echo "# !!! FAIL !!! Downloading BITCOIN BINARY did not succeed."
      exit 1
  fi

  # check binary checksum test
  binaryChecksum=$(sha256sum ${binaryName} | cut -d " " -f1)
  if [ "${binaryChecksum}" != "${bitcoinSHA256}" ]; then
    echo "!!! FAIL !!! Downloaded BITCOIN BINARY not matching SHA256 checksum: ${bitcoinSHA256}"
    exit 1
  else
    echo
    echo "# OK --> VERIFIED BITCOIN CHECKSUM CORRECT"
    echo
  fi

fi 

if [ "${mode}" = "tested" ]; then
  # note: install will be done the same as reckless further down
  bitcoinInterimsUpdateNew="${bitcoinVersion}"
elif [ "${mode}" = "reckless" ]; then
  bitcoinInterimsUpdateNew="reckless"
fi

# JOINED INSTALL (tested & RECKLESS)
if [ "${mode}" = "tested" ] || [ "${mode}" = "reckless" ]; then

  # install
  echo "# Stopping bitcoind and lnd"
  sudo systemctl stop lnd
  sudo systemctl stop bitcoind
  echo
  echo "# Installing Bitcoin Core v${bitcoinVersion}"
  sudo -u admin tar -xvf ${binaryName}
  sudo install -m 0755 -o root -g root -t /usr/local/bin/ bitcoin-${bitcoinVersion}/bin/*
  sleep 3
  installed=$(sudo -u admin bitcoind --version | grep "${bitcoinVersion}" -c)
  if [ ${installed} -lt 1 ]; then
    echo
    echo "# !!! BUILD FAILED --> Was not able to install bitcoind version(${bitcoinVersion})"
    exit 1
  fi
  echo "# flag update in raspiblitz config"
  source /mnt/hdd/raspiblitz.conf
  if [ ${#bitcoinInterimsUpdate} -eq 0 ]; then
    echo "bitcoinInterimsUpdate='${bitcoinInterimsUpdateNew}'" >> /mnt/hdd/raspiblitz.conf
  else
    sudo sed -i "s/^bitcoinInterimsUpdate=.*/bitcoinInterimsUpdate='${bitcoinInterimsUpdateNew}'/g" /mnt/hdd/raspiblitz.conf
  fi

  if [ "${state}" == "ready" ]; then
    sudo systemctl start bitcoind
    sudo systemctl start lnd
  fi

  echo "# OK Bitcoin Core Installed"
  echo "# NOTE: RaspiBlitz may need to reboot now"
  exit 1

else

  echo "# error='parameter not known'"
  exit 1

fi
