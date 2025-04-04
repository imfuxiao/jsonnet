#!/bin/bash
set -e

# Configuration
LIBRARY_NAME="Jsonnet"
IOS_SDK="iphoneos"
SIMULATOR_SDK="iphonesimulator"
FRAMEWORK_DIR="./build/frameworks"
BUILD_DIR="./build"
XCFRAMEWORK_DIR="./build/xcframework"

# Create necessary directories
echo "Creating build directories..."
mkdir -p $FRAMEWORK_DIR/iOS
mkdir -p $FRAMEWORK_DIR/Simulator
mkdir -p $BUILD_DIR/ios_objects
mkdir -p $BUILD_DIR/simulator_objects
mkdir -p $XCFRAMEWORK_DIR

# Ensure directories have write permissions
chmod -R 755 $BUILD_DIR
chmod -R 755 $FRAMEWORK_DIR

# Clean existing builds
rm -rf $FRAMEWORK_DIR/*
rm -rf $XCFRAMEWORK_DIR/*
rm -rf $BUILD_DIR/ios_objects/*
rm -rf $BUILD_DIR/simulator_objects/*

# Generate std.jsonnet.h (required for desugarer.cpp)
echo "Generating std.jsonnet.h..."
if [ ! -f core/std.jsonnet.h ]; then
    ((od -v -Anone -t u1 stdlib/std.jsonnet | tr " " "\n" | grep -v "^$" | tr "\n" "," ) && echo "0") > core/std.jsonnet.h
    echo >> core/std.jsonnet.h
fi

# Set up common compiler flags
COMMON_FLAGS="-g -O3 -Wall -Wextra -pedantic -fPIC -Iinclude -Ithird_party/md5 -Ithird_party/json -Ithird_party/rapidyaml/"
CFLAGS="$COMMON_FLAGS -std=c99"
CXXFLAGS="$COMMON_FLAGS -Woverloaded-virtual -std=c++17"

# Source files
LIB_SRC=$(find core -name "*.cpp" -not -name "*test*")
LIB_SRC="$LIB_SRC third_party/md5/md5.cpp third_party/rapidyaml/rapidyaml.cpp cpp/libjsonnet++.cpp"

# 1. Build for iOS devices (arm64)
echo "Building for iOS devices (arm64)..."
for SRC in $LIB_SRC; do
    FILENAME=$(basename "$SRC")
    OBJNAME="${FILENAME%.cpp}.o"
    xcrun --sdk $IOS_SDK clang++ -arch arm64 \
        $CXXFLAGS \
        -miphoneos-version-min=12.0 \
        -c "$SRC" \
        -o "$BUILD_DIR/ios_objects/$OBJNAME"
done

# Create static library for iOS
# Create static library for iOS - use absolute path
echo "Creating iOS static library..."
mkdir -p "$FRAMEWORK_DIR/iOS"
libtool -static -o "$PWD/$FRAMEWORK_DIR/iOS/libJsonnet.a" $BUILD_DIR/ios_objects/*.o

# 2. Build for iOS Simulator (arm64, x86_64)
echo "Building for iOS Simulator..."
for SRC in $LIB_SRC; do
    FILENAME=$(basename "$SRC")
    OBJNAME="${FILENAME%.cpp}.o"
    xcrun --sdk $SIMULATOR_SDK clang++ -arch arm64 -arch x86_64 \
        $CXXFLAGS \
        -mios-simulator-version-min=12.0 \
        -c "$SRC" \
        -o "$BUILD_DIR/simulator_objects/$OBJNAME"
done

# Create static library for Simulator
# Create static library for Simulator - use absolute path
echo "Creating Simulator static library..."
mkdir -p "$FRAMEWORK_DIR/Simulator"
libtool -static -o "$PWD/$FRAMEWORK_DIR/Simulator/libJsonnet.a" $BUILD_DIR/simulator_objects/*.o

# 3. Create framework structure
echo "Creating framework structure..."
mkdir -p $FRAMEWORK_DIR/iOS/$LIBRARY_NAME.framework/Headers
mkdir -p $FRAMEWORK_DIR/Simulator/$LIBRARY_NAME.framework/Headers

# Copy headers
cp include/libjsonnet.h $FRAMEWORK_DIR/iOS/$LIBRARY_NAME.framework/Headers/
cp include/libjsonnet_fmt.h $FRAMEWORK_DIR/iOS/$LIBRARY_NAME.framework/Headers/
cp include/libjsonnet++.h $FRAMEWORK_DIR/iOS/$LIBRARY_NAME.framework/Headers/

cp include/libjsonnet.h $FRAMEWORK_DIR/Simulator/$LIBRARY_NAME.framework/Headers/
cp include/libjsonnet_fmt.h $FRAMEWORK_DIR/Simulator/$LIBRARY_NAME.framework/Headers/
cp include/libjsonnet++.h $FRAMEWORK_DIR/Simulator/$LIBRARY_NAME.framework/Headers/

# Copy static libraries
cp $FRAMEWORK_DIR/iOS/libJsonnet.a $FRAMEWORK_DIR/iOS/$LIBRARY_NAME.framework/$LIBRARY_NAME
cp $FRAMEWORK_DIR/Simulator/libJsonnet.a $FRAMEWORK_DIR/Simulator/$LIBRARY_NAME.framework/$LIBRARY_NAME

# Create Info.plist files
cat > $FRAMEWORK_DIR/iOS/$LIBRARY_NAME.framework/Info.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$LIBRARY_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>org.jsonnet.$LIBRARY_NAME</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$LIBRARY_NAME</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>MinimumOSVersion</key>
    <string>12.0</string>
</dict>
</plist>
EOF

cp $FRAMEWORK_DIR/iOS/$LIBRARY_NAME.framework/Info.plist $FRAMEWORK_DIR/Simulator/$LIBRARY_NAME.framework/Info.plist

# 4. Create XCFramework
echo "Creating XCFramework..."
xcodebuild -create-xcframework \
    -framework $FRAMEWORK_DIR/iOS/$LIBRARY_NAME.framework \
    -framework $FRAMEWORK_DIR/Simulator/$LIBRARY_NAME.framework \
    -output $XCFRAMEWORK_DIR/$LIBRARY_NAME.xcframework

echo "XCFramework successfully created at $XCFRAMEWORK_DIR/$LIBRARY_NAME.xcframework"