# Set to 'yes' to include debugging information, e.g. DEBUG=yes make -e
DEBUG := no

PREFIX ?= /usr
ARCH := $(shell uname -m)
UID := $(shell id -u)
GID := $(shell id -g)
USE_FEDORA_LIBDIR := $(shell test -d /lib64/security && echo 1 || echo 0)
VERSION := $(shell git for-each-ref --sort=creatordate --format '%(tag)' refs/tags | tail -n 1).$(shell git rev-list --count $(shell git for-each-ref --sort=creatordate --format '%(tag)' refs/tags | tail -n 1)..HEAD)

ifeq ($(ARCH), x86_64)
	ifeq ($(USE_FEDORA_LIBDIR), 1)
		LIBDIR ?= lib64
	else
		LIBDIR ?= lib/x86_64-linux-gnu
	endif
endif
ifeq ($(ARCH), i686)
	LIBDIR ?= lib
endif
ifeq ($(ARCH), aarch64) # ARM64, i.e Apple silicon and other up2date CPUs/SoCs
	LIBDIR ?= lib/aarch64-linux-gnu
endif
ifeq ($(ARCH), armv7l) # ARM32, i.e Raspberries
	LIBDIR ?= lib/arm-linux-gnueabihf
endif
ifeq ($(ARCH), m68k-linux-gnu) # Motorola 68k - Amiga forever
	LIBDIR ?= lib/m68k-linux-gnu
endif

# compiler/linker options
CC := gcc
CFLAGS := $(CFLAGS) -Wall -fPIC `pkg-config --cflags libxml-2.0` `pkg-config --cflags udisks2` #cflags libxml?
ifeq (yes, ${DEBUG})
	CFLAGS := ${CFLAGS} -ggdb
endif

LIBS := `pkg-config --libs libxml-2.0` `pkg-config --libs udisks2`

# common source files
SRCS := src/conf.c \
	src/mem.c \
	src/log.c \
	src/xpath.c \
	src/pad.c \
	src/volume.c \
	src/process.c \
	src/tmux.c \
	src/local.c \
	src/device.c
OBJS := $(SRCS:.c=.o)

# pam_usb
PAM_USB_SRCS := src/pam.c
PAM_USB_OBJS := $(PAM_USB_SRCS:.c=.o)
PAM_USB	:= pam_usb.so
PAM_USB_LDFLAGS := -shared
PAM_USB_DEST := $(DESTDIR)/$(LIBDIR)/security

# pamusb-check
PAMUSB_CHECK_SRCS := src/pamusb-check.c
PAMUSB_CHECK_OBJS := $(PAMUSB_CHECK_SRCS:.c=.o)
PAMUSB_CHECK := pamusb-check

# Tools
PAMUSB_CONF := pamusb-conf
PAMUSB_AGENT := pamusb-agent
PAMUSB_KEYRING_GNOME := pamusb-keyring-unlock-gnome
PAMUSB_PINENTRY := pamusb-pinentry
TOOLS_DEST := $(DESTDIR)$(PREFIX)/bin
TOOLS_SRC := tools

# Conf
CONFS := doc/pam_usb.conf
CONFS_DEST := $(DESTDIR)/etc/security

# Doc
DOCS := doc/CONFIGURATION doc/QUICKSTART doc/SECURITY doc/TROUBLESHOOTING
DOCS_DEST := $(DESTDIR)$(PREFIX)/share/doc/pam_usb

# Man
MANS := doc/pamusb-conf.1.gz doc/pamusb-agent.1.gz doc/pamusb-check.1.gz doc/pamusb-keyring-unlock-gnome.1.gz doc/pamusb-pinentry.1.gz
MANS_DEST := $(DESTDIR)$(PREFIX)/share/man/man1

# PAM config
PAM_CONF := debian/pam-auth-update/usb
PAM_CONF_DEST := $(DESTDIR)$(PREFIX)/share/pam-configs

# Binaries
RM  := rm
INSTALL	:= install
MKDIR := mkdir
DEBUILD	:= debuild -b -uc -us --lintian-opts --profile debian
RPMBUILD := rpmbuild -v -bb --clean fedora/SPECS/pam_usb.spec
ZSTBUILD := cd arch_linux && makepkg -p PKGBUILD_git && cd ..
MANCOMPILE := gzip -kf
DOCKER := docker

