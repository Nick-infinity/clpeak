#!/bin/bash
## Directory Info
BASE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
PROJECT_DIR=$(realpath ${BASE_DIR}/../../)

if [ -n "$BUILD_BASE" ]; then
    BUILD_DIR=$(realpath ${BUILD_BASE})
else
    BUILD_DIR=$PROJECT_DIR/build
fi

## CMake Default Args
CMAKE_BUILD_ARCH="arm64-v8a"
CMAKE_BUILD_TYPE="Release"
NUM_JOBS=8
DEBUG=false
BUILD_TARGET=""

echo "PROJECT_DIR: $PROJECT_DIR"
echo "BUILD_DIR: $BUILD_DIR"

function add_cmake_arg() {
    if [[ -z "$CMAKE_ARGS" ]]
    then
        CMAKE_ARGS="$1"
    else
        CMAKE_ARGS="$CMAKE_ARGS \\
      $1"
    fi
}

## Android Default Args
NDK_DIR=""
ANDROID_NATIVE_API_LEVEL="android-28"
ANDROID_TOOLCHAIN_NAME="clang"
ANDROID_STL="c++_static"

function usage () {
    echo "<Usage> build.sh <command> <arguments>

        <command>           <argument>                  <description>

        --ccache                                        Compile use ccache (Default: Compile without ccache)
        --clean(-c)                                     Clean the project
        --clean_build(-cb)                              Clean and build the project
        --clang                                         Enable Clang build
        --asan                                          Build with AddressSanitizer
        --debug(-d)                                     Build with debug mode
        --ndk(-n)                                       ndk dir (Default: /opt/cmdline-tools/ndk/25.2.9519653/)
        --architecture(-a)  Unix/arm64-v8a/armeabi-v7a  Build architecture (Default: Unix)
        -j                  number of jobs              Number of job instances to be run in parallel (Default : 1)
        "
}

function clean () {
    rm -rf $BUILD_DIR
    rm -rf $PROJECT_DIR/ir
}

function check_cmake_version () {
    current_ver="@(cmake --version | head -n1 | awk {'print $3'})"
    required_ver="3.16"

    if [ "$(printf '%s\n' "$required_ver" "$current_ver" | sort -V | head -n1)" != "$required_ver" ]
    then
          echo "It need to use Cmake version to ${required_ver}"
	  exit 1
    fi
}

function build() {
    # build
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    echo "cmake ${CMAKE_ARGS} ${PROJECT_DIR}"
      cmake ${CMAKE_ARGS} ${PROJECT_DIR}
    echo "make -j $NUM_JOBS"
    make $BUILD_TARGET -j $NUM_JOBS

    EXIT_STATUS=$?
    if [[ $EXIT_STATUS == 0 ]]
    then
        echo "Build files generated at $(realpath $BUILD_DIR)"
    fi
    exit $EXIT_STATUS
}

CLANG_BUILD=false
CLEAN=false
BUILD=true
ASAN=false
DEBUG=false
CCACHE=false
# command-line option check
for (( i=1; i<=$#; i++))
do
    case "${!i}" in
        "--ccache")
            echo "CCACHE IS USED"
            CCACHE=true
            ;;
        "--clean"|"-c")
            echo "Clean"
            CLEAN=true
            BUILD=false
            ;;
        "--clean_build"|"-cb")
            echo "Clean Build"
            CLEAN=true
            ;;
        "--clang")
            CLANG_BUILD=true
            ;;
        "--asan")
            echo "ASAN build"
            ASAN=true
            ;;
        "--debug"|"-d")
            echo "Debug "
            DEBUG=true
            ;;
        "--ndk"|"-n")
            let "i++"
            NDK_DIR="${!i}"
            ;;
        "-j")
            let "i++"
            if [[ $(echo "${!i}" | grep -qE '^[0-9]+$'; echo $?) -ne "0" ]]
            then
                echo "Enter number of threads to use"
                usage
                exit 1
            else
                NUM_JOBS="${!i}"
            fi
            ;;
        "--architecture"|"-a")
            let "i++"
            CMAKE_BUILD_ARCH="${!i}"
            ;;
        *)
            echo "Unknown option: ${!i}"
            usage
            exit 1
            ;;
    esac
done


if [[ "$CCACHE" == "true" ]]
then
    add_cmake_arg "-DCCACHE=TRUE"
fi

