#!/bin/bash

# Copyright (c) 2011  Zotero
#                     Center for History and New Media
#                     George Mason University, Fairfax, Virginia, USA
#                     http://zotero.org
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

BUILD_MAC=1
BUILD_WIN32=1
BUILD_LINUX=1

[ "`uname`" != "Darwin" ]
MAC_NATIVE=$?
[ "`uname -o 2> /dev/null`" != "Cygwin" ]
WIN_NATIVE=$?

MACWORD_URL=https://www.zotero.org/download/dev/Zotero-MacWord-Plugin-trunk.xpi
WINWORD_URL=https://www.zotero.org/download/dev/Zotero-WinWord-Plugin-trunk.xpi
OOO_URL=https://www.zotero.org/download/dev/Zotero-OpenOffice-Plugin-trunk.xpi

# Requires XULRunner runtime 2.0.*
MAC_RUNTIME_PATH="`pwd`/xulrunner/XUL.framework"
WIN32_RUNTIME_PATH="`pwd`/xulrunner/xulrunner_win32"
LINUX_i686_RUNTIME_PATH="`pwd`/xulrunner/xulrunner_linux-i686"
LINUX_x86_64_RUNTIME_PATH="`pwd`/xulrunner/xulrunner_linux-x86_64"

# Paths for Win32 installer build
MAKENSISU='C:\Program Files (x86)\NSIS\Unicode\makensis.exe'
UPX='C:\Program Files (x86)\upx\upx.exe'
EXE7ZIP='C:\Program Files\7-Zip\7z.exe'

DEFAULT_VERSION_PREFIX="3.0a1.SVN.r" # If version is not specified, version is this prefix followed by
                                   # the revision
VERSION_NUMERIC="3.0"

RAN=`uuidgen | head -c 8`  # Get random 8-character string for build directory
CALLDIR=`pwd`
BUILDDIR="/tmp/zotero-build-$RAN"
DISTDIR="$CALLDIR/dist"
STAGEDIR="$CALLDIR/staging"
SVNPREFIX="https://www.zotero.org/svn/extension/"
SVNPATH="$1" # e.g. branches/1.0, defaults to "trunk"
             # if this begins with /, a local build is made via symlinking
VERSION="$2" # Version to write to application.ini
UPDATE_CHANNEL="$3" # Usually "nightly", "beta", "release", or "default" (for custom builds)
REV="$4" # Revision normally supplied by SVN post-commit script (to speed things up) or left blank
BUILDID=`date +%Y%m%d`

mkdir "$BUILDDIR"
rm -rf "$STAGEDIR"
mkdir "$STAGEDIR"
rm -rf "$DISTDIR"
mkdir "$DISTDIR"

if [ -z "$SVNPATH" ]; then SVNPATH="trunk"; fi
if [ -z "$UPDATE_CHANNEL" ]; then UPDATE_CHANNEL="default"; fi

URL=${SVNPREFIX}${SVNPATH}/

# If revision not supplied, checkout and use svnversion to get latest revision
if [ ${SVNPATH:0:1} == "/" ]; then
	echo "Building Zotero from local directory"
	cp -R "$SVNPATH" "$BUILDDIR/zotero"
	cd "$BUILDDIR/zotero"
	if [ $? != 0 ]; then
		exit
	fi
	REV=`svnversion .`
	find . -depth -type d -name .svn -exec rm -rf {} \;
	
	# Windows can't actually symlink; copy instead, with a note
	if [ $WIN_NATIVE == 1 ]; then
		echo "Windows host detected; copying files instead of symlinking"
		
		# Copy branding
		cp -R "$CALLDIR/assets/branding" "$BUILDDIR/zotero/chrome/branding"
	else	
		# Symlink chrome dirs
		rm -rf "$BUILDDIR/zotero/chrome/"*
		for i in `ls $SVNPATH/chrome`; do
			ln -s "$SVNPATH/chrome/$i" "$BUILDDIR/zotero/chrome/$i"
		done
		
		# Symlink translators and styles
		rm -rf "$BUILDDIR/zotero/translators" "$BUILDDIR/zotero/styles"
		ln -s "$SVNPATH/translators" "$BUILDDIR/zotero/translators"
		ln -s "$SVNPATH/styles" "$BUILDDIR/zotero/styles"
		
		# Symlink branding
		ln -s "$CALLDIR/assets/branding" "$BUILDDIR/zotero/chrome/branding"
	fi
	
	# Add to chrome manifest
	echo "" >> "$BUILDDIR/zotero/chrome.manifest"
	cat "$CALLDIR/assets/chrome.manifest" >> "$BUILDDIR/zotero/chrome.manifest"
else
	if [ -z $REV ]; then
		echo "Getting latest Zotero revision"
		svn co --quiet --non-interactive "$URL" "$BUILDDIR/zotero"
		cd "$BUILDDIR/zotero"
		if [ $? != 0 ]; then
			exit
		fi
		REV=`svnversion .`
		cd ..
		echo "Got Zotero r$REV"
		rm -rf `find . -type d -name .svn`
	else
		# Export a clean copy of the tree
		echo "Checking out Zotero r$REV"
		svn export --quiet --non-interactive -r "$REV" "$URL" "$BUILDDIR/zotero"
	fi
	
	# Copy branding
	cp -r "$CALLDIR/assets/branding" "$BUILDDIR/zotero/chrome"
	
	# Zip chrome into JAR
	cd "$BUILDDIR/zotero/chrome"
	# Checkout failed -- bail
	if [ $? -eq 1 ]; then
		exit;
	fi
	zip -0 -r -q ../zotero.jar .
	rm -rf "$BUILDDIR/zotero/chrome/"*
	mv ../zotero.jar .
	cd ..
	
	# Build translators.zip
	echo "Retrieving translators"
	rm -rf translators
	git clone -q https://github.com/zotero/translators.git
	rm -rf translators/.git
	
	echo "Building translators.zip"
	cd translators
	mkdir output
	counter=0;
	for file in *.js; do
		newfile=$counter.js;
		id=`grep '"translatorID" *: *"' "$file" | perl -pe 's/.*"translatorID"\s*:\s*"(.*)".*/\1/'`
		label=`grep '"label" *: *"' "$file" | perl -pe 's/.*"label"\s*:\s*"(.*)".*/\1/'`
		mtime=`grep '"lastUpdated" *: *"' "$file" | perl -pe 's/.*"lastUpdated"\s*:\s*"(.*)".*/\1/'`
		echo $newfile,$id,$label,$mtime >> ../translators.index
		cp "$file" output/$newfile;
		counter=$(($counter+1))
	done;
	cd output
	zip -q ../../translators.zip *
	cd ../..
	
	# Build styles.zip with default styles
	if [ -d styles ]; then
		echo "Building styles.zip"
		
		cd styles
		for i in *.csl; do
			svn export --quiet --non-interactive https://www.zotero.org/svn/csl/$i;
		done
		zip -q ../styles.zip *
		cd ..
		rm -rf styles
	fi
	
	# Adjust chrome.manifest
	echo "" >> "$BUILDDIR/zotero/chrome.manifest"
	cat "$CALLDIR/assets/chrome.manifest" >> "$BUILDDIR/zotero/chrome.manifest"
	perl -pi -e 's/chrome\//jar:chrome\/zotero.jar\!\//g' "$BUILDDIR/zotero/chrome.manifest"
fi

if [ -z $VERSION ]; then
	VERSION="$DEFAULT_VERSION_PREFIX$REV"
fi

# Adjust connector pref
perl -pi -e 's/pref\("extensions\.zotero\.httpServer\.enabled", false\);/pref("extensions.zotero.httpServer.enabled", true);/g' "$BUILDDIR/zotero/defaults/preferences/zotero.js"
perl -pi -e 's/pref\("extensions\.zotero\.connector\.enabled", false\);/pref("extensions.zotero.connector.enabled", true);/g' "$BUILDDIR/zotero/defaults/preferences/zotero.js"

# Copy icons
cp -r "$CALLDIR/assets/icons" "$BUILDDIR/zotero/chrome/icons"

# Copy application.ini and modify
cp "$CALLDIR/assets/application.ini" "$BUILDDIR/application.ini"
perl -pi -e "s/{{VERSION}}/$VERSION/" "$BUILDDIR/application.ini"
perl -pi -e "s/{{BUILDID}}/$BUILDID/" "$BUILDDIR/application.ini"

# Copy prefs.js and modify
cp "$CALLDIR/assets/prefs.js" "$BUILDDIR/zotero/defaults/preferences"
perl -pi -e 's/pref\("app\.update\.channel", "[^"]*"\);/pref\("app\.update\.channel", "'"$UPDATE_CHANNEL"'");/' "$BUILDDIR/zotero/defaults/preferences/prefs.js"

# Delete .DS_Store and .svn
find "$BUILDDIR" -depth -type d -name .svn -exec rm -rf {} \;
find "$BUILDDIR" -name .DS_Store -exec rm -f {} \;

echo "Retrieving Zotero OpenOffice.org Integration"
curl -4s "$OOO_URL" -o "$BUILDDIR/ooo.zip"

cd "$CALLDIR"

