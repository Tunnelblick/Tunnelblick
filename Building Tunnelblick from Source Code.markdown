**Building Tunnelblick from Source Code**

_Last Updated 2024-06-16_

You can build Tunnelblick from the source code. Usually, people install
and use a ready-to-use binary version of Tunnelblick. The most recent
binary is available on the [Tunnelblick
website](https://tunnelblick.net) as a disk image (".dmg") file
containing a copy of the Tunnelblick application. It's easy to install
the Tunnelblick applications from this .dmg -- you simply double-click it.

Because Tunnelblick is distributed using the "GNU General Public
License, version 2", the source code itself is also available. Anyone
with sufficient technical skills and resources can create their own
binary and use it as they see fit under the terms of the license. This
document describes how to do that.

Tunnelblick runs on macOS High Sierra (10.13) and higher when built with Xcode 16
as described in this document.

When running on recent versions of macOS, Tunnelblick's tun and tap system
extensions are restricted:

 * On macOS Catalina (10.15), the computer must be restarted after loading the
   system extensions for the first time.

 * On macOS Big Sur (10.16), Tunnelblick's tun and tap system extensions can be
   used only after being installed and approved by an administrator;
   the installation process involves restarting the computer.

 * On Apple Silicon (M1) Macs, installing Tunnelblick's system extensions
   requires a change to the default security settings, which requires two
   additional computer restarts.

See [The Future of Tun and Tap VPNs on macOS](https://tunnelblick.net/cTunTapConnections.html)
For details.

To build Tunnelblick from the source code:

 1. You need a supported version of macOS and Xcode;
 2. You need a copy of the Tunnelblick source code;
 3. You need to have installed the GNU autotools;
 4. If you want to build a release version, you need to give Xcode "Full Disk Access";
 5. If building on an Apple Silicon Mac, you need to install Rosetta;
 6. You need to install Xcode command line tools;
 7. You need to have set up Xcode to build Tunnelblick;
 8. You need to select the type of build you want to create; and then
 9. You can (finally!) build Tunnelblick.

This document has a section about each of these steps.

Interspersed with these are sections on **Using a Virtual Machine**,
**Beginning to Use Xcode to Build Tunnelblick**, and **Building OpenVPN
and the Other Third-Party Software**.


**Using a Virtual Machine**

Using a virtual machine to build Tunnelblick is fine – Tunnelblick
releases are sometimes built using
[Viable](https://eclecticlight.co/virtualisation-on-apple-silicon/).
However, there have been unreproducible errors when the Tunnelblick source
code is located on a network device or the host computer, so copying the source
to the virtual machine's hard drive and building there is recommended.


**1. Supported Versions of macOS and Xcode**

The current version of Tunnelblick should be built using:
 * Xcode 16.0  on macOS 14.7 on an Intel or Apple Silicon Mac; Rosetta is required
on Apple Silicon Macs because of a bug in Apple's "files" command line utility.

Tunnelblick will be a Universal binary and run natively on Intel or Apple Silicon
processors.

Other versions of Xcode and macOS may fail to build Tunnelblick, or create
Tunnelblick binaries that crash or have other unpredictable behavior.

**2. Getting the Tunnelblick Source Code**

Tunnelblick source code is maintained using the git version control program. The
three branches normally used are:
 * *master*: Contains the most recent code; beta releases are based on master.
 * *3*: Contains the most recent code for the latest 3.* release
 * *3.5*: Contains the most recent code for the 3.5.* release (very old!)

Download the Tunnelblick source code from the [Tunnelblick Project on
GitHub](https://github.com/Tunnelblick//Tunnelblick).

You can download a .zip containing the source from the "master" branch (which includes
the latest changes to the source code) by clicking the green "< > Code" button and
then the "Download ZIP" button, or you can select a different branch and download
the source code for that. As an alternative, you can find a specific release and
download the source code for that.

The rest of this document refers to the folder in which you have
downloaded Tunnelblick as "**TBS**".


**3. Installing the GNU autotools**

To build the third-party parts of Tunnelblick, the build computer must
have appropriate versions of the GNU "auto tools" installed in
/usr/local/bin.

Notes:

 1. automake version 2.0 and higher cannot be used.

 2. If built with automake version 1.14 or higher, warnings and errors
 concerning "subdir-objects" may be ignored.

  **Method 1. Homebrew Install**

  Required packages are available from homebrew. If you have homebrew
  installed, open a Terminal window and execute

  brew install autoconf automake libtool

  **Method 2. Shell Script Install**

  A shell script is provided that will download and install them. To use
  it, open a Terminal window and execute

  **TBS**/third_party/ShellScriptToInstallAutotools.sh

  The script downloads appropriate versions of the tools and installs
  them. Because it installs to a protected folder, you will be asked for
  your password at one point in the process. (You must install as an
  "administrator" user, not as a "standard" user.)

  If you installed the autotools using an older version of the above
  script, you should update automake to version 1.16.3 using the script at

  **TBS**/third_party/ShellScriptToInstallAutomake1.16.3.sh

**4. (Optional) Giving Xcode "Full Disk Access"**

If you are building a "Release" version of Tunnelblick, you must give
Xcode "Full Disk Access" so it can build disk images. "Debug" versions do not
build disk images and thus do not need "Full Disk Access".

To give Xcode "Full Disk Access", set:

System Settings >> Privacy and Security >> Full Disk Access >> Xcode

**5. Installing Rosetta**

On an Apple Silicon Mac, Tunnelblick's build process requires Rosetta because
it uses Apple's "files" command line program, which has a bug which requires
Rosetta to work properly. Install Rosetta by typing the following into Terminal:

softwareupdate --install-rosetta

**6. Installing Xcode command line tools**

Xcode needs to have the command line tools installed. You can
do that in Terminal with the following command:
```xcode-select --install```

**7. Setting up Xcode to Build Tunnelblick**

Double-click **TBS**/tunnelblick/Tunnelblick.xcodeproj to
open the Tunnelblick source code in Xcode.

After a few moments, Xcode will begin indexing files, indicated in the progress
bar at the top of the Xcode window. Allow the indexing to complete, which
usually takes a minute or two. Xcode does indexing at various times, and if you
click a button while Xcode is indexing it may crash. (This is an Xcode
problem, not a Tunnelblick problem.)

Xcode needs to be built using "Manual Order", which is _not_ the default. To
change the default, click Product >> Scheme >> Edit Scheme, then "Build" on the left,
then set "Build Order" to "Manual Order". You should also un-check "Find Implicit
Dependencies".

Xcode also needs to be set to build in "legacy" locations; in Xcode >> Settings
>> Locations >> Advanced >> set "Build Location" to "Legacy".

**8. Selecting the Type of Build You Want to Create**

There are two different types of builds:

 * Debug: Used to debug Tunnelblick. Builds only for the current CPU architecture
   and does not build disk images.

 * Release: Used for distribution. Builds for all available CPU architectures
   and creates both unsigned and ad hoc signed Tunnelblick.app and Tunnelblick.dmg.

Xcode defaults to "Debug", so you probably want to change it to "Release".

To select the type of build in Xcode:

 1. Click Product > Scheme > Edit Scheme…
 2. Select "Run Tunnelblick" in the list on the left of the window that
 appears.
 3. Select "Info" at the top of the window.
 4. Select build type "Release" in the drop-down list to the right of "Build
 Configuration" on the right.

**9. Finally, Building Tunnelblick!**

Do a "Product >> Clean build folder" before building.

Finally! You are ready to build Tunnelblick. Click Product > Build.

_Note that the first time a build is done, it may take tens of minutes, even on a
relatively fast computer, so be patient. (Subsequent builds, which do
not usually rebuild OpenVPN or the Tun/Tap kexts, are quicker.)_

When the build is complete, "Build succeeded" should appear at the bottom
of the Build Results window. In some situations it may take another
30-60 seconds to finish creating the .dmg file after "Build succeeded"
appears.

There should not be any errors, but there may be many warnings (over a thousand!)
the first time Tunnelblick is built. You can ignore them: some old versions of
OpenVPN and OpenSSL that are included in Tunnelblick generate these warnings.

Note: the first build of Tunnelblick after updating Xcode may cause a warning about
suggested changes to build settings, caused by changes in Xcode. You can accept
all of the changes except those that would cause Xcode to codesign binaries.

DO NOT ACCEPT THE CHANGES TO CODE SIGN BINARIES.

Tunnelblick's structure is unusual and Xcode isn't able to properly sign it.
Tunnelblick's build process signs Tunnelblick, so Xcode should not sign it.

At this point, you might want to make a copy of your current
Tunnelblick.app in case the new one doesn't work for you.

Your .dmg file is at

**TBS**/tunnelblick/build/Release/Tunnelblick.dmg.

Double-click it to open the disk image and, in the resulting window,
double-click the Tunnelblick icon to install Tunnelblick to
/Applications.

Good luck!

If you have problems, please post to the [Tunnelblick Discussion
Group](https://groups.google.com/forum/#!forum/tunnelblick-discuss).


Building OpenVPN and the Other Third-Party Software

The normal Tunnelblick build process only builds the third-party software (OpenVPN,
OpenSSL, LZO, Sparkle, pkcs11-helper, and tuntap) **once**, using third_party/Makefile.
Subsequent builds normally skip this, and build only the Tunnelblick code. This
is done because building the third-party software takes a long time (tens of minutes,
even on a fast computer), and because most debugging is done on Tunnelblick, not
the third-party programs.

Unlike the usual "Make" procedure, the third_party/Makefile creates
special "built-xxx" files to indicate that each of the components has
been built, and a "do-not-clean" file to indicate that everything has
been built. After the first build of Tunnelblick, the presence of the
"do-not-clean" file and the "built-xxx" files causes the build process
to skip building third party components.

If you modify any of the third-party source after building Tunnelblick,
you must delete the corresponding "built-xxx" file so that Tunnelblick
will rebuild that software when you next build Tunnelblick.

To re-build all of the third-party software when Tunnelblick is built, delete
the "third_party/do-not-clean file", the "third_party/built-..." files, and the
"third_party/product" and "third_party/build" folders.

**TBS**/third_party/README.txt contains detailed
information about modifying and updating the third-party software.
