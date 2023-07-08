#!/bin/bash

# from project root: 
# sh ignored_utils/build_utils/export_template_generator.sh ~/Programming/godot/godot [all|ios|android]

# this script allows you to generate Godot export templates for PCK encryption

echo Starting encrypted export template build script.

# Check if the Godot source argument is provided
if [ -z "$1" ]; then
    echo "Error: Godot source path argument is missing."
    exit 1
fi

# Change to the specified directory
cd "$1" || {
    echo "Error: Failed to change directory."
    exit 1
}

option="$2"
# check specified platforms
if [[ "$option" != "all" && "$option" != "ios" && "$option" != "android" ]]; then
  echo "Invalid option: $option"
  exit 1
fi

# Check if the required environment variables are set for Android
if [[ -z "${ANDROID_SDK_ROOT}" || -z "${ANDROID_HOME}" || -z "${JAVA_HOME}" ]]; then
    if [[ "$2" == "android" || "$2" == "all" ]]; then
        echo "Error: Required environment variables are not set for Android."
        echo "Please ensure that ANDROID_SDK_ROOT, ANDROID_HOME, and JAVA_HOME are properly set."
        exit 1
    fi
fi

# Check if the required environment variables are set for iOS
if [[ -z "${VULKAN_SDK}" ]]; then
    if [[ "$2" == "ios" || "$2" == "all" ]]; then
        echo "Error: Required environment variables are not set for iOS."
        echo "Please ensure that VULKAN_SDK is properly set."
        exit 1
    fi
fi

# Check if SCRIPT_AES256_ENCRYPTION_KEY is set
if [[ -z "${SCRIPT_AES256_ENCRYPTION_KEY}" ]]; then
    echo "Warning: SCRIPT_AES256_ENCRYPTION_KEY environment variable is not set."
    echo "The generated templates will not be encrypted."
    echo "Type 'Y' to acknowledge and proceed, or any other key to exit:"
    read -r acknowledge
    if [[ "${acknowledge}" != "Y" && "${acknowledge}" != "y" ]]; then
        echo "User acknowledgment not received. Exiting..."
        exit 1
    fi
fi

# Print the current Git branch and branch tag
git_branch=$(git rev-parse --abbrev-ref HEAD)
echo "Current Git Branch: $git_branch"

git_tag=$(git describe --exact-match --tags HEAD 2>/dev/null)
if [ -n "$git_tag" ]; then
    echo "Current Git Tag: $git_tag"
fi

build_ios() {
    echo "Building iOS templates..."

    # clean ios build
    echo Cleaning build with Scons
    scons p=ios -c 
    echo Finished cleaning build with Scons

    # iOS debug builds
    scons p=ios target=template_debug arch=arm64 tools=no &&
    scons p=ios target=template_debug ios_simulator=yes arch=x86_64 tools=no &&
    scons p=ios target=template_debug ios_simulator=yes arch=arm64 tools=no &&

    # iOS release builds
    scons p=ios target=template_release arch=arm64 tools=no &&
    scons p=ios target=template_release arch=arm64 ios_simulator=yes tools=no &&
    scons p=ios target=template_release arch=x86_64 ios_simulator=yes tools=no &&

    cd bin &&
    
    echo Deleting old ios_xcode folder
    rm -rf ios_xcode/
    
    echo Copying new ios_xcode folder
    cp -r ../misc/dist/ios_xcode . &&

    # make debug fat
    cp libgodot.ios.template_debug.arm64.a ios_xcode/libgodot.ios.debug.xcframework/ios-arm64/libgodot.a &&
    lipo -create libgodot.ios.template_debug.arm64.simulator.a libgodot.ios.template_debug.x86_64.simulator.a -output ios_xcode/libgodot.ios.debug.xcframework/ios-arm64_x86_64-simulator/libgodot.a &&

    cp libgodot.ios.template_release.arm64.a ios_xcode/libgodot.ios.release.xcframework/ios-arm64/libgodot.a &&
    lipo -create libgodot.ios.template_release.arm64.simulator.a libgodot.ios.template_release.x86_64.simulator.a -output  ios_xcode/libgodot.ios.release.xcframework/ios-arm64_x86_64-simulator/libgodot.a &&

    # The MoltenVK static .xcframework folder must also be placed in the ios_xcode folder once it has been created.
    echo Copying MoltenVK...
    cp "${VULKAN_SDK}/MoltenVK/MoltenVK.xcframework/Info.plist" ios_xcode/
    cp "${VULKAN_SDK}/MoltenVK/MoltenVK.xcframework/ios-arm64" ios_xcode/
    cp "${VULKAN_SDK}/MoltenVK/MoltenVK.xcframework/ios-arm64_x86_64-maccatalyst" ios_xcode/
    cp "${VULKAN_SDK}/MoltenVK/MoltenVK.xcframework/ios-arm64_x86_64-simulator" ios_xcode/
    echo Finished copying MoltenVK...

    echo Deleting old ios.zip if exists
    rm ios.zip

    echo "Zipping..."
    # exclude unneeded release and debug folders
    cd ios_xcode/ && zip -q -9 -r ../ios.zip * -x "release/*" -x "debug/*"    
    
    echo "iOS export completed."
}

build_android() {
    echo "Building Android templates..."
    echo "Cleaning Android build templates"
    cd platform/android/java &&
    ./gradlew cleanGodotTemplates && 
    cd ../../../ &&

    # Android builds
    scons platform=android target=template_release arch=armv7 tools=no &&
    scons platform=android target=template_release arch=arm64v8 tools=no &&
    scons platform=android target=template_release arch=x86 tools=no &&
    scons platform=android target=template_release arch=x86_64 tools=no &&


    # Debug builds for Android
    scons platform=android target=template_debug arch=armv7 tools=no &&
    scons platform=android target=template_debug arch=arm64v8 tools=no &&
    scons platform=android target=template_debug arch=x86 tools=no &&
    scons platform=android target=template_debug arch=x86_64 tools=no &&

    # Generate Godot templates for Android
    cd platform/android/java &&
    ./gradlew generateGodotTemplates
        
    echo "Android export completed."
}

if [ "$2" == "ios" ]; then
    build_ios
elif [ "$2" == "android" ]; then
    build_android
else
    build_ios
    build_android
fi

echo "Success! Export complete."