# Mac
if [ $BUILD_MAC == 1 ]; then
	echo "Retrieving Zotero MacWord Integration"
	curl -4s "$MACWORD_URL" -o "$BUILDDIR/macword.zip"
	
	echo 'Building Zotero.app'
		
	# Set up directory structure
	APPDIR="$STAGEDIR/Zotero.app"
	rm -rf "$APPDIR"
	mkdir "$APPDIR"
	chmod 755 "$APPDIR"
	cp -r "$CALLDIR/mac/Contents" "$APPDIR"
	CONTENTSDIR="$APPDIR/Contents"
	find "$CONTENTSDIR" -depth -type d -name .svn -exec rm -rf {} \;
	find "$CONTENTSDIR" -name .DS_Store -exec rm -f {} \;
	
	# Merge xulrunner and relevant assets
	mkdir "$CONTENTSDIR/MacOS"
	mkdir "$CONTENTSDIR/Frameworks"
	cp -a "$MAC_RUNTIME_PATH" "$CONTENTSDIR/Frameworks/XUL.framework"
	rm "$CONTENTSDIR/Frameworks/XUL.framework/Versions/Current"
	mv "$CONTENTSDIR/Frameworks/XUL.framework/Versions/"[1-9]* "$CONTENTSDIR/Frameworks/XUL.framework/Versions/Current"
	cp "$CONTENTSDIR/Frameworks/XUL.framework/Versions/Current/xulrunner" "$CONTENTSDIR/MacOS/zotero"
	cp "$BUILDDIR/application.ini" "$CONTENTSDIR/Resources"
	cp "$CALLDIR/mac/Contents/Info.plist" "$CONTENTSDIR"
	
	# Modify Info.plist
	cp "$CALLDIR/mac/Contents/Info.plist" "$CONTENTSDIR/Info.plist"
	perl -pi -e "s/{{VERSION}}/$VERSION/" "$CONTENTSDIR/Info.plist"
	perl -pi -e "s/{{VERSION_NUMERIC}}/$VERSION_NUMERIC/" "$CONTENTSDIR/Info.plist"
	# Needed for "monkeypatch" Windows builds: 
	# http://www.nntp.perl.org/group/perl.perl5.porters/2010/08/msg162834.html
	rm -f "$CONTENTSDIR/Info.plist.bak"
	
	# Add components
	cp -R "$BUILDDIR/zotero/"* "$CONTENTSDIR/Resources"
	
	# Add word processor plug-ins
	mkdir "$CONTENTSDIR/Resources/extensions"
	unzip -q "$CALLDIR/mac/pythonext-Darwin_universal.xpi" -d "$CONTENTSDIR/Resources/extensions/pythonext@mozdev.org"
	unzip -q "$BUILDDIR/macword.zip" -d "$CONTENTSDIR/Resources/extensions/zoteroMacWordIntegration@zotero.org"
	unzip -q "$BUILDDIR/ooo.zip" -d "$CONTENTSDIR/Resources/extensions/zoteroOpenOfficeIntegration@zotero.org"
	
	# Build disk image
	if [ $MAC_NATIVE == 1 ]; then
		echo 'Creating Mac installer'
		"$CALLDIR/mac/pkg-dmg" --source "$STAGEDIR/Zotero.app" --target "$DISTDIR/Zotero.dmg" \
			--sourcefile --volname Zotero --copy "$CALLDIR/mac/DSStore:/.DS_Store" \
			--symlink /Applications:"/Drag Here to Install" > /dev/null
	else
		echo 'Not building on Mac; creating Mac distribution as a zip file'
		rm -f "$DISTDIR/Zotero_mac.zip"
		cd "$STAGEDIR" && zip -rqX "$DISTDIR/Zotero_mac.zip" Zotero.app
	fi
fi

