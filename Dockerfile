FROM balenalib/fincm3-debian:stretch as base

ENV DEBIAN_FRONTEND noninteractive
ENV TERM xterm

COPY src/01_nodoc /etc/dpkg/dpkg.cfg.d/
COPY src/01_buildconfig /etc/apt/apt.conf.d/

RUN apt-get update \
	&& apt-get dist-upgrade \
	&& apt-get install \
		apt-transport-https \
		build-essential \
		ca-certificates \
		curl \
		dirmngr \
		dbus \
		git \
		gnupg \
		htop \
		init \
		iptables \
		iptraf-ng \
		less \
		libpq-dev \
		libnss-mdns \
		libsqlite3-dev \
		jq \
		nano \
		netcat \
		net-tools \
		ifupdown \
		openssh-client \
		openssh-server \
		openvpn \
		python \
		python-dev \
		rsyslog \
		rsyslog-gnutls \
		strace \
		systemd \
		vim \
		wget \
	&& rm -rf /var/lib/apt/lists/*

ENV GO_VERSION 1.10.5

RUN mkdir -p /usr/local/go \
	&& curl -SLO "http://resin-packages.s3.amazonaws.com/golang/v$GO_VERSION/go$GO_VERSION.linux-armv7hf.tar.gz" \
	&& echo "b6fe44574959e8160e456623607fa682db2bdcc0d1e59f57c7000fee9455f7b5  go$GO_VERSION.linux-armv7hf.tar.gz" | sha256sum -c - \
	&& tar -xzf "go$GO_VERSION.linux-armv7hf.tar.gz" -C /usr/local/go --strip-components=1 \
	&& rm -f go$GO_VERSION.linux-armv7hf.tar.gz

ENV GOROOT /usr/local/go
ENV GOPATH /go
ENV PATH $GOPATH/bin:/usr/local/go/bin:$PATH

RUN mkdir -p "$GOPATH/src" "$GOPATH/bin" && chmod -R 777 "$GOPATH"

ENV NODE_VERSION 10.14.1
ENV NPM_VERSION 6.4.1
RUN curl -SL "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-linux-armv7l.tar.gz" | tar xz -C /usr/local --strip-components=1 \
	&& npm config set unsafe-perm true \
	&& npm install -g npm@"$NPM_VERSION" \
	&& npm cache clear --force \
	&& rm -rf /tmp/*

# We have to build confd as there's no armhf build but we don't want
# all this extra source in the final container
FROM base as confd

ENV CONFD_VERSION 0.15.0

RUN git clone https://github.com/kelseyhightower/confd.git $GOPATH/src/github.com/kelseyhightower/confd \
	&& cd $GOPATH/src/github.com/kelseyhightower/confd \
	&& make && make install \
	&& chmod a+x /usr/local/bin/confd \
	&& ln -s /usr/src/app/config/confd /etc/confd

# Final base container
FROM base as main

# Copy confd
COPY --from=confd /usr/local/bin/confd /usr/local/bin/confd

RUN mkdir -p /usr/src/app
WORKDIR /usr/src/app

# Remove default nproc limit for Avahi for it to work in-container
RUN sed -i "s/rlimit-nproc=3//" /etc/avahi/avahi-daemon.conf

# systemd configuration
ENV container lxc

# We never want these to run in a container
RUN systemctl mask \
	dev-hugepages.mount \
	dev-mqueue.mount \
	sys-fs-fuse-connections.mount \
	sys-kernel-config.mount \
	sys-kernel-debug.mount \
	display-manager.service \
	getty@.service \
	systemd-logind.service \
	systemd-remount-fs.service \
	getty.target \
	graphical.target

RUN systemctl disable ssh.service

COPY src/confd.service /etc/systemd/system/
COPY src/balena-root-ca.service /etc/systemd/system/
COPY src/configure-balena-root-ca.sh /usr/sbin/
COPY src/balena-host-envvars.service /etc/systemd/system/
COPY src/configure-balena-host-envvars.sh /usr/sbin/
COPY src/journald.conf /etc/systemd/
COPY src/rsyslog.conf /etc/
COPY src/dbus-no-oom-adjust.conf /etc/systemd/system/dbus.service.d/dbus-no-oom-adjust.conf
COPY src/nsswitch.conf /etc/nsswitch.conf
COPY src/entry.sh /usr/bin/entry.sh

VOLUME ["/sys/fs/cgroup"]
VOLUME ["/run"]
VOLUME ["/run/lock"]

CMD ["/usr/bin/entry.sh"]
