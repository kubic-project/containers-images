#!/bin/bash

## pre_checkin.sh script is expected to be called from
## a local copy of the build service image after running
## the _services file, e.g. `osc service disabledrun`

log()       { echo ">>> $@" ; }
abort()     { log "FATAL: $@" ; exit 1 ; }
endScript() { log "EXITING: $@" ; exit 0 ; }
usage()     {
    cat <<USAGE
usage:
    ./pre_checkin.sh [kubic|caasp]
    ./pre_checkin.sh kubic|caasp [OPTIONS]

options:
    --mkchanges     Create/update the changes file (mostly used for automation)

If no parameter is given defaults to 'kubic'
USAGE
}

namespace=${1:-kubic}
mkchanges=$2

[ -n "${mkchanges}" ] && [ "${mkchanges}" != "--mkchanges" ] && usage \
    && abort "Bad option"

make_changes_file() {
    local previous_commit
    local changes_log
    local git_log_format="- Commit %h by %an %ae %n%n%w(77,2,2)%B"

    if [ -f "${changes_file}" ]; then
        previous_commit="$(sed "4q;d" "${changes_file}" | cut -d' ' -f3).."
    fi
    # Update the changes file
    pushd container-images 1> /dev/null
        changes_log=$(git log --pretty=format:"${git_log_format}" \
            ${previous_commit} -- pre_checkin.sh \
            "${image}" | sed "1 s/- \(.*$\)/\1/")
    popd 1> /dev/null
    [ -z "${changes_log}" ] && endScript "Missing new changelog entries"
    osc vc ${changes_file} -m "${changes_log}"
}

if [ "${namespace}" == "kubic" ]; then
    product='kubic'
    baseimage="opensuse/tumbleweed#latest"
    distro="openSUSE Kubic"
elif [[ "${namespace}" =~ ^caasp/.* ]]; then
    product='caasp'
    baseimage="suse/sle15#latest"
    distro="SLES15"
else
    usage
    abort "Unknown product. Product needs to match 'kubic|caasp/.*'"
fi

set -e

for file in *kiwi.ini; do
    image="${file%%.kiwi.ini}"
    changes_file="${product}-${image}.changes"
    kiwi_file="${product}-${image}.kiwi"
    extra_packages=""
    extra_packages_file="${product}-extra-packages"

    # Create a list of extra packages
    if [ -f "${extra_packages_file}" ]; then
        while read -r package; do
            extra_packages+="    <package name=\"${package}\"\/>\n"
        done < "${extra_packages_file}"
    fi

    # update the changes file, mostly used for automation in Concourse CI
    [ -n "${mkchanges}" ] && make_changes_file

    # create *.kiwi file from *kiwi.ini template
    cp "${file}" "${kiwi_file}"
    sed -i -e "s@_BASEIMAGE_@${baseimage}@g" \
        -e "s@_DISTRO_@${distro}@g" \
        -e "s@_NAMESPACE_@${namespace}@g" \
        -e "s@_PRODUCT_@${product}@g" \
        -e "/^<image/i\<!--\n\tThis is an autogenerated \
file from ${file} template.\n\tDo not manually modify \
this file.\n-->\n" \
        -e "s@_EXTRA_PACKAGES_@${extra_packages}@g" "${kiwi_file}"
    # Remove blank lines
    sed -i "/^ *$/d" "${kiwi_file}"
    log "${kiwi_file} has been created"
done
