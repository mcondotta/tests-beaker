#!/bin/bash
#
# Copyright (c) 2019 Red Hat, Inc. All rights reserved.
#
# This copyrighted material is made available to anyone wishing
# to use, modify, copy, or redistribute it subject to the terms
# and conditions of the GNU General Public License version 2.
#
# This program is distributed in the hope that it will be
# useful, but WITHOUT ANY WARRANTY; without even the implied
# warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
# PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public
# License along with this program; if not, write to the Free
# Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
# Boston, MA 02110-1301, USA.
#
. ../../cki_lib/libcki.sh || exit 1

NAME=$(basename $0)
CDIR=$(dirname $0)
TEST=${TEST:-"$0"}
RELEASE=$(uname -r | sed s/\.`arch`//)
PACKAGE="kernel-${RELEASE}"
TMPDIR=/var/tmp/$(date +"%Y%m%d%H%M%S")
BINDIR=${TMPDIR}-bin
GICVERSION=""
CPUTYPE=""
OSVERSION=""
KVMPARAMFILE=/etc/modprobe.d/kvm-ci.conf

source /usr/share/beakerlib/beakerlib.sh

#
# A simple wrapper function to skip a test because beakerlib doesn't support
# such an important feature, right here we just leverage 'beaker'. Note we
# don't call function report_result() as it directly invoke command
# rstrnt-report-result actually
#
function rlSkip
{
    . ../../cki_lib/libcki.sh || exit 1

    rlLog "Skipping test because $*"
    rstrnt-report-result $TEST SKIP $OUTPUTFILE

    #
    # As we want result="Skip" status="Completed" for all scenarios, right here
    # we always exit 0, otherwise the test will skip/abort
    #
    exit 0
}

function checkPlatformSupport
{
    typeset hwpf=${1?"*** what hardware-platform?, e.g. x86_64"}
    [[ $hwpf == "x86_64" ]] && return 0
    [[ $hwpf == "aarch64" ]] && return 0
    [[ $hwpf == "ppc64" ]] && return 1
    [[ $hwpf == "ppc64le" ]] && return 1
    [[ $hwpf == "s390x" ]] && return 0
    return 1
}

function checkVirtSupport
{
    typeset hwpf=${1?"*** what hardware-platform?, e.g. x86_64"}

    if grep -q "Red Hat Enterprise Linux release 8." /etc/redhat-release; then
        OSVERSION="RHEL8"
    else
        OSVERSION="ARK"
    fi

    if [[ $hwpf == "x86_64" ]]; then
        if (egrep -q 'vmx' /proc/cpuinfo); then
            CPUTYPE="INTEL"
        elif (egrep -q 'svm' /proc/cpuinfo); then
            CPUTYPE="AMD"
        fi
        egrep -q '(vmx|svm)' /proc/cpuinfo
        return $?
    elif [[ $hwpf == "aarch64" ]]; then
        if journalctl -k | egrep -qi "disabling GICv2" ; then
            GICVERSION="3"
        else
            GICVERSION="2"
        fi
        CPUTYPE="ARMGICv$GICVERSION"
        journalctl -k | egrep -iq "kvm.*: (Hyp|VHE) mode initialized successfully"
        return $?
    elif [[ $hwpf == "ppc64" || $hwpf == "ppc64le" ]]; then
        if (egrep -q 'POWER9' /proc/cpuinfo); then
            CPUTYPE="POWER9"
        else
            CPUTYPE="POWER8"
        fi
        grep -q 'platform.*PowerNV' /proc/cpuinfo
        return $?
    elif [[ $hwpf == "s390x" ]]; then
        CPUTYPE="S390X"
        grep -q 'features.*sie' /proc/cpuinfo
        return $?
    else
        return 1
    fi
}

function getTests
{
    # List of tests to run on all architectures
    ALLARCH_TESTS=()
    while IFS=  read -r -d $'\0'; do
        ALLARCH_TESTS+=("$REPLY")
    done < <(find ${BINDIR} -maxdepth 1 -type f -executable -printf "%f\0")

    # List of tests to run on x86_64 architecture
    X86_64_TESTS=()
    while IFS=  read -r -d $'\0'; do
        X86_64_TESTS+=("$REPLY")
    done < <(find ${BINDIR}/x86_64 -maxdepth 1 -type f -executable -printf "x86_64/%f\0")

    # List of tests to run on aarch64 architecture
    AARCH64_TESTS=()
    while IFS=  read -r -d $'\0'; do
        AARCH64_TESTS+=("$REPLY")
    done < <(find ${BINDIR}/aarch64 -maxdepth 1 -type f -executable -printf "aarch64/%f\0")

    # List of tests to run on ppc64 architecture
    PPC64_TESTS=()

    # List of tests to run on s390x architecture
    S390X_TESTS=()
    while IFS=  read -r -d $'\0'; do
        S390X_TESTS+=("$REPLY")
    done < <(find ${BINDIR}/s390x -maxdepth 1 -type f -executable -printf "s390x/%f\0")
}

function disableTests
{
    typeset hwpf=$(uname -i)

    # Disable tests for RHEL8 Kernel (4.18.X)
    if [[ $OSVERSION == "RHEL8" ]]; then

        # Disabled s390x tests due to bugs
        if [[ $hwpf == "s390x" ]]; then
            # Disable test demand_paging_test
            # due to https://bugzilla.redhat.com/show_bug.cgi?id=
            mapfile -d $'\0' -t ALLARCH_TESTS < <(printf '%s\0' "${ALLARCH_TESTS[@]}" | grep -Pzv "demand_paging_test")

            # Disable test dirty_log_test
            # due to https://bugzilla.redhat.com/show_bug.cgi?id=
            mapfile -d $'\0' -t ALLARCH_TESTS < <(printf '%s\0' "${ALLARCH_TESTS[@]}" | grep -Pzv "dirty_log_test")
        fi

        # Disabled ARM tests due to bugs
        if [[ $hwpf == "aarch64" ]]; then
            # Disabled tests for GICv2 systems
            if ! journalctl -k | egrep -qi "disabling GICv2" ; then
                # Disable test kvm_create_max_vcpus
                # due to https://bugzilla.redhat.com/show_bug.cgi?id=
                mapfile -d $'\0' -t ALLARCH_TESTS < <(printf '%s\0' "${ALLARCH_TESTS[@]}" | grep -Pzv "kvm_create_max_vcpus")
            fi
        fi
    fi

}
function runtest
{
    rlPhaseStartTest
    rlRun "pushd '.'"


    typeset linux_srcdir=$(find $TMPDIR -type d -a -name "linux-*")
    typeset tests_srcdir="$linux_srcdir/tools/testing/selftests/kvm"
    typeset outputdir="${BINDIR}"
    typeset hwpf=$(uname -i)

    rlAssertExists $tests_srcdir
    rlAssertExists ${outputdir}

    #
    # XXX: Apply a patch because case 'dirty_log_test' fails to be built, which
    #      is because patch [1] is missed when backporting to RHEL8 repo. Note
    #      we should remove the workaround if the case is fixed.
    #      [1] https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=07a262cc
    #
    # This patch was merged in version 4.18.0-97.el8 only earlier versions need to apply it
    rlTestVersion "${RELEASE}" "<" "4.18.0-97.el8"
    if (( $? == 0)); then
        rlRun "patch -d $linux_srcdir -p1 < patches/bitmap.h.patch" 0 \
              "Patching via patches/bitmap.h.patch"
    fi

    # Build tests
    [[ $hwpf == "x86_64" ]] && ARCH="x86_64"
    [[ $hwpf == "aarch64" ]] && ARCH="arm64"
    [[ $hwpf == "ppc64" || $hwpf == "ppc64le" ]] && ARCH="powerpc"
    [[ $hwpf == "s390x" ]] && ARCH="s390"
    rlRun "make -C ${tests_srcdir} OUTPUT=${outputdir} ARCH=${ARCH} TARGETS=kvm"

    # Prepare lists of tests to run
    getTests
    disableTests

    # Run tests
    for test in ${ALLARCH_TESTS[*]}; do rlRun "${outputdir}/${test}" 0,4; done
    [[ $hwpf == "x86_64" ]] && for test in ${X86_64_TESTS[*]}; do rlRun "${outputdir}/${test}" 0,4;  done
    [[ $hwpf == "aarch64" ]] && for test in ${AARCH64_TESTS[*]}; do rlRun "${outputdir}/${test}" 0,4;  done
    [[ $hwpf == "ppc64" || $hwpf == "ppc64le" ]] && for test in ${PPC64_TESTS[*]}; do rlRun "${outputdir}/${test}" 0,4; done
    [[ $hwpf == "s390x" ]] &&  for test in ${S390X_TESTS[*]}; do rlRun "${outputdir}/${test}" 0,4; done

    rlRun "popd"
    rlPhaseEnd
}

function setup
{
    typeset pkg=$PACKAGE

    rlPhaseStartSetup
    rlRun "pushd '.'"

    # tests are currently supported on x86_64, aarch64, ppc64 and s390x
    hwpf=$(uname -i)
    checkPlatformSupport $hwpf
    if (( $? == 0 )); then
        # test can only run on hardware that supports virtualization
        checkVirtSupport $hwpf
        rlLog "[$OSVERSION][$hwpf][$CPUTYPE] Running on supported arch"
        if (( $? == 0 )); then
            rlLog "[$OSVERSION][$hwpf][$CPUTYPE] Hardware supports virtualization, proceeding"
        else
            rlSkip "[$OSVERSION][$hwpf][$CPUTYPE] CPU doesn't support virtualization"
        fi
    else
        rlSkip "[$OSVERSION][$hwpf][$CPUTYPE] test is only supported on x86_64, aarch64 or s390x"
    fi

    # test should only run on a system with 1 or more cpus
    typeset cpus=$(grep -c ^processor /proc/cpuinfo)
    if (( $cpus > 1 )); then
        rlLog "[$OSVERSION][$hwpf][$CPUTYPE] You have sufficient CPU's to run the test"
    else
        rlSkip "[$OSVERSION][$hwpf][$CPUTYPE] system requires > 1 CPU"
    fi

    rlLog "[$OSVERSION][$hwpf][$CPUTYPE] Running tests for OSVERSION: $OSVERSION"
    rlLog "[$OSVERSION][$hwpf][$CPUTYPE] Running tests for ARCH: $hwpf"
    rlLog "[$OSVERSION][$hwpf][$CPUTYPE] Running tests for CPUTYPE: $CPUTYPE"

    KVM_SYSFS=/sys/module/kvm/parameters/
    KVM_OPTIONS=""
    if [[ $hwpf == "x86_64" ]]; then
        KVM_OPTIONS+=("enable_vmware_backdoor")
        KVM_OPTIONS+=("force_emulation_prefix")
    elif [[ $hwpf == "s390x" ]]; then
        KVM_OPTIONS+=("nested")
    fi

    KVM_ARCH=""
    KVM_MODULES=()
    KVM_ARCH_OPTIONS=()
    if [[ $CPUTYPE == "INTEL" ]]; then
        KVM_ARCH="kvm_intel"
        KVM_ARCH_OPTIONS+=("nested")
    elif [[ $CPUTYPE == "AMD" ]]; then
        KVM_ARCH="kvm_amd"
        KVM_ARCH_OPTIONS+=("nested")
    elif [[ $hwpf == "ppc64" || $hwpf == "ppc64le" ]]; then
        KVM_ARCH="kvm_hv"
        KVM_MODULES+=("kvm_pr")
        KVM_ARCH_OPTIONS+=("nested")
    fi
    KVM_MODULES+=("$KVM_ARCH")
    KVM_MODULES+=("kvm")
    KVM_ARCH_SYSFS=/sys/module/$KVM_ARCH/parameters/

    # Set the KVM parameters needed for the tests
    > $KVMPARAMFILE
    for opt in ${KVM_OPTIONS[*]}; do
        echo -e "options kvm $opt=1\n" >> $KVMPARAMFILE
    done
    for opt in ${KVM_ARCH_OPTIONS[*]}; do
        echo -e "options $KVM_ARCH $opt=1\n" >> $KVMPARAMFILE
    done

    # Export env variables used by KVM Unit Tests
    export TIMEOUT=3000s

    # Reload the modules
    for mod in ${KVM_MODULES[*]}; do rmmod -f $mod > /dev/null 2>&1; done
    modprobe -a kvm $KVM_ARCH

    # Test if the KVM parameters were set correctly
    for opt in ${KVM_OPTIONS[*]}; do
        if ! cat $KVM_SYSFS/$opt | egrep -q "Y|y|1"; then
            rlLog "[$OSVERSION][$hwpf][$CPUTYPE] kvm module option $opt not set"
            rstrnt-report-result $TEST WARN
            rstrnt-abort -t recipe
        else
            rlLog "[$OSVERSION][$hwpf][$CPUTYPE] kvm module option $opt is set"
        fi
    done
    for opt in ${KVM_ARCH_OPTIONS[*]}; do
        if ! cat $KVM_ARCH_SYSFS/$opt | egrep -q "Y|y|1"; then
            rlLog "[$OSVERSION][$hwpf][$CPUTYPE] $KVM_ARCH module option $opt not set"
            rstrnt-report-result $TEST WARN
            rstrnt-abort -t recipe
        else
            rlLog "[$OSVERSION][$hwpf][$CPUTYPE] $KVM_ARCH module option $opt is set"
        fi
    done
    rlRun "rm -rf $TMPDIR && mkdir $TMPDIR"
    rlRun "rm -rf ${BINDIR} && mkdir -p ${BINDIR}/x86_64 && mkdir -p ${BINDIR}/s390x && mkdir ${BINDIR}/aarch64"

    # if running on rhel8, use python3
    if [[ $OSVERSION == "RHEL8" ]] && [ ! -f /usr/bin/python ]; then
        ln -s /usr/libexec/platform-python /usr/bin/python
    fi

    rlRun "cd $TMPDIR"
    if [ -x /usr/bin/dnf ]; then
        dnf download ${pkg} --source
    elif [ -x /usr/bin/yum ]; then
        yum download ${pkg} --source
    fi
    if [ ! -f $TMPDIR/${pkg}.src.rpm ]; then
        rlFetchSrcForInstalled $pkg
    fi
    typeset rpmfile=$(ls -1 $TMPDIR/${pkg}.src.rpm)
    rlAssertExists $rpmfile
    rlRun "ls -l $rpmfile"

    rlRun "rpm -ivh --define '_topdir $TMPDIR' $rpmfile" 0

    typeset linux_tarball=$(find $TMPDIR -name "linux*.tar.xz")
    rlAssertExists $linux_tarball
    rlRun "ls -l $linux_tarball"

    typeset tarball_dirname=$(dirname $linux_tarball)
    rlRun "cd $tarball_dirname"
    rlRun "tar Jxf $linux_tarball"

    rlRun "popd"
    rlPhaseEnd
}

function cleanup
{
    rlPhaseStartCleanup
    rlRun "pushd '.'"

    rlRun "rm -rf $TMPDIR"
    rlRun "rm -rf ${BINDIR}"

    rlRun "popd"
    rlPhaseEnd
}

function main
{
    rlJournalStart

    setup
    runtest
    cleanup

    rlJournalEnd
}

main
exit $?
