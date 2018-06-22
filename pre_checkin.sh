#!/bin/bash

## pre_checkin.sh script is expected to be called from
## a local copy of the build service image after running
## the _services file, e.g. `osc service disabledrun`

git_log_format="- Commit %h by %an %ae %n%n%w(77,2,2)%B"

set -e

for file in *kiwi.ini; do
    for product in kubic caasp; do
        image="${file%%.kiwi.ini}"
        changes_file="${product}-${image}.changes"
        kiwi_file="${product}-${image}.kiwi"
        last_changes_date=$(sed "2q;d" "${changes_file}" | cut -d- -f1)
        changes_log=""

        # Update the changes file
        pushd container-images 1> /dev/null
            changes_log=$(git log --after="${last_changes_date}" \
                --pretty=format:"${git_log_format}" -- pre_checkin.sh \
                "${image}" | sed "1 s/- \(.*$\)/\1/")
        popd 1> /dev/null
        [ ! -z "${changes_log}" ] || exit 1
        osc vc ${changes_file} -m "${changes_log}"

        # create *.kiwi file from *kiwi.ini template
        cp "${file}" "${kiwi_file}"
        if [ "${product}" == "kubic" ]; then
            baseimage="opensuse/tumbleweed#current"
            distro="openSUSE Kubic"
        else
            baseimage="suse/sle15#current"
            distro="SLES15"
        fi
        sed -i -e "s@_BASEIMAGE_@${baseimage}@g" \
            -e "s/_DISTRO_/${distro}/g" \
            -e "s/_PRODUCT_/${product}/g" \
            -e "/^<image/i\<!--\n\tThis is an autogenerated \
file from ${file} template.\n\tDo not manually modify \
this file.\n-->\n" "${kiwi_file}"
    done
done
