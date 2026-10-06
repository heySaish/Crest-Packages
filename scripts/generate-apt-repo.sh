#!/usr/bin/env bash
set -euo pipefail

# Scripts directory and repository root
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CDIR="${REPO_ROOT}/dists/stable/main/binary-arm64"
DIST_DIR="${REPO_ROOT}/dists/stable"

echo "==> Generating APT repository metadata in ${REPO_ROOT}..."

mkdir -p "${CDIR}"

PACKAGES_FILE="${CDIR}/Packages"
PACKAGES_GZ="${CDIR}/Packages.gz"
RELEASE_FILE="${DIST_DIR}/Release"
RELEASE_GPG="${DIST_DIR}/Release.gpg"
INRELEASE_FILE="${DIST_DIR}/InRelease"

rm -f "${PACKAGES_FILE}" "${PACKAGES_GZ}" "${RELEASE_FILE}" "${RELEASE_GPG}" "${INRELEASE_FILE}"

# Function to calculate portable file size
get_file_size() {
    wc -c < "$1" | tr -d ' '
}

# Function to calculate MD5 hash
get_md5() {
    md5sum "$1" | awk '{print $1}'
}

# Function to calculate SHA256 hash
get_sha256() {
    sha256sum "$1" | awk '{print $1}'
}

# Scan pool directory for .deb packages
DEB_FILES=$(find "${REPO_ROOT}/pool" -type f -name "*.deb" | sort)

if [ -z "${DEB_FILES}" ]; then
    echo "Warning: No .deb files found in ${REPO_ROOT}/pool"
    touch "${PACKAGES_FILE}"
else
    for deb in ${DEB_FILES}; do
        rel_path="${deb#${REPO_ROOT}/}"
        size=$(get_file_size "${deb}")
        md5=$(get_md5 "${deb}")
        sha256=$(get_sha256 "${deb}")

        # Write control fields + APT index metadata
        dpkg-deb -f "${deb}" >> "${PACKAGES_FILE}"
        echo "Filename: ${rel_path}" >> "${PACKAGES_FILE}"
        echo "Size: ${size}" >> "${PACKAGES_FILE}"
        echo "MD5sum: ${md5}" >> "${PACKAGES_FILE}"
        echo "SHA256: ${sha256}" >> "${PACKAGES_FILE}"
        echo "" >> "${PACKAGES_FILE}"
    done
fi

# Compress Packages file
gzip -9 -c "${PACKAGES_FILE}" > "${PACKAGES_GZ}"

# Generate Release file
DATE_STR=$(date -u -R 2>/dev/null || date -u)

pkg_rel_path="main/binary-arm64/Packages"
pkg_gz_rel_path="main/binary-arm64/Packages.gz"

pkg_size=$(get_file_size "${PACKAGES_FILE}")
pkg_md5=$(get_md5 "${PACKAGES_FILE}")
pkg_sha256=$(get_sha256 "${PACKAGES_FILE}")

pkg_gz_size=$(get_file_size "${PACKAGES_GZ}")
pkg_gz_md5=$(get_md5 "${PACKAGES_GZ}")
pkg_gz_sha256=$(get_sha256 "${PACKAGES_GZ}")

cat << EOF > "${RELEASE_FILE}"
Origin: Crest Debian
Label: Crest Debian
Suite: stable
Codename: stable
Components: main
Architectures: arm64
Date: ${DATE_STR}
MD5Sum:
 ${pkg_md5} ${pkg_size} ${pkg_rel_path}
 ${pkg_gz_md5} ${pkg_gz_size} ${pkg_gz_rel_path}
SHA256:
 ${pkg_sha256} ${pkg_size} ${pkg_rel_path}
 ${pkg_gz_sha256} ${pkg_gz_size} ${pkg_gz_rel_path}
EOF

echo "==> Successfully generated APT metadata:"
echo "    - ${PACKAGES_FILE}"
echo "    - ${PACKAGES_GZ}"
echo "    - ${RELEASE_FILE}"

# Cryptographic Signing (Release.gpg & InRelease)
REQUIRE_GPG_SIGNING="${REQUIRE_GPG_SIGNING:-0}"

if command -v gpg >/dev/null 2>&1 && ( gpg --list-secret-keys 2>/dev/null | grep -q "sec" || [ -n "${GPG_KEY_ID:-}" ] ); then
    echo "==> Signing APT repository Release file..."
    
    SIGN_ARGS=("--batch" "--yes")
    if [ -n "${GPG_KEY_ID:-}" ]; then
        SIGN_ARGS+=("--default-key" "${GPG_KEY_ID}")
    fi

    # Generate detached signature (Release.gpg)
    gpg "${SIGN_ARGS[@]}" --detach-sign --armor --output "${RELEASE_GPG}" "${RELEASE_FILE}"
    
    # Generate clearsigned signature (InRelease)
    gpg "${SIGN_ARGS[@]}" --clearsign --output "${INRELEASE_FILE}" "${RELEASE_FILE}"
    
    echo "==> Successfully signed Release file:"
    echo "    - ${RELEASE_GPG}"
    echo "    - ${INRELEASE_FILE}"
elif [ "${REQUIRE_GPG_SIGNING}" = "1" ]; then
    echo "ERROR: REQUIRE_GPG_SIGNING is set to 1, but no GPG secret key was found in keyring!" >&2
    exit 1
else
    echo "Notice: No GPG secret key detected. Skipping repository signing (Release.gpg / InRelease)."
fi
