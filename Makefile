VERSION = $(shell date +'%Y.%m.%d')
NAME = greenbone-community-edition
DEB = $(NAME)_$(VERSION)_amd64.deb
LIBDIR = /usr/lib/x86_64-linux-gnu
DESTDIR = $(PWD)/debian/tmp
QBINDIR = $(DESTDIR)/usr/bin
QSBINDIR = $(DESTDIR)/usr/sbin
QLIBDIR = $(DESTDIR)$(LIBDIR)

export PKG_CONFIG_PATH = $(QLIBDIR)/pkgconfig
export CFLAGS = -I$(DESTDIR)/usr/include
export CXXFLAGS = -I$(DESTDIR)/usr/include
export LDFLAGS = -L$(QLIBDIR)
export LD_LIBRARY_PATH = $(QLIBDIR)

all: check-release install-deps $(DEB)

check-release:
	cat /etc/os-release | grep -q UBUNTU_CODENAME=focal

# ----------------------------- dependencies -----------------------------
PSQL_LIST = /etc/apt/sources.list.d/pgdg.list
NODE_LIST = /etc/apt/sources.list.d/nodesource.list
YARN_LIST = /etc/apt/sources.list.d/yarn.list

install-deps: ubuntu-deps external-deps

ubuntu-deps:
	su -c 'apt update'
	su -c 'apt install --no-install-recommends --assume-yes \
		binutils \
		bison \
		build-essential \
		cmake \
		curl \
		gnupg \
		libbsd-dev \
		libgcrypt20-dev \
		libglib2.0-dev \
		libgnutls28-dev \
		libgpgme-dev \
		libhiredis-dev \
		libical-dev \
		libjson-glib-dev \
		libksba-dev \
		libmicrohttpd-dev \
		libnet1-dev \
		libpcap-dev \
		libssh-gcrypt-dev \
		libssl-dev \
		libxml2-dev \
		pkg-config \
		python3.9 \
		python3-pip \
		python3-setuptools \
		uuid-dev \
		xsltproc'

external-deps: $(PSQL_LIST) $(NODE_LIST) $(YARN_LIST)
	su -c 'apt update'
	su -c 'apt install --assume-yes \
		libpq-dev \
		postgresql-server-dev-14 \
		yarn'

$(PSQL_LIST):
	curl https://www.postgresql.org/media/keys/ACCC4CF8.asc | su -c 'apt-key add -'
	echo "deb http://apt.postgresql.org/pub/repos/apt focal-pgdg main" | su -c "tee $(PSQL_LIST)"

NODE_VERSION=14
$(NODE_LIST):
	curl https://deb.nodesource.com/gpgkey/nodesource.gpg.key | su -c 'apt-key add -'
	echo "deb https://deb.nodesource.com/node_$(NODE_VERSION).x focal main" | su -c "tee $(NODE_LIST)"

$(YARN_LIST):
	curl https://dl.yarnpkg.com/debian/pubkey.gpg | su -c 'apt-key add -'
	echo "deb https://dl.yarnpkg.com/debian/ stable main" | su -c "tee $(YARN_LIST)"

# ----------------------------- .deb -----------------------------
LIBPAHO_MQTT = $(QLIBDIR)/libpaho-mqtt3c.so
LIBGVM_UTIL = $(QLIBDIR)/libgvm_util.so
GVMD_BIN = $(QSBINDIR)/gvmd
PG_GVM_BIN = $(DESTDIR)/usr/lib/postgresql/14/lib/libpg-gvm.so
GSA_INDEX = $(DESTDIR)/usr/share/gvm/gsad/web/index.html
GSAD_BIN = $(QSBINDIR)/gsad
OPENVAS_SCANNER_BIN = $(QSBINDIR)/openvas
OSPD_OPENVAS_PY = $(DESTDIR)/usr/lib/python3.9/dist-packages/ospd_openvas/__init__.py
NOTUS_SCANNER_PY = $(DESTDIR)/usr/lib/python3.9/dist-packages/notus/scanner/__init__.py
GREENBONE_FEED_SYNC_PY = $(DESTDIR)/usr/bin/greenbone-feed-sync
GVM_TOOLS_PY = $(DESTDIR)/usr/bin/gvm-cli

BINARIES = \
	$(LIBPAHO_MQTT) \
	$(LIBGVM_UTIL) \
	$(GVMD_BIN) \
	$(PG_GVM_BIN) \
	$(GSA_INDEX) \
	$(GSAD_BIN) \
	$(OPENVAS_SCANNER_BIN) \
	$(OSPD_OPENVAS_PY) \
	$(NOTUS_SCANNER_PY) \
	$(GREENBONE_FEED_SYNC_PY) \
	$(GVM_TOOLS_PY) \

