# Copyright 1999-2010 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Header: /var/cvsroot/gentoo-x86/games-roguelike/nethack/nethack-3.4.3-r1.ebuild,v 1.27 2010/03/02 21:10:39 mr_bones_ Exp $

EAPI=2
inherit eutils toolchain-funcs flag-o-matic games

MY_PV=${PV//.}
DESCRIPTION="The ultimate old-school single player dungeon exploration game"
HOMEPAGE="http://www.nethack.org/"
SRC_URI="mirror://sourceforge/nethack/${PN}-${MY_PV}-src.tgz"

LICENSE="nethack"
SLOT="0"
KEYWORDS="amd64 hppa ppc sparc x86 ~x86-fbsd"
IUSE="X unicode menucolor paranoid easywizard"

RDEPEND=">=sys-libs/ncurses-5.2-r5
	X? (
		x11-libs/libXaw
		x11-libs/libXpm
		x11-libs/libXt
	)"
DEPEND="${RDEPEND}
	X? (
		x11-proto/xproto
		x11-apps/bdftopcf
		x11-apps/mkfontdir
	)"

HACKDIR=${GAMES_DATADIR}/${PN}

src_prepare() {
	# This copies the /sys/unix Makefile.*s to their correct places for
	# seding and compiling.
	cd "sys/unix"
	source setup.sh || die

	cd ../..
	epatch \
		"${FILESDIR}"/${PV}-gentoo-paths.patch \
		"${FILESDIR}"/${PV}-default-options.patch \
		"${FILESDIR}"/${PV}-bison.patch \
		"${FILESDIR}"/${PV}-macos.patch \
		"${FILESDIR}"/${P}-gibc210.patch \
		"${FILESDIR}"/${P}-recover.patch

	mv doc/recover.6 doc/nethack-recover.6

	sed -i \
		-e "s:GENTOO_STATEDIR:${EPREFIX}${GAMES_STATEDIR}/${PN}:" include/unixconf.h \
		|| die "setting statedir"
	sed -i \
		-e "s:GENTOO_HACKDIR:${EPREFIX}${HACKDIR}:" include/config.h \
		|| die "setting hackdir"
	# set the default pager from the environment bug #52122
	if [[ -n "${PAGER}" ]] ; then
		sed -i \
			-e "115c\#define DEF_PAGER \"${PAGER}\"" \
			include/unixconf.h \
			|| die "setting statedir"
		# bug #57410
		sed -i \
			-e "s/^DATNODLB =/DATNODLB = \$(DATHELP)/" Makefile \
			|| die "sed Makefile failed"
	fi

	if use X ; then
		epatch "${FILESDIR}/${PV}-X-support.patch"
	fi

	if use unicode; then
		epatch "${FILESDIR}/${P}-unicode.patch"
	fi

	if use menucolor; then
		OS=`uname -o`
		if [[ ! ${OS#GNU} != ${OS} ]] ; then
			# uncomment "# define MENU_COLOR_REGEX_POSIX"
			einfo "Assuming ${OS} is POSIX-compliant ..."
			epatch "${FILESDIR}/${P}-menucolor.patch"
			sed -i \
				-e "s/\/\*\(# define MENU_COLOR_REGEX_POSIX\) \*\//\1/" \
				include/config.h \
				|| die "setting menu_color_regex_posix"
		else
			epatch "${FILESDIR}/${P}-menucolor.patch"
		fi
	fi

	if use paranoid; then
		epatch "${FILESDIR}/${P}-paranoid.patch"
	fi

	if use easywizard; then
		epatch "${FILESDIR}/${P}-easywizard.patch"
	fi
}

src_compile() {
	local lflags="-L/usr/X11R6/lib"

	cd "${S}"/src
	append-flags -I../include

	emake \
		CC="$(tc-getCC)" \
		CFLAGS="${CFLAGS}" \
		LFLAGS="${lflags}" \
		../util/makedefs \
		|| die "initial makedefs build failed"
	emake \
		CC="$(tc-getCC)" \
		CFLAGS="${CFLAGS}" \
		LFLAGS="${lflags}" \
		|| die "main build failed"
	cd "${S}"/util
	emake CC="$(tc-getCC)" CFLAGS="${CFLAGS}" recover || die "util build failed"
}

src_install() {
	emake \
		CC="$(tc-getCC)" \
		CFLAGS="${CFLAGS}" \
		LFLAGS="-L/usr/X11R6/lib" \
		GAMEPERM=0755 \
		GAMEUID="${GAMES_USER}" GAMEGRP="${GAMES_GROUP}" \
		PREFIX="${ED}/usr" \
		GAMEDIR="${ED}${HACKDIR}" \
		SHELLDIR="${ED}/${GAMES_BINDIR}" \
		install \
		|| die "emake install failed"

	# We keep this stuff in ${GAMES_STATEDIR} instead so tidy up.
	rm -rf "${ED}/usr/share/games/nethack/save"

	newgamesbin util/recover recover-nethack || die "newgamesbin failed"

	# The final nethack is a sh script.  This fixes the hard-coded
	# HACKDIR directory so it doesn't point to ${ED}/usr/share/nethackdir
	sed -i \
		-e "s:^\(HACKDIR=\).*:\1${EPREFIX}${HACKDIR}:" \
		"${ED}${GAMES_BINDIR}/nethack" \
		|| die "sed ${GAMES_BINDIR}/nethack failed"

	doman doc/*.6
	dodoc doc/*.txt

	# Can be copied to ~/.nethackrc to set options
	# Add this to /etc/.skel as well, thats the place for default configs
	insinto "${HACKDIR}"
	doins "${FILESDIR}/dot.nethackrc"

	local windowtypes="tty"
	use X && windowtypes="${windowtypes} x11"
	set -- ${windowtypes}
	sed -i \
		-e "s:GENTOO_WINDOWTYPES:${windowtypes}:" \
		-e "s:GENTOO_DEFWINDOWTYPE:$1:" \
		"${ED}${HACKDIR}/dot.nethackrc" \
		|| die "sed ${HACKDIR}/dot.nethackrc failed"
	insinto /etc/skel
	newins "${ED}/${HACKDIR}/dot.nethackrc" .nethackrc

	if use X ; then
		# install nethack fonts
		cd "${S}/win/X11"
		bdftopcf -o nh10.pcf nh10.bdf || die "Converting fonts failed"
		bdftopcf -o ibm.pcf ibm.bdf || die "Converting fonts failed"
		insinto "${HACKDIR}/fonts"
		doins *.pcf
		cd "${ED}/${HACKDIR}/fonts"
		mkfontdir || die "The action mkfontdir ${HACKDIR}/fonts failed"

		# copy nethack x application defaults
		cd "${S}/win/X11"
		insinto /etc/X11/app-defaults
		newins NetHack.ad NetHack || die "Failed to install NetHack X app defaults"
		sed -i \
			-e 's:^!\(NetHack.tile_file.*\):\1:' \
			"${ED}/etc/X11/app-defaults/NetHack" \
			|| die "sed /etc/X11/app-defaults/NetHack failed"
	fi

	local statedir="${GAMES_STATEDIR}/${PN}"
	keepdir "${statedir}/save"
	mv "${ED}/${HACKDIR}/"{record,logfile,perm} "${ED}/${statedir}/"
	make_desktop_entry nethack "Nethack"

	prepgamesdirs
	chmod -R 660 "${ED}/${statedir}"
	chmod 770 "${ED}/${statedir}" "${ED}/${statedir}/save"
}

pkg_postinst() {
	games_pkg_postinst
	if use menucolor; then
		elog "USE flag 'menucolor' enabled. You can"
		elog "    cat \"OPTIONS=menucolors\" >> ~/.nethackrc"
		elog "to enable this feature."
	fi
	elog "You may want to look at /etc/skel/.nethackrc for interesting options"
}
