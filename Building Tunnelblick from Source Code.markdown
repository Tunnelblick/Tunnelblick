**Building Tunnelblick from Source Code**

_Last Updated 2021-09-12_

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

Tunnelblick runs on macOS 10.10 and higher.

On recent versions of macOS, Tunnelblick's tun and tap system extensions
are restricted:

 * On macOS Catalina, the computer must be restarted after loading the
   system extensions for the first time.

 * On macOS Big Sur, Tunnelblick's tun and tap system extensions can be
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
 4. You need to have set up Xcode to build Tunnelblick; and
 5. You need to select the type of build you want to create.

This document has a section about each of these requirements.

Interspersed with these are sections on **Using a Virtual Machine**,
**Beginning to Use Xcode to Build Tunnelblick**, and **Building OpenVPN
and the Other Third-Party Software**.


**Using a Virtual Machine**

Using a virtual machine to build Tunnelblick is fine – Tunnelblick
releases are sometimes built using Parallels and VirtualBox. However, there
have been unreproducible errors when the Tunnelblick source code is located
on a network device or the host computer, so copying the source to the
virtual machine's hard drive and building there is recommended. Using
Parallels with more than one virtual CPU also can also cause
unreproducible errors, so a virtual machine setting of one CPU is
recommended for Parallels.


**1. Supported Versions of macOS and Xcode**

The current version of Tunnelblick should be built using:
 * Xcode 7.3.1  on macOS 10.11.6 on an Intel Mac; or
 * Xcode 12.5.1 on macOS 11.5.2  on an Intel or Apple Silicon Mac.

When built by Xcode 7.3.1, Tunnelblick will run on Intel processors, or
on Apple Silicon processors using Rosetta 2.

When built by Xcode 12.5.1, Tunnelblick will be a Universal binary and run
natively on Intel or Apple Silicon processors.

Other versions of Xcode and macOS may fail to build Tunnelblick, or create
Tunnelblick binaries that crash or have other unpredictable behavior.

**2. Getting the Tunnelblick Source Code**

Download the Tunnelblick source code from the [Tunnelblick Project on
GitHub](https://github.com/Tunnelblick//Tunnelblick).

You can download a .zip containing the source from the "master" branch
(which includes the latest changes to the source code) by clicking the
"Download ZIP" button, or you can select a different branch and download
the source code for that, or you can select a specific release and download
the source code for that.

The rest of this document refers to the folder in which you have
downloaded Tunnelblick as "**TunnelblickSource**".


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

  **TunnelblickSource**/third_party/ShellScriptToInstallAutotools.sh

  The script downloads appropriate versions of the tools and installs
  them. Because it installs to a protected folder, you will be asked for
  your password at one point in the process. (You must install as an
  "administrator" user, not as a "standard" user.)

  If you installed the autotools using an older version of the above
  script, you should update automake to version 1.16.3 using the script at

  **TunnelblickSource**/third_party/ShellScriptToInstallAutomake1.16.3.sh

**4. Setting up Xcode to Build Tunnelblick**

Double-click **TunnelblickSource**/tunnelblick/Tunnelblick.xcodeproj to
open the Tunnelblick source code in Xcode.

After a few moments, Xcode will begin indexing files, indicated in the progress
bar at the top of the Xcode window. Allow the indexing to complete, which
usually takes a minute or two. Xcode does indexing at various times, and if you
click a button while Xcode is indexing it may crash. (This is an Xcode
problem, not a Tunnelblick problem.)

Xcode 12 needs to have the command line tools installed. You can
do that in Terminal with the following command:
```xcode-select --install```

Xcode 12 also needs to have "parallelized builds" turned off. This can be done
on the Build tab of the window that appears when you click Product >> Scheme
>> Edit Scheme.

**5. Selecting  the Type of Build You Want to Create**

There are two different types of builds. Unfortunately Xcode defaults to
using the one you shouldn't use, "Debug". You should use the "Release"
build instead.

To select the type of build in Xcode 12:

 1. Click Product > Scheme > Edit Scheme…
 2. Select "Run Tunnelblick" in the list on the left of the window that
 appears.
 3. Select "Info" at the top of the window.
 4. Select the build type in the drop-down list to the right of "Build
 Configuration" on the right.


**Finally, Build Tunnelblick!**

Do a "Product >> Clean build folder" before building.

Finally! You are ready to build Tunnelblick. Click Product > Build.

_Note that the first time a build is done, it may take tens of minutes, even on a
relatively fast computer, so be patient. (Subsequent builds, which do
not usually rebuild OpenVPN or the Tun/Tap kexts, are quicker.)_

When the build is complete, "Build succeeded" will appear at the bottom
of the Build Results window. In some situations it may take another
30-60 seconds to finish creating the .dmg file after "Build succeeded"
appears.

There should not be any errors, but the first time you build Tunnelblick
there may be many warnings, which can be ignored. Building some old
versions of OpenVPN that are included in Tunnelblick generates dozens of
warnings, primarily about signed/unsigned conflicts.

At this point, you might want to make a copy of your current
Tunnelblick.app in case the new one doesn't work for you.

Your .dmg file is at
**TunnelblickSource**/tunnelblick/build/Release/Tunnelblick.dmg.
Double-click it to open the disk image and, in the resulting window,
double-click the Tunnelblick icon to install Tunnelblick to
/Applications.

Good luck!

If you have problems, please post to the [Tunnelblick Discussion
Group](https://groups.google.com/forum/#!forum/tunnelblick-discuss).


Building OpenVPN and the Other Third-Party Software

The normal Tunnelblick build process builds all of the third-party
software (OpenVPN, OpenSSL, LZO, Sparkle, pkcs11-helper, and tuntap)
using third_party/Makefile.

Unlike the usual "Make" procedure, the third_party/Makefile creates
special "built-xxx" files to indicate that each of the components has
been built, and a "do-not-clean" file to indicate that everything has
been built. After the first build of Tunnelblick, the presence of the
"do-not-clean" file and the "built-xxx" files causes the build process
to skip building third party components.

If you modify any of the third-party source after building Tunnelblick,
you must delete the corresponding "built-xxx" file so that Tunnelblick
will rebuild that software when you next build Tunnelblick.

**TunnelblickSource**/third_party/README.txt contains detailed
information about modifying the third-party software.
