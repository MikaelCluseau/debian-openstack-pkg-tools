# -*- Makefile -*-, you silly Emacs!
# vim: set ft=make:

DEBVERS		?= $(shell dpkg-parsechangelog | sed -n -e 's/^Version: //p')
VERSION		?= $(shell echo '$(DEBVERS)' | sed -e 's/^[[:digit:]]*://' -e 's/[-].*//')
DEBFLAVOR	?= $(shell dpkg-parsechangelog | grep -E ^Distribution: | cut -d" " -f2)
DEBPKGNAME	?= $(shell dpkg-parsechangelog | grep -E ^Source: | cut -d" " -f2)
UPSTREAM_GIT	?= git://github.com/openstack/$(DEBPKGNAME).git
GIT_TAG		?= $(shell echo '$(VERSION)' | sed -e 's/~/_/')
MANIFEST_EXCLUDE_STANDARD ?= $(DEBPKGNAME)

# Activate xz compression
override_dh_builddeb:
	dh_builddeb -- -Zxz -z9

# Only use upstart scripts in Ubuntu. All .upstart files have to be renamed .upstart.in
override_dh_installinit:
	if dpkg-vendor --derives-from ubuntu ; then \
		for i in *.upstart.in ; do \
			MYPKG=`echo $i | cut -d. -f1` ; \
			cp $$MYPKG.upstart.in $$MYPKG.upstart ; \
		done ; \
        fi
	dh_installinit --error-handler=true

gen-author-list:
	git log --format='%aN <%aE>' | awk '{arr[$0]++} END{for (i in arr){print arr[i], i;}}' | sort -rn | cut -d' ' -f2-

gen-upstream-changelog:
	git checkout master
	git reset --hard $(GIT_TAG)
	git log >$(CURDIR)/../CHANGELOG
	git checkout debian/$(DEBFLAVOR)
	mv $(CURDIR)/../CHANGELOG $(CURDIR)/debian/CHANGELOG
	git add $(CURDIR)/debian/CHANGELOG
	git commit -a -m "Updated upstream changelog"

override_dh_installchangelogs:
	if [ -e $(CURDIR)/debian/CHANGELOG ] ; then \
		dh_installchangelogs $(CURDIR)/debian/CHANGELOG ; \
	else \
		dh_installchangelogs ; \
	fi

get-orig-source:
	uscan --verbose --force-download --rename --destdir=../build-area

get-vcs-source:
	git remote add upstream $(UPSTREAM_GIT) || true
	git fetch upstream
	if [ ! -f ../$(DEBPKGNAME)_$(VERSION).orig.tar.xz ] ; then \
		git archive --prefix=$(DEBPKGNAME)-$(GIT_TAG)/ $(GIT_TAG) | xz >../$(DEBPKGNAME)_$(VERSION).orig.tar.xz ; \
	fi
	[ ! -e ../build-area ] && mkdir ../build-area
	[ ! -e ../build-area/$(DEBPKGNAME)_$(VERSION).orig.tar.xz ] && cp ../$(DEBPKGNAME)_$(VERSION).orig.tar.xz ../build-area
	if ! git checkout master ; then \
		echo "No upstream branch: checking out" ; \
		git checkout -b master upstream/master ; \
	fi
	git checkout debian/$(DEBFLAVOR)

versioninfo:
	echo $(VERSION) > versioninfo

display-po-stats:
	cd $(CURDIR)/debian/po ; for i in *.po ; do \
		echo -n $$i": " ; \
		msgfmt -o /dev/null --statistic $$i ; \
	done

call-for-po-trans:
	podebconf-report-po --call --withtranslators --languageteam

regen-manifest-patch:
	quilt pop -a || true
	quilt push install-missing-files.patch
	git checkout MANIFEST.in
	git ls-files --no-empty-directory --exclude-standard $(MANIFEST_EXCLUDE_STANDARD) | grep -v '.py$$' | grep -v LICENSE | sed -n 's/.*/include &/gp' >> MANIFEST.in
	quilt refresh
	quilt pop -a

override_dh_gencontrol:
	if dpkg-vendor --derives-from ubuntu ; then \
		dh_gencontrol -- -T$(CURDIR)/debian/ubuntu_control_vars ; \
	else \
		dh_gencontrol -- -T$(CURDIR)/debian/debian_control_vars ; \
	fi

.PHONY: get-vcs-source get-orig-source override_dh_installinit override_dh_builddeb regen-manifest-patch call-for-po-trans display-po-stats versioninfo