$(DEB): $(DESTDIR)/DEBIAN/control $(BINARIES)
	rm -rf $(DESTDIR)/run
	mkdir -p $(DESTDIR)/var/lib/notus/products
	install -D -m 0440 configs/etc/sudoers.d/90_gvm $(DESTDIR)/etc/sudoers.d/90_gvm
	test ! -f $(DESTDIR)/usr/bin/pygmentize || mv $(DESTDIR)/usr/bin/pygmentize $(DESTDIR)/usr/bin/pygmentize3.9
	test ! -f $(DESTDIR)/usr/bin/markdown-it || mv $(DESTDIR)/usr/bin/markdown-it $(DESTDIR)/usr/bin/markdown-it3.9
	dpkg-deb --root-owner-group --build $(DESTDIR) .

$(DESTDIR)/DEBIAN/control: debian/substvars debian/postinst
	mkdir -p $(DESTDIR)/DEBIAN
	dpkg-gencontrol -v$(VERSION) -UMulti-Arch
	cp debian/postinst debian/triggers $(DESTDIR)/DEBIAN

debian/substvars: $(BINARIES)
	echo 'misc:Depends=python3.9 (>= 3.9.0), redis-server (>= 5:5.0), mosquitto (>= 1.6.9), postgresql-14 (>= 14.8), rsync, xml-twig-tools, xsltproc, nmap' > debian/substvars
	echo "binary:Version=$(VERSION)" >> debian/substvars
	dpkg-shlibdeps $(QLIBDIR)/*.so $(QSBINDIR)/*

# ----------------------------- paho-mqtt -----------------------------
PAHO_MQTT_VERSION = 1.3.12
PAHO_MQTT = paho.mqtt.c-$(PAHO_MQTT_VERSION)
PAHO_MQTT_TAR = $(PAHO_MQTT).tar.gz
PAHO_MQTT_BUILD = $(PAHO_MQTT)-build
$(LIBPAHO_MQTT): $(PAHO_MQTT_TAR)
	tar -xf $(PAHO_MQTT_TAR)
	mkdir -p $(PAHO_MQTT_BUILD)
	cd $(PAHO_MQTT_BUILD) && cmake \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX=/usr \
		../$(PAHO_MQTT)
	cd $(PAHO_MQTT_BUILD) && make
	cd $(PAHO_MQTT_BUILD) && make DESTDIR=$(DESTDIR) install
	rm -r "$(DESTDIR)/usr/share/doc/Eclipse Paho C"

$(PAHO_MQTT_TAR):
	curl -f -L \
		https://github.com/eclipse/paho.mqtt.c/archive/refs/tags/v$(PAHO_MQTT_VERSION).tar.gz \
		-o $(PAHO_MQTT_TAR)

# ----------------------------- gvm-libs -----------------------------
GVM_LIBS_VERSION = 22.6.1
GVM_LIBS = gvm-libs-$(GVM_LIBS_VERSION)
GVM_LIBS_TAR = $(GVM_LIBS).tar.gz
GVM_LIBS_BUILD = $(GVM_LIBS)-build
$(LIBGVM_UTIL): $(GVM_LIBS_TAR) $(LIBPAHO_MQTT)
	tar -xf $(GVM_LIBS_TAR)
	mkdir -p $(GVM_LIBS_BUILD)
	cd $(GVM_LIBS_BUILD) && cmake \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_LIBRARY_PATH=$(QLIBDIR) \
		-DLIBDIR=$(LIBDIR) \
		../$(GVM_LIBS)
	cd $(GVM_LIBS_BUILD) && make
	cd $(GVM_LIBS_BUILD) && make DESTDIR=$(DESTDIR) install

$(GVM_LIBS_TAR):
	curl -f -L \
		https://github.com/greenbone/gvm-libs/archive/refs/tags/v$(GVM_LIBS_VERSION).tar.gz \
		-o $(GVM_LIBS_TAR)

# ----------------------------- gvmd -----------------------------
GVMD_VERSION = 22.4.2
GVMD = gvmd-$(GVMD_VERSION)
GVMD_TAR = $(GVMD).tar.gz
GVMD_BUILD = $(GVMD)-build
$(GVMD_BIN): $(GVMD_TAR) $(LIBGVM_UTIL)
	tar -xf $(GVMD_TAR)
	mkdir -p $(GVMD_BUILD)
	cd $(GVMD_BUILD) && cmake \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DLIBDIR=$(LIBDIR) \
		-DSYSTEMD_SERVICE_DIR=/usr/lib/systemd/system \
		-DGVM_DATA_DIR=/var \
		-DPostgreSQL_ADDITIONAL_VERSIONS=14 \
		../$(GVMD)
	cd $(GVMD_BUILD) && make
	cd $(GVMD_BUILD) && make DESTDIR=$(DESTDIR) install
	install -D -m 644 configs/usr/lib/tmpfiles.d/greenbone.conf $(DESTDIR)/usr/lib/tmpfiles.d/greenbone.conf
	install -D -m 644 configs/usr/lib/systemd/system/gvmd.service $(DESTDIR)/usr/lib/systemd/system/gvmd.service

$(GVMD_TAR):
	curl -f -L \
		https://github.com/greenbone/gvmd/archive/refs/tags/v$(GVMD_VERSION).tar.gz \
		-o $(GVMD_TAR)

# ----------------------------- pg-gvm -----------------------------
PG_GVM_VERSION = 22.4.0
PG_GVM = pg-gvm-$(PG_GVM_VERSION)
PG_GVM_TAR = $(PG_GVM).tar.gz
PG_GVM_BUILD = $(PG_GVM)-build
$(PG_GVM_BIN): $(PG_GVM_TAR)
	tar -xf $(PG_GVM_TAR)
	mkdir -p $(PG_GVM_BUILD)
	cd $(PG_GVM_BUILD) && cmake \
		-DCMAKE_BUILD_TYPE=Release \
		-DPostgreSQL_ADDITIONAL_VERSIONS=14 \
		../$(PG_GVM)
	cd $(PG_GVM_BUILD) && make
	cd $(PG_GVM_BUILD) && make DESTDIR=$(DESTDIR) install

$(PG_GVM_TAR):
	curl -f -L \
		https://github.com/greenbone/pg-gvm/archive/refs/tags/v$(PG_GVM_VERSION).tar.gz \
		-o $(PG_GVM_TAR)

# ----------------------------- gsa -----------------------------
GSA_VERSION = 22.4.1
GSA = gsa-$(GSA_VERSION)
GSA_TAR = $(GSA).tar.gz
$(GSA_INDEX): $(GSA_TAR)
	tar -xf $(GSA_TAR)
	cd $(GSA) && yarn
	cd $(GSA) && yarn build
	mkdir -p $(DESTDIR)/usr/share/gvm/gsad/
	cp -avT $(GSA)/build $(DESTDIR)/usr/share/gvm/gsad/web

$(GSA_TAR):
	curl -f -L \
		https://github.com/greenbone/gsa/archive/refs/tags/v$(GSA_VERSION).tar.gz \
		-o $(GSA_TAR)

# ----------------------------- gsad -----------------------------
GSAD_VERSION = 22.4.1
GSAD = gsad-$(GSAD_VERSION)
GSAD_TAR = $(GSAD).tar.gz
GSAD_BUILD = $(GSAD)-build
$(GSAD_BIN): $(GSAD_TAR)
	tar -xf $(GSAD_TAR)
	mkdir -p $(GSAD_BUILD)
	cd $(GSAD_BUILD) && cmake \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DLIBDIR=$(LIBDIR) \
		-DSYSTEMD_SERVICE_DIR=/usr/lib/systemd/system \
		../$(GSAD)
	cd $(GSAD_BUILD) && make
	cd $(GSAD_BUILD) && make DESTDIR=$(DESTDIR) install
	install -D -m 644 configs/usr/lib/systemd/system/gsad.service $(DESTDIR)/usr/lib/systemd/system/gsad.service

$(GSAD_TAR):
	curl -f -L \
		https://github.com/greenbone/gsad/archive/refs/tags/v$(GSAD_VERSION).tar.gz \
		-o $(GSAD_TAR)

# ----------------------------- openvas-scanner -----------------------------
OPENVAS_SCANNER_VERSION = 22.7.1
OPENVAS_SCANNER = openvas-scanner-$(OPENVAS_SCANNER_VERSION)
OPENVAS_SCANNER_TAR = $(OPENVAS_SCANNER).tar.gz
OPENVAS_SCANNER_BUILD = $(OPENVAS_SCANNER)-build
$(OPENVAS_SCANNER_BIN): $(OPENVAS_SCANNER_TAR) $(LIBGVM_UTIL)
	tar -xf $(OPENVAS_SCANNER_TAR)
	mkdir -p $(OPENVAS_SCANNER_BUILD)
	cd $(OPENVAS_SCANNER_BUILD) && cmake \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DLIBDIR=$(LIBDIR) \
		../$(OPENVAS_SCANNER)
	cd $(OPENVAS_SCANNER_BUILD) && make
	cd $(OPENVAS_SCANNER_BUILD) && make DESTDIR=$(DESTDIR) install
	install -D -m 644 $(OPENVAS_SCANNER)/config/redis-openvas.conf $(DESTDIR)/etc/redis/redis-openvas.conf
	install -D -m 644 configs/etc/openvas/openvas.conf $(DESTDIR)/etc/openvas/openvas.conf

$(OPENVAS_SCANNER_TAR):
	curl -f -L \
		https://github.com/greenbone/openvas-scanner/archive/refs/tags/v$(OPENVAS_SCANNER_VERSION).tar.gz \
		-o $(OPENVAS_SCANNER_TAR)

# ----------------------------- ospd-openvas -----------------------------
OSPD_OPENVAS_VERSION = 22.5.1
OSPD_OPENVAS = ospd-openvas-$(OSPD_OPENVAS_VERSION)
OSPD_OPENVAS_TAR = $(OSPD_OPENVAS).tar.gz
$(OSPD_OPENVAS_PY): $(OSPD_OPENVAS_TAR)
	tar -xf $(OSPD_OPENVAS_TAR)
	cd $(OSPD_OPENVAS) && python3.9 -m pip \
		install \
		--prefix=/usr \
		--root=$(DESTDIR) \
		--no-warn-script-location \
		.
	mkdir -p $(DESTDIR)/usr/lib/python3.9/dist-packages
	cp -avn $(DESTDIR)/usr/lib/python3.9/site-packages/* $(DESTDIR)/usr/lib/python3.9/dist-packages
	rm -r $(DESTDIR)/usr/lib/python3.9/site-packages
	install -D -m 644 $(OSPD_OPENVAS)/config/ospd-openvas.conf $(DESTDIR)/etc/gvm/ospd-openvas.conf
	install -D -m 644 configs/usr/lib/systemd/system/ospd-openvas.service $(DESTDIR)/usr/lib/systemd/system/ospd-openvas.service

$(OSPD_OPENVAS_TAR):
	curl -f -L \
		https://github.com/greenbone/ospd-openvas/archive/refs/tags/v$(OSPD_OPENVAS_VERSION).tar.gz \
		-o $(OSPD_OPENVAS_TAR)

# ----------------------------- notus-scanner -----------------------------
NOTUS_SCANNER_VERSION = 22.5.0
NOTUS_SCANNER = notus-scanner-$(NOTUS_SCANNER_VERSION)
NOTUS_SCANNER_TAR = $(NOTUS_SCANNER).tar.gz
$(NOTUS_SCANNER_PY): $(NOTUS_SCANNER_TAR)
	tar -xf $(NOTUS_SCANNER_TAR)
	cd $(NOTUS_SCANNER) && python3.9 -m pip \
		install \
		--prefix=/usr \
		--root=$(DESTDIR) \
		--no-warn-script-location \
		.
	mkdir -p $(DESTDIR)/usr/lib/python3.9/dist-packages
	cp -avn $(DESTDIR)/usr/lib/python3.9/site-packages/* $(DESTDIR)/usr/lib/python3.9/dist-packages
	rm -r $(DESTDIR)/usr/lib/python3.9/site-packages
	install -D -m 644 configs/usr/lib/systemd/system/notus-scanner.service $(DESTDIR)/usr/lib/systemd/system/notus-scanner.service

$(NOTUS_SCANNER_TAR):
	curl -f -L \
		https://github.com/greenbone/notus-scanner/archive/refs/tags/v$(NOTUS_SCANNER_VERSION).tar.gz \
		-o $(NOTUS_SCANNER_TAR)

# ----------------------------- greenbone-feed-sync -----------------------------
$(GREENBONE_FEED_SYNC_PY):
	python3.9 -m pip \
		install \
		--prefix=/usr \
		--root=$(DESTDIR) \
		--no-warn-script-location \
		greenbone-feed-sync
	mkdir -p $(DESTDIR)/usr/lib/python3.9/dist-packages
	cp -avn $(DESTDIR)/usr/lib/python3.9/site-packages/* $(DESTDIR)/usr/lib/python3.9/dist-packages
	rm -r $(DESTDIR)/usr/lib/python3.9/site-packages

# ----------------------------- gvm-tools -----------------------------
$(GVM_TOOLS_PY):
	python3.9 -m pip \
		install \
		--prefix=/usr \
		--root=$(DESTDIR) \
		--no-warn-script-location \
		gvm-tools
	mkdir -p $(DESTDIR)/usr/lib/python3.9/dist-packages
	cp -avn $(DESTDIR)/usr/lib/python3.9/site-packages/* $(DESTDIR)/usr/lib/python3.9/dist-packages
	rm -r $(DESTDIR)/usr/lib/python3.9/site-packages
