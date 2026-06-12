#!/bin/sh

export MC="-j$(nproc)"

echo
echo "============================================"
echo "Install extensions from   : install.sh"
echo "PHP version               : ${PHP_VERSION}"
echo "Extra Extensions          : ${PHP_EXTENSIONS}"
echo "Multicore Compilation     : ${MC}"
echo "Container package url     : ${CONTAINER_PACKAGE_URL}"
echo "Work directory            : ${PWD}"
echo "============================================"
echo

export EXTENSIONS=",${PHP_EXTENSIONS},"

#
# Helper: install from local .tgz (for version-pinned extensions)
#
installExtensionFromTgz()
{
    tgzName=$1
    result=""
    extensionName="${tgzName%%-*}"
    shift 1
    result=$@
    mkdir -p ${extensionName}
    tar -xf ${tgzName}.tgz -C ${extensionName} --strip-components=1
    ( cd ${extensionName} && phpize && ./configure ${result} && make ${MC} && make install )
    # Find the installed .so and enable it
    extDir=$(php -r "echo ini_get('extension_dir');")
    if [ -f "${extDir}/${extensionName}.so" ]; then
        docker-php-ext-enable ${extensionName}
    else
        echo "WARNING: ${extensionName}.so not found in ${extDir}, skipping enable"
    fi
}

#
# Check if extension is in the list
#
has_extension() {
    case "${EXTENSIONS}" in
        *",$1,"*) return 0 ;;
        *) return 1 ;;
    esac
}

# ============================================================
# Phase 1: Version-pinned extensions via local .tgz
# (phpize needs autoconf+gcc+make; install-php-extensions handles its own deps)
# ============================================================
apk --update add --no-cache autoconf g++ libtool make

if has_extension "redis"; then
    echo "---------- Install redis (pinned: 5.3.7) ----------"
    installExtensionFromTgz redis-5.3.7
fi

if has_extension "mongodb"; then
    echo "---------- Install mongodb (pinned: 1.12.0) ----------"
    apk add --no-cache openssl-dev
    installExtensionFromTgz mongodb-1.12.0
fi

# ============================================================
# Phase 2: All other extensions via install-php-extensions
# ============================================================

# Build a list of extensions to install (exclude already-handled ones)
INSTALL_LIST=""
for ext in $(echo "${PHP_EXTENSIONS}" | tr ',' ' '); do
    case "${ext}" in
        redis|mongodb) ;;  # already installed above
        mysql) ;;           # removed from PHP 7.0+, skip silently
        *) INSTALL_LIST="${INSTALL_LIST} ${ext}" ;;
    esac
done

if [ -n "${INSTALL_LIST}" ]; then
    echo "---------- Install via install-php-extensions:${INSTALL_LIST} ----------"
    # IPE_INSECURE=1: skip SSL verification for Microsoft downloads
    export IPE_INSECURE=1
    install-php-extensions ${INSTALL_LIST}
fi

echo "============================================"
echo "Extension installation complete"
echo "============================================"