all: manpages $(PAM_USB) $(PAMUSB_CHECK)

$(PAM_USB): $(OBJS) $(PAM_USB_OBJS)
	$(CC) -o $(PAM_USB) $(PAM_USB_LDFLAGS) $(LDFLAGS) $(OBJS) $(PAM_USB_OBJS) $(LIBS)

$(PAMUSB_CHECK): $(OBJS) $(PAMUSB_CHECK_OBJS)
	$(CC) -o $(PAMUSB_CHECK) $(LDFLAGS) $(OBJS) $(PAMUSB_CHECK_OBJS) $(LIBS)

%.o: %.c
	${CC} -c ${CFLAGS} $< -o $@

clean:
	$(RM) -f \
		$(MANS) \
		$(PAM_USB) \
		$(PAMUSB_CHECK) \
		$(OBJS) \
		$(PAMUSB_CHECK_OBJS) \
		$(PAM_USB_OBJS)

manpages:
	$(MANCOMPILE) ./doc/*.1

update-other-docs:
	wget https://raw.githubusercontent.com/wiki/mcdope/pam_usb/Configuration.md -O doc/CONFIGURATION > /dev/null 2>&1
	wget https://raw.githubusercontent.com/wiki/mcdope/pam_usb/Getting-Started.md -O doc/QUICKSTART > /dev/null 2>&1
	wget https://raw.githubusercontent.com/wiki/mcdope/pam_usb/Security.md -O doc/SECURITY > /dev/null 2>&1
	wget https://raw.githubusercontent.com/wiki/mcdope/pam_usb/Troubleshooting.md -O doc/TROUBLESHOOTING > /dev/null 2>&1
	git status --porcelain=v1 2>/dev/null && echo "Committing docs..." || { echo "Git staging area needs to be clean!"; exit 1; }
	git add \
		doc/CONFIGURATION \
		doc/QUICKSTART \
		doc/SECURITY \
		doc/TROUBLESHOOTING \
		 > /dev/null 2>&1
	git commit \
		--author="make update-other-docs <noemail@example.com>" \
		--signoff \
		-m "[Docs] Update non-manpage \"doc/\" files" \
		 > /dev/null 2>&1 || { git reset doc/CONFIGURATION doc/QUICKSTART doc/SECURITY doc/TROUBLESHOOTING; echo "No changes to commit."; }

install: all
	$(MKDIR) -p \
		$(CONFS_DEST) \
		$(DOCS_DEST) \
		$(MANS_DEST) \
		$(TOOLS_DEST) \
		$(PAM_USB_DEST)

	$(INSTALL) -m755 $(PAM_USB) $(PAM_USB_DEST)
	$(INSTALL) -m755 $(PAMUSB_CHECK) $(TOOLS_SRC)/$(PAMUSB_CONF) $(TOOLS_SRC)/$(PAMUSB_AGENT) $(TOOLS_SRC)/$(PAMUSB_KEYRING_GNOME) $(TOOLS_SRC)/$(PAMUSB_PINENTRY) $(TOOLS_DEST)
	$(INSTALL) -m644 $(DOCS) $(DOCS_DEST)
	$(INSTALL) -m644 $(MANS) $(MANS_DEST)

	if test -d $(PAM_CONF_DEST); then $(INSTALL) -m644 $(PAM_CONF) $(PAM_CONF_DEST)/libpam-usb; fi
	if test -f $(CONFS_DEST)/pam_usb.conf; then $(INSTALL) -b -m644 $(CONFS) $(CONFS_DEST)/pam_usb.conf.dist; fi
	if test ! -f $(CONFS_DEST)/pam_usb.conf; then $(INSTALL) -b -m644 $(CONFS) $(CONFS_DEST); fi

# force pam-auth-update config install if building a deb
	if test $(DEB_TARGET_ARCH) != "" > /dev/null 2>&1; then mkdir -p $(PAM_CONF_DEST) && $(INSTALL) -m644 $(PAM_CONF) $(PAM_CONF_DEST)/libpam-usb; fi

	update-alternatives --install /usr/bin/pinentry pinentry $(TOOLS_DEST)/pamusb-pinentry 100 || exit 0

deinstall:
	$(RM) -f $(PAM_USB_DEST)/$(PAM_USB)
	$(RM) -f \
		$(TOOLS_DEST)/$(PAMUSB_CHECK) \
		$(TOOLS_DEST)/$(PAMUSB_CONF) \
		$(TOOLS_DEST)/$(PAMUSB_AGENT) \
		$(TOOLS_DEST)/$(PAMUSB_KEYRING_GNOME) \
		$(TOOLS_DEST)/$(PAMUSB_PINENTRY) \
		$(PAM_CONF_DEST)/$(PAM_CONF)

	$(RM) -rf $(DOCS_DEST)
	$(RM) -f $(MANS_DEST)/pamusb-*\.1\.gz
	$(RM) -f $(PAM_CONF_DEST)/$(PAM_CONF)

uninstall: deinstall

changelog:
	git log --pretty=format:"%h %ad%x09%an%x09%s" --date=short 40b17fa..HEAD > changelog-from-v0.5.0

debchangelog:
	git log --pretty=format:"  * %s (%an <%ae>)" --date=short 40b17fa..HEAD > changelog-for-deb

builddir:
	mkdir -p .build > /dev/null 2>&1 || echo 0

deb: clean builddir
	$(DEBUILD)

deb-sign: build-debian
	debsign -S -k$(APT_SIGNING_KEY) `ls -t .build/*.changes | head -1`

rpm: clean builddir
	$(RPMBUILD)
	yes | cp -rf fedora/RPMS/$(ARCH)/*.rpm .build

rpm-sign: build-fedora
	rpm --addsign `ls -t .build/*.rpm | head -1`

rpm-lint: build-fedora
	rpmlint `ls -t .build/*.rpm | head -1`

zst: clean builddir
	rm -f arch_linux/*.zst
	$(ZSTBUILD)
	yes | cp -rf arch_linux/*.zst .build
	rm -rf arch_linux/pam_usb arch_linux/src arch_linux/pkg arch_linux/*.tar.gz arch_linux/*.zst

sourcegz: clean builddir
	tar --exclude="debian/.debhelper" \
		--exclude="debian/files" \
		--exclude="debian/libpam-usb/*" \
		--exclude="debian/libpam-usb.debhelper.log" \
		--exclude="debian/libpam-usb.substvars" \
		--exclude="debian/debhelper-build-stamp" \
		--exclude="debian/libpam-usb.postinst.debhelper" \
		--exclude="debian/libpam-usb.postrm.debhelper" \
		--exclude="debian/libpam-usb.prerm.debhelper" \
		--exclude="fedora/RPMS/x86_64" \
		--exclude="fedora/BUILD/*" \
		--exclude="tests" \
		--exclude=".build" \
		--exclude=".idea" \
		--exclude=".vscode" \
		--exclude=".github" \
		--exclude=".git" \
		-zcvf .build/pam_usb-$(VERSION).tar.gz .

buildenv-debian:
	$(DOCKER) build -f Dockerfile.debian -t mcdope/pam_usb-ubuntu-build .

buildenv-fedora:
	$(DOCKER) build -f Dockerfile.fedora -t mcdope/pam_usb-fedora-build .

buildenv-arch:
	$(DOCKER) build -f Dockerfile.arch -t mcdope/pam_usb-arch-build .

build-debian: buildenv-debian
	$(DOCKER) run -i \
		-v`pwd`/.build:/usr/local/src \
		-v`pwd`:/usr/local/src/pam_usb \
		--rm mcdope/pam_usb-ubuntu-build \
		sh -c "make deb && chown -R $(UID):$(GID) .build debian"

build-fedora: buildenv-fedora
	$(DOCKER) run -i \
		-v`pwd`/.build:/usr/local/src \
		-v`pwd`:/usr/local/src/pam_usb \
		--rm mcdope/pam_usb-fedora-build \
		sh -c "make rpm && chown -R $(UID):$(GID) .build fedora"

build-arch: buildenv-arch
	$(DOCKER) run -i \
		-v`pwd`/.build:/usr/local/src \
		-v`pwd`:/usr/local/src/pam_usb \
		--rm mcdope/pam_usb-arch-build \
		sh -c "chown -R builduser:builduser . && sudo -u builduser make zst && chown -R $(UID):$(GID) ."
