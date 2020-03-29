# BASE_PATH is folder where you want to store code.
BASE_PATH=$(cd `dirname $0`; pwd)
# enter folder
cd $BASE_PATH
# Setup a folder path to contain source code.
BUILD_PATH=$BASE_PATH/"build_framework"
# Check folder exist or not to create new.
if [ ! -d $BUILD_PATH ]
then
	mkdir $BUILD_PATH
fi
# Enter build folder
cd $BUILD_PATH

# directories
# Newest version or particular version be selected.
FF_VERSION="4.2.2"
if [[ $FFMPEG_VERSION != "" ]]; then
  FF_VERSION=$FFMPEG_VERSION
fi
SOURCE="ffmpeg-$FF_VERSION"
# Folder name to contain the output framework
FAT="FFmpeg-iOS"
SCRATCH="scratch"
# must be an absolute path
THIN=`pwd`/"thin"
# absolute path to x264 library
# X264=`pwd`/fat-x264
#FDK_AAC=`pwd`/../fdk-aac-build-script-for-iOS/fdk-aac-ios
# You can change confige depends on your target
CONFIGURE_FLAGS="--enable-cross-compile --disable-debug --disable-programs \
                 --disable-doc --enable-pic \
				 --disable-filters --disable-devices \
				 --disable-postproc \
				 --disable-ffmpeg --disable-ffplay --disable-ffprobe"

if [ "$X264" ]
then
	CONFIGURE_FLAGS="$CONFIGURE_FLAGS --enable-gpl --enable-libx264"
fi
if [ "$FDK_AAC" ]
then
	CONFIGURE_FLAGS="$CONFIGURE_FLAGS --enable-libfdk-aac --enable-nonfree"
fi
# avresample
#CONFIGURE_FLAGS="$CONFIGURE_FLAGS --enable-avresample"
# Set architect be supported to export.
#i386 - simulator 32 bits
#x86_64 - simulator 64 bits
ARCHS="arm64 armv7 x86_64 i386"
COMPILE="y"
LIPO="y"
# Min OS version be supported
DEPLOYMENT_TARGET="9.0"
if [ "$*" ]
then
	if [ "$*" = "lipo" ]
	then
		# skip compile
		COMPILE=
	else
		ARCHS="$*"
		if [ $# -eq 1 ]
		then
			# skip lipo
			LIPO=
		fi
	fi
fi
# Check gas-preprocessor available or not to download.
if [ "$COMPILE" ]
then
	if [ ! `which yasm` ]
	then
		echo 'Yasm not found'
		if [ ! `which brew` ]
		then
			echo 'Homebrew not found. Trying to install...'
                        ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)" \
				|| exit 1
		fi
		echo 'Trying to install Yasm...'
		brew install yasm || exit 1
	fi
	if [ ! `which gas-preprocessor.pl` ]
	then
		echo 'gas-preprocessor.pl not found. Trying to install...'
		(curl -L https://raw.githubusercontent.com/mansr/gas-preprocessor/master/gas-preprocessor.pl \
			-o /usr/local/bin/gas-preprocessor.pl \
			&& chmod +x /usr/local/bin/gas-preprocessor.pl) \
			|| exit 1
	fi
# Check FFMPEG source code available or not to download.
	if [ ! -r $SOURCE ]
	then
		echo 'FFmpeg source not found. Trying to download...'
		curl http://www.ffmpeg.org/releases/$SOURCE.tar.bz2 | tar xj \
			|| exit 1
	fi
# Lets process to export FFMPEG code to iOS code within specific architect be selected above.
	CWD=`pwd`
	for ARCH in $ARCHS
	do
		echo "building $ARCH..."
		mkdir -p "$SCRATCH/$ARCH"
		cd "$SCRATCH/$ARCH"

		CFLAGS="-arch $ARCH"
		if [ "$ARCH" = "i386" -o "$ARCH" = "x86_64" ]
		then
		    PLATFORM="iPhoneSimulator"
		    CFLAGS="$CFLAGS -mios-simulator-version-min=$DEPLOYMENT_TARGET"
		else
		    PLATFORM="iPhoneOS"
		    CFLAGS="$CFLAGS -mios-version-min=$DEPLOYMENT_TARGET -fembed-bitcode"
		    if [ "$ARCH" = "arm64" ]
		    then
		        EXPORT="GASPP_FIX_XCODE5=1"
		    fi
		fi

		XCRUN_SDK=`echo $PLATFORM | tr '[:upper:]' '[:lower:]'`
		CC="xcrun -sdk $XCRUN_SDK clang"

		# force "configure" to use "gas-preprocessor.pl" (FFmpeg 3.3)
		if [ "$ARCH" = "arm64" ]
		then
		    AS="gas-preprocessor.pl -arch aarch64 -- $CC"
		else
		    AS="gas-preprocessor.pl -- $CC"
		fi

		CXXFLAGS="$CFLAGS"
		LDFLAGS="$CFLAGS"
		if [ "$X264" ]
		then
			CFLAGS="$CFLAGS -I$X264/include"
			LDFLAGS="$LDFLAGS -L$X264/lib"
		fi
		if [ "$FDK_AAC" ]
		then
			CFLAGS="$CFLAGS -I$FDK_AAC/include"
			LDFLAGS="$LDFLAGS -L$FDK_AAC/lib"
		fi

		TMPDIR=${TMPDIR/%\/} $CWD/$SOURCE/configure \
		    --target-os=darwin \
		    --arch=$ARCH \
		    --cc="$CC" \
		    --as="$AS" \
		    $CONFIGURE_FLAGS \
		    --extra-cflags="$CFLAGS" \
		    --extra-ldflags="$LDFLAGS" \
		    --prefix="$THIN/$ARCH" \
		|| exit 1

		make -j3 install $EXPORT || exit 1
		cd $CWD
	done
fi
# Combile architects to fat binaries .a
if [ "$LIPO" ]
then
	echo "building fat binaries..."
	mkdir -p $FAT/lib
	set - $ARCHS
	CWD=`pwd`
	cd $THIN/$1/lib
	for LIB in *.a
	do
		cd $CWD
		echo lipo -create `find $THIN -name $LIB` -output $FAT/lib/$LIB 1>&2
		lipo -create `find $THIN -name $LIB` -output $FAT/lib/$LIB || exit 1
	done

	cd $CWD
	cp -rf $THIN/$1/include $FAT
fi

# Copy avc.h file
cd $BUILD_PATH
cp -rf $SOURCE/"libavformat/avc.h" $FAT/"include/libavformat"
#  Remove time header file because it override system file, it doesn't need in iOS.
rm -r $FAT/"include/libavutil/time.h"
# Copy FFmpeg-iOS folder to destination folder
cd $BASE_PATH
cp -rf "$BUILD_PATH/FFmpeg-iOS" "$BASE_PATH/TKLiveFramework"
# Finish processing
echo Done