if [[ "$CMAKE_BUILD_ARCH" == "Unix" ]]
then
    if [[ $CLANG_BUILD == true ]]
    then
        add_cmake_arg "-DCMAKE_C_COMPILER=clang"
        add_cmake_arg "-DCMAKE_CXX_COMPILER=clang++"
    else
        HIGHEST_COMPILER_VERSION=0

        # Search for highest compiler version available
        C_COMPILER="gcc"
        CXX_COMPILER="g++"
        MINIMUM_COMPILER_VERSION=7.0.0

        PATHS=$(echo $PATH | sed 's/:/ /g')
        AVAILABLE_COMPILER="$CXX_COMPILER"
        for SEARCH_PATH in $PATHS
        do
            COMPILER_CANDIDATE=$(find $SEARCH_PATH -maxdepth 1 -name "$CXX_COMPILER-*" 2> /dev/null)
            if [[ "$COMPILER_CANDIDATE" != "" ]]
            then
                AVAILABLE_COMPILER="$AVAILABLE_COMPILER $COMPILER_CANDIDATE"
            fi
        done

        for CANDIDATE in $AVAILABLE_COMPILER
        do
            CANDIDATE_VERSION=$(echo $($CANDIDATE --version 2>/dev/null | cut -d' ' -f3)| cut -d- -f1)
            if [[ "$HIGHEST_COMPILER_VERSION" = "`echo -e \"$HIGHEST_COMPILER_VERSION\n$CANDIDATE_VERSION\" | sort -V | head -n1`" ]]
            then
                HIGHEST_COMPILER_VERSION=$CANDIDATE_VERSION
                CXX_COMPILER=$(basename $CANDIDATE)
            fi
        done

        # Check if found highest compiler version meets minimum requirement
        if [[ ! "$HIGHEST_COMPILER_VERSION" = "$MINIMUM_COMPILER_VERSION" ]] && [[ "$HIGHEST_COMPILER_VERSION" = "`echo -e \"$HIGHEST_COMPILER_VERSION\n$MINIMUM_COMPILER_VERSION\" | sort -V | head -n1`" ]]
        then
            echo "Minimum required compiler version is $MINIMUM_COMPILER_VERSION for $CXX_COMPILER"
            echo "You have only $HIGHEST_COMPILER_VERSION"
            exit 1
        fi

        if echo $CXX_COMPILER | grep -q -- '-[0-9.]\+$'; then
            C_COMPILER=$C_COMPILER-$(echo $CXX_COMPILER | cut -d- -f2)
        fi
        C_COMPILER_VERSION=$(echo $($C_COMPILER --version | cut -d' ' -f3) | cut -d- -f1)

        if [[ $C_COMPILER_VERSION != $HIGHEST_COMPILER_VERSION ]]
        then
            echo "C compiler version and CXX compiler version does not match!"
            echo "Please check your system environment"
            echo "C   compiler version : $C_COMPILER_VERSION"
            echo "CXX compiler version : $HIGHEST_COMPILER_VERSION"
            exit 1
        fi

        add_cmake_arg "-DCMAKE_C_COMPILER=$C_COMPILER"
        add_cmake_arg "-DCMAKE_CXX_COMPILER=$CXX_COMPILER"
    fi

elif [[ "$CMAKE_BUILD_ARCH" == "arm64-v8a" ]] || [[ "$CMAKE_BUILD_ARCH" == "armeabi-v7a" ]]
then
    if [[ -z ${NDK_DIR} ]]
    then
        echo "NDK dir will be set to /opt/cmdline-tools/ndk/25.2.9519653/ by default"
        NDK_DIR="/opt/cmdline-tools/ndk/25.2.9519653/"
    fi
    CMAKE_TOOLCHAIN_FILE="${NDK_DIR}/build/cmake/android.toolchain.cmake"
    if [[ ! -f ${CMAKE_TOOLCHAIN_FILE} ]]
    then
        echo "There is no android.toolchain.cmake in ${NDK_DIR}/build/cmake"
        usage
        exit 1
    fi

    BUILD_DIR="$PROJECT_DIR/build_$CMAKE_BUILD_ARCH"

    add_cmake_arg "-DCMAKE_TOOLCHAIN_FILE=$CMAKE_TOOLCHAIN_FILE"
    add_cmake_arg "-DANDROID_NATIVE_API_LEVEL=$ANDROID_NATIVE_API_LEVEL"
    add_cmake_arg "-DANDROID_TOOLCHAIN_NAME=$ANDROID_TOOLCHAIN_NAME"
    add_cmake_arg "-DANDROID_STL=$ANDROID_STL"
    add_cmake_arg "-DANDROID_ABI=$CMAKE_BUILD_ARCH"
    if [[ "$CMAKE_BUILD_ARCH" == "armeabi-v7a" ]]
    then
        add_cmake_arg "-DANDROID_ARM_NEON=TRUE"
    fi
else
    echo "Unsupported architecture"
    exit 1
fi

add_cmake_arg "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON"

add_cmake_arg "-DNUM_JOBS=${NUM_JOBS}"
    
if [[ $ASAN == true ]]
then
   add_cmake_arg "-DASAN=ON"
fi

if [[ $DEBUG == true ]]
then
    add_cmake_arg "-DCMAKE_BUILD_TYPE=Debug"
else
    add_cmake_arg "-DCMAKE_BUILD_TYPE=Release"
fi

if [[ $CLEAN == true ]]
then
    clean
fi

if [[ $BUILD == true ]]
then
    build
else
    exit 0
fi
