**Building Tunnelblick from Source Code**

You can build Tunnelblick from the source code. Usually, people install and use a ready-to-use binary version of Tunnelblick. The most recent binary is available on the [Tunnelblick website](https://tunnelblick.net) and is a disk image (".dmg") file. It's easy to install Tunnelblick from this .dmg -- you simple double-click it.

Because Tunnelblick is distributed using the "GNU General Public License, version 2", the source code itself is also available, including the source code for changes before they are incorporated into a binary. That means that anyone with sufficient technical skills and resources can create their own binary and use it as they see fit under the terms of the license. This document describes how to do that.

To build Tunnelblick from the source code:

 1.	You need a copy of the Tunnelblick source code;
 2.	You need a supported version of OS X and Xcode;
 3.	You need to have set up Xcode to build Tunnelblick;
 4.	You need to have installed the GNU autotools;
 5.	You need to select the type of build you want to create.

This document has a section about each of these requirements.

Interspersed with these are sections on **Using a Virtual Machine**, **Beginning to Use Xcode to Build Tunnelblick**, and **Building OpenVPN and the Other Third-Party Software**.


**Using a Virtual Machine**

Using a virtual machine to build Tunnelblick is fine – Tunnelblick releases are built using Parallels and VirtualBox. However, there have been unreproducible errors when the Tunnelblick source code is located on a network device or the host computer, so copying the source to the virtual machine's hard drive and building there is recommended. Using Parallels with more than one virtual CPU also can also cause unreproducible errors, so a virtual machine setting of one CPU is recommended for Parallels.


**1. Getting the Tunnelblick Source Code**

Download the Tunnelblick source code from the [Tunnelblick Project on GitHub](https://github.com/Tunnelblick//Tunnelblick).

You can download a .zip containing the source from the "master" branch (which includes the latest changes to the source code) by clicking the "Download ZIP" button, or you can select a different branch and download the source code for that.

The rest of this document refers to the folder in which you have downloaded Tunnelblick as "**TunnelblickSource**".

**2. Supported Versions of OS X and Xcode**

As of 2016-09-30, Tunnelblick is built using Xcode 7.3.1 on OS X 10.11.6. (Xcode 8.0 creates binaries without complaint but they cause peculiar, unreproducible crashes.)

Older versions (such as the 3.5 branch) of Tunnelblick can be built using Xcode 3.2.2 on OS X 10.6.8. (Do not use Xcode 3.2.3.)

Other versions of Xcode and OS X may be used, but additional work may be required.

Which platform you build on determines what platforms can run the Tunnelblick application you build:

 * When Tunnelblick is built using Xcode 7.0 and higher on OS X 10.10.5 or higher:
   ⁃ The Tunnelblick application and all supporting programs are 64-bit Intel programs.
   ⁃ Tunnelblick works on OS X 10.8 and higher and on OS X 10.7.0 and higher when running a 64-bit kernel.

 * When Tunnelblick is built using Xcode 3.2.2 on OS X 10.6.8:
   ⁃ Tunnelblick works on OS X 10.4 - 10.10 using PowerPC or Intel processors.
   ⁃ Tunnelblick and most of its supporting programs are 32-bit PowerPC/Intel programs.
   ⁃ OpenVPN and the tun and tap kexts are 32/64-bit PowerPC/Intel programs.


**3. Installing the GNU autotools**

To build Tunnelblick, the build computer must have appropriate versions of the GNU "auto tools" installed in /usr/local/bin.

  **Method 1. Homebrew Install**

  Required packages are available from homebrew. If you have homebrew installed, open a Terminal window and execute

  brew install autoconf automake libtool

  **Method 2. Shell Script Install**

  A shell script is provided that will download and install them. To use it, open a Terminal window and execute

  **TunnelblickSource**/third_party/ShellScriptToInstallAutotools.sh

  The script downloads appropriate versions of the tools and installs them. Because it installs to a protected folder, you will be asked for your password at one point in the process. (You must install as an "administrator" user, not as a "standard" user.)


**4. Setting up Xcode to Build Tunnelblick**

Double-click …TunnelblickSource/tunnelblick/Tunnelblick.xcodeproj to open the Tunnelblick source code in Xcode.

After a few moments, recent versions of Xcode will begin indexing files, indicated in the progress bar at the top of the Xcode window. Allow the indexing to complete, which usually takes a minute or two. Xcode does indexing at various times, and if you click a button while Xcode is indexing it will often crash. (This is an Xcode problem, not a Tunnelblick problem.) The safest way to proceed if Xcode crashes is to download the source code again, because Xcode creates caches which can be corrupted when Xcode crashes and cause even more crashes.

To build Tunnelblick using Xcode 7.0+, it needs to be set up to use "legacy" locations for build products:

1. Launch Xcode
2. Click "File" > "Project Settings..."
3. Click the "Advanced" button
4. Click on the "Legacy" radio button
5. Click the "Done" button

Xcode 7.0+ also need to have the command line tools installed. You can do that in Terminal with the following command: ```xcode-select&nbsp;--install```


**5. Selecting  the Type of Build You Want to Create**

There are two different types of builds. Unfortunately Xcode defaults to using the one you shouldn't use, "Debug". You should use the "Release" build instead.

To select the type of build in Xcode 3.2.2, change it in the drop-down list to "Unsigned Release".

To select the type of build in Xcode 7.0+:
 1. Click Product > Scheme > Edit Scheme…
 2. Select "Run Tunnelblick" in the list on the left of the window that appears
 3. Select "Info" at the top of the window
 4. Select the build type in the drop-down list to the right of "Build Configuration" on the right.


**Finally, Build Tunnelblick!**

Do a "Clean" before building.

Finally! You are ready to build Tunnelblick. Go ahead!

The first time a build is done, it may take several minutes, even on a relatively fast computer, so be patient. (Subsequent builds, which do not usually rebuild OpenVPN or the Tun/Tap kexts, are quicker.)

When the build is complete, "Build succeeded" will appear at the bottom of the Build Results window. In some situations it may take another 30-60 seconds to finish creating the .dmg file after "Build succeeded" appears.

There should not be any errors, but the first time you build Tunnelblick there may be many warnings. Building OpenVPN 2.3.6 generates dozens of warnings, primarily about signed/unsigned conflicts. Other versions of OpenVPN may or may not generate errors.


At this point, you might want to make a copy of your current Tunnelblick.app in case the new one doesn't work for you.

Your .dmg file is at **TunnelblickSource**/tunnelblick/build/Release/Tunnelblick.dmg. Double-click it to open the disk image and, in the resulting window, double-click the Tunnelblick icon to install Tunnelblick to /Applications.

Good luck!

If you have problems, please post to the [Tunnelblick Discussion Group](https://groups.google.com/forum/#!forum/tunnelblick-discuss).


Building OpenVPN and the Other Third-Party Software

There is a README.txt in the third_party folder in the source code which describes the contents of that folder and how to make changes to the programs it contains.

The normal Tunnelblick build process builds all of the third-party software (OpenVPN, OpenSSL, LZO, Sparkle, pkcs11-helper, and tuntap) using third_party/Makefile.

Unlike the usual "Make" procedure, the third_party/Makefile creates special "built-xxx" files to indicate that each of the components has been built, and a "do-not-clean" file to indicate that everything has been built. After the first build of Tunnelblick, the presence of the "do-not-clean" file and the "built-xxx" files causes the build process to skip building third party components.

If you modify any of the third-party source after building Tunnelblick, you must delete the corresponding "built-xxx" file so that Tunnelblick will rebuild that software when you next build Tunnelblick.

***TunnelblickSource***/third_party/README.txt contains detailed information about modifying the third-party software.
