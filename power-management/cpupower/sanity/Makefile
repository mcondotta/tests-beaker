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

export TEST		:= /kernel/power-management/cpupower/sanity
export TESTVERSION	:= 1.0

BUILT_FILES		= runtest

FILES			= $(METADATA) \
			  Makefile \
			  PURPOSE \
			  README.md \
			  runtest.sh \
			  utils/cpupower_sanity_test.sh

.PHONY: all install download clean

run: $(FILES) build
	./runtest

runtest: runtest.sh
	cp $< $@ && chmod +x $@

build: $(BUILT_FILES)

clean:
	rm -f *~ $(BUILT_FILES)

# Common Variables
TEST_DIR=/mnt/tests$(TEST)
INSTALL_DIR=$(DEST)$(TEST_DIR)
METADATA=testinfo.desc

$(METADATA): Makefile
	@echo "Owner:        Erik Hamera <ehamera@redhat.com>" > $(METADATA)
	@echo "Name:         $(TEST)" >> $(METADATA)
	@echo "TestVersion:  $(TESTVERSION)" >> $(METADATA)
	@echo "Path:         $(TEST_DIR)" >> $(METADATA)
	@echo "Description:  Check, that output of cpupower is sane" >> $(METADATA)
	@echo "Type:         Sanity" >> $(METADATA)
	@echo "RunFor:       kernel" >> $(METADATA)
	@echo "Requires:     kernel" >> $(METADATA)
	@echo "Requires:     kernel-tools" >> $(METADATA)
	@echo "Requires:     virt-what" >> $(METADATA)
	@echo "Requires:     cpupowerutils" >> $(METADATA)
	@echo "Requires:     bc" >> $(METADATA)
	@echo "Requires:     python2-lxml" >> $(METADATA)
	@echo "Requires:     python3-lxml" >> $(METADATA)
	@echo "repoRequires: cki_lib" >> $(METADATA)
	@echo "repoRequires: power-management/common" >> $(METADATA)
	@echo "Priority:     Normal" >> $(METADATA)
	@echo "License:      GPLv2 or above" >> $(METADATA)
	@echo "Confidential: no" >> $(METADATA)
	@echo "Destructive:  no" >> $(METADATA)
