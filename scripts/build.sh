#!/usr/bin/env bash

TOOL=vault-plugin-auth-kerberos
#
# This script builds the application from source for multiple platforms.
set -e

# Get the parent directory of where this script is.
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ] ; do SOURCE="$(readlink "$SOURCE")"; done
DIR="$( cd -P "$( dirname "$SOURCE" )/.." && pwd )"

# Change into that directory
cd "$DIR"

# Set build tags
BUILD_TAGS="${BUILD_TAGS}:-${TOOL}"

# Get the git commit
GIT_COMMIT="$(git rev-parse HEAD)"
GIT_DIRTY="$(test -n "`git status --porcelain`" && echo "+CHANGES" || true)"

# Determine the arch/os combos we're building for
XC_ARCH=${XC_ARCH:-"386 amd64"}
XC_OS=${XC_OS:-linux darwin windows freebsd openbsd netbsd solaris}
XC_OSARCH=${XC_OSARCH:-"linux/amd64 linux/arm64 darwin/amd64 windows/amd64 freebsd/amd64 openbsd/amd64 netbsd/amd64 solaris/amd64"}

GOPATH=${GOPATH:-$(go env GOPATH)}
case $(uname) in
    CYGWIN*)
        GOPATH="$(cygpath $GOPATH)"
        ;;
esac

# Delete the old dir
echo "==> Removing old directory..."
rm -f bin/*
rm -rf pkg/*
mkdir -p bin/

# If its dev mode, only build for our self
if [ "${VAULT_DEV_BUILD}x" != "x" ]; then
    XC_OS=$(go env GOOS)
    XC_ARCH=$(go env GOARCH)
    XC_OSARCH=$(go env GOOS)/$(go env GOARCH)
fi

# If its devenv we only build for linux/amd64 - as this ends up in the containers
if [ "${VAULT_DEVENV_BUILD}x" != "x" ]; then
  XC_OS="linux"
  XC_ARCH="amd64"
  XC_OSARCH="linux/amd64"
  # We set this to 1 now so that we don't zip and copy to the dist folder later
  VAULT_DEV_BUILD=1
fi

# Build!
echo "==> Building..."
gox \
    -osarch="${XC_OSARCH}" \
    -ldflags "-X github.com/hashicorp/${TOOL}/version.GitCommit='${GIT_COMMIT}${GIT_DIRTY}'" \
    -output "pkg/{{.OS}}_{{.Arch}}/${TOOL}" \
    -tags="${BUILD_TAGS}" \
    ./cmd/$TOOL

# Move all the compiled things to the $GOPATH/bin
OLDIFS=$IFS
IFS=: MAIN_GOPATH=($GOPATH)
IFS=$OLDIFS

# Copy our OS/Arch to the bin/ directory
# Unless we're in DEVENV mode
if [ "${VAULT_DEVENV_BUILD}x" = "x" ]; then
  DEV_PLATFORM="./pkg/$(go env GOOS)_$(go env GOARCH)"
  for F in $(find ${DEV_PLATFORM} -mindepth 1 -maxdepth 1 -type f); do
      cp ${F} bin/
      cp ${F} ${MAIN_GOPATH}/bin/
  done
fi

if [ "${VAULT_DEV_BUILD}x" = "x" ]; then
    # Zip and copy to the dist dir
    echo "==> Packaging..."
    for PLATFORM in $(find ./pkg -mindepth 1 -maxdepth 1 -type d); do
        OSARCH=$(basename ${PLATFORM})
        echo "--> ${OSARCH}"

        pushd $PLATFORM >/dev/null 2>&1
        zip ../${OSARCH}.zip ./*
        popd >/dev/null 2>&1
    done
fi

# Done!
echo
echo "==> Results:"
ls -hl bin/