# Win32
if [ $BUILD_WIN32 == 1 ]; then
	
	echo "Retrieving Zotero WinWord Integration"
	curl -4s "$WINWORD_URL" -o "$BUILDDIR/winword.zip"
	
	echo 'Building Zotero_win32'
	
	# Set up directory
	WINSTAGEDIR="$STAGEDIR/Zotero_win32"
	APPDIR="$WINSTAGEDIR/core"
	rm -rf "$STAGEDIR/Zotero_win32"
	mkdir -p "$APPDIR"
	
	# Merge xulrunner and relevant assets
	cp -R "$BUILDDIR/zotero/"* "$BUILDDIR/application.ini" "$APPDIR"
	cp -r "$WIN32_RUNTIME_PATH" "$APPDIR/xulrunner"
	mv "$APPDIR/xulrunner/xulrunner-stub.exe" "$APPDIR/zotero.exe"
	cp "$APPDIR/xulrunner/mozcrt19.dll" "$APPDIR/mozcrt19.dll"
	
	# Add word processor plug-ins
	mkdir "$APPDIR/extensions"
	unzip -q "$BUILDDIR/ooo.zip" -d "$APPDIR/extensions/zoteroOpenOfficeIntegration@zotero.org"
	unzip -q "$BUILDDIR/winword.zip" -d "$APPDIR/extensions/zoteroWinWordIntegration@zotero.org"
	
	if [ $WIN_NATIVE == 1 ]; then
		# Add icon to xulrunner-stub
		"$CALLDIR/win/ReplaceVistaIcon/ReplaceVistaIcon.exe" "`cygpath -w \"$APPDIR/zotero.exe\"`" \
			"`cygpath -w \"$CALLDIR/assets/icons/default/main-window.ico\"`"
		
		echo 'Creating Windows installer'
		# Copy installer files
		cp -r "$CALLDIR/win/installer" "$BUILDDIR/win_installer"
		
		# Build uninstaller
		"`cygpath -u \"$MAKENSISU\"`" /V1 "`cygpath -w \"$BUILDDIR/win_installer/uninstaller.nsi\"`"
		mkdir "$APPDIR/uninstall"
		mv "$BUILDDIR/win_installer/helper.exe" "$APPDIR/uninstall"
		
		# Build setup.exe
		perl -pi -e "s/{{VERSION}}/$VERSION/" "$BUILDDIR/win_installer/defines.nsi"
		"`cygpath -u \"$MAKENSISU\"`" /V1 "`cygpath -w \"$BUILDDIR/win_installer/installer.nsi\"`"
		mv "$BUILDDIR/win_installer/setup.exe" "$WINSTAGEDIR"
		
		# Compress application
		cd "$WINSTAGEDIR" && "`cygpath -u \"$EXE7ZIP\"`" a -r -t7z "`cygpath -w \"$BUILDDIR/app_win32.7z\"`" \
			-mx -m0=BCJ2 -m1=LZMA:d24 -m2=LZMA:d19 -m3=LZMA:d19  -mb0:1 -mb0s1:2 -mb0s2:3 > /dev/null
			
		# Compress 7zSD.sfx
		"`cygpath -u \"$UPX\"`" --best -o "`cygpath -w \"$BUILDDIR/7zSD.sfx\"`" \
			"`cygpath -w \"$CALLDIR/win/installer/7zstub/firefox/7zSD.sfx\"`" > /dev/null
		
		# Combine 7zSD.sfx and app.tag into setup.exe
		cat "$BUILDDIR/7zSD.sfx" "$CALLDIR/win/installer/app.tag" \
			"$BUILDDIR/app_win32.7z" > "$DISTDIR/Zotero_setup.exe"
		chmod 755 "$DISTDIR/Zotero_setup.exe"
	else
		echo 'Not building on Windows; creating Windows distribution as a zip file'
		rm -f $DISTDIR/Zotero_win32.zip
		mv "$WINSTAGEDIR/core" "$WINSTAGEDIR/zotero"
		cd "$WINSTAGEDIR" && zip -rqX "$DISTDIR/Zotero_win32.zip" "zotero"
	fi
fi

# Linux
if [ $BUILD_LINUX == 1 ]; then
	for arch in "i686" "x86_64"; do
		RUNTIME_PATH=`eval echo '$LINUX_'$arch'_RUNTIME_PATH'`
		
		# Set up directory
		echo 'Building Zotero_linux-'$arch
		APPDIR="$STAGEDIR/Zotero_linux-$arch"
		rm -rf "$APPDIR"
		mkdir "$APPDIR"
		
		# Merge xulrunner and relevant assets
		cp -R "$BUILDDIR/zotero/"* "$BUILDDIR/application.ini" "$APPDIR"
		cp -r "$RUNTIME_PATH" "$APPDIR/xulrunner"
		mv "$APPDIR/xulrunner/xulrunner-stub" "$APPDIR/zotero"
		chmod 755 "$APPDIR/zotero"
		
		# Add word processor plug-ins
		mkdir "$APPDIR/extensions"
		unzip -q "$BUILDDIR/ooo.zip" -d "$APPDIR/extensions/zoteroOpenOfficeIntegration@zotero.org"
		
		# Add run-zotero.sh
		cp "$CALLDIR/linux/run-zotero.sh" "$APPDIR/run-zotero.sh"
		
		# Create tar
		rm -f "$DISTDIR/Zotero_linux-$arch.tar.bz2"
		cd "$STAGEDIR"
		tar -cjf "$DISTDIR/Zotero_linux-$arch.tar.bz2" "Zotero_linux-$arch"
	done
fi

rm -rf $BUILDDIR