==== Tunnelblick for Mac OS X 10.3 or higher ====

Tunnelblick is a simple graphical user interface for the great VPN software OpenVPN 2.0 and higher. It is written in Cocoa and comes in a ready to use distribution with all necessary binaries and drivers. 
Versions of OpenVPN older than 2.0 are not supported, because they lack the management interface used by Tunnelblick.


==== Simple Installation ====

Download the disk image from: http://tunnelblick.net/, mount it and start the Installer Package Tunnelblick-Complete.mpkg to continue. Tunnelblick will be put in your /Applications folder.

Single Package Installation is also available for advanced users - please check the corresponding section in this manual on how to proceed. 


==== Configuration and Use ====

Now you are ready to start Tunnelblick by doubleclicking on it. A menu item that looks like the entrance to a tunnel will appear in the upper right corner of the menu bar. Clicking on that item will provide a drop-down menu. 

When starting Tunnelblick for the first time, you will be warned that no valid configuration file for OpenVPN exists in the openvpn directory. To provide Tunnelblick with the lacking file, click 'Continue' and a sample configuration text file will open. Simply replace its contents with the contents of your personal openvpn configuration file and save the file. 

If you have received key files together with your personal configuration file, please make sure to put them in the openvpn directory (located in ~/Library/openvpn/ - the openvpn folder is a subfolder of the Library folder located in your home directory). OpenVPN will try to locate the key files in this directory, unless the paths to them are specified in the configuration file in absolute terms.

Select "Connect" from the drop-down menu to establish the pre-configured VPN connection. To illustrate the connection being established, three dots will appear in the tunnel menu item. If the connection was successfully created, you will see light at the end of the tunnel. 

You may be asked for a passphrase or username/password combination. You can save your passphrase or password in Apple's Keychain by checking the appropriate checkbox. 

The connection will be active as long as you do not end it or log out of your computer. Putting your computer to sleep or losing contact to the server (by lack of wlan signal, for example) will result in Tunnelblick's attempt to re-establish the connection.

If a connection error occurs, or in the unlikely event of an interface crash, Tunnelblick will terminate the VPN tunnel and record the error in your computer's syslog.

Use "Disconnect" from the drop-down menu to end the VPN connection; use "Quit" to leave the program and to prevent Tunnelblick from starting itself at your next login at your computer.

==== Uninstalling ====

Please remove the following files to uninstall Tunnelblick from your system:

/System/Library/Extensions/tap.kext
/System/Library/Extensions/tun.kext
/System/Library/StartupItems/tap
/System/Library/StartupItems/tun
/usr/local/sbin/openvpn
/usr/local/sbin/openvpnstop
/usr/local/sbin/openvpnstart
/Applications/Tunnelblick.app

Then unload the kernel extensions or reboot and you're done.


==== Building Tunnelblick from Source ====

To check out the source from the repository, you need subversion. If you have fink (http://fink.sourceforge.net), this can be easily done by typing:

apt-get install svn-client

Check out the source code from our subversion repository by typing:

svn checkout svn://tunnelblick.net/openvpngui


Then type:

cd openvpngui

and 

./makepackages.sh

to automatically build and generate the .dmg files containing the Installer Packages. You will need your administrator password. Don't worry, this is because the permissions of some files must be set to 'chown root:wheel' prior to the creation of the package.


==== Package Description ====

The disk image contains the following single packages:

TUN/TAP driver for Mac OS X by Matthias Nissler, see 
http://www-user.rhrk.uni-kl.de/~nissler/tuntap/ for further information.

-> tap_kext.pkg
-> tun_kext.pkg 
-> startup_item.pkg

OpenVPN 2.0 console application by James Yonan and the OpenVPN project,
see http://openvpn.net/ for further information.

-> OpenVPN.pkg

Tunnelblick application by Angelo Laub and Dirk Theisen, see http://tunnelblick.net for further information.

-> Tunnelblick.pkg

If you want to install all the packages at once, then doubleclick on

-> Tunnelblick-Complete.mpkg
 

==== Known Bugs and Drawbacks ====

* At this moment, no multiple connections are possible.

* Tunnelblick does not provide an interface for the OpenVPN log-output as yet. Please refer to your computer's syslog for this information.


==== Credits ====

The Tunnelblick Crew would like to thank the following people:

* Andreas Prusak for the japanese localization
* Jens Ohlig for the korean localization
* Waldemar Brodkorb for the build script and first version of documentation
* Tina Lorenz for this document 
* Daniel Lehmann for the beer he did not provide and his quick and wonderful OpenVPN Support.
* MacHackers Bonn and the famous Netzladen for Mate and room for thoughts


==== Feedback ====

Please contact us with suggestions about Tunnelblick or if you find any bugs not listed here.
 
Have fun!

	Dirk Theisen, Objectpark Group <d.theisen@objectpark.org>
	Angelo Laub <al@rechenknecht.net>

