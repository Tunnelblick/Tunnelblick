Tunnelblick comes set up to be built using Xcode 3.2.2 on OS X 10.6.8 but can be built
with Xcode 5.1.1 on OS X 10.8.5 or Xcode 6.3 and higher on OS X 10.10.3 or higher.

 * PowerPC and Intel processors and OS X 10.4 - 10.10 are supported only when Tunnelblick
   is built using Xcode 3.2.2 on OS X 10.6.8.

 * Xcode 5.1.1 and 6.3 and higher only generate 64-bit Intel code and are for use on
   OS X 10.6 - 10.10 and higher only.


To use Xcode 3.2.2 on OS X 10.6.8:

  Double-click tunnelblick/Tunnelblick.xcodeproj to being using Xcode.


To use a different version of Xcode on a different version of OS X:

  1. Quit Xcode

  2. Replace

          tunnelblick/tunnelblick.xcodeproj

     with a tunnelblick.xcodeproj from the appropriate folder:

          tunnelblick/xcodeproj-versions/xcode6.3   (on OS X 10.10.3)

          tunnelblick/xcodeproj-versions/xcode5.1.1 (on OS X 10.8.5)

          tunnelblick/xcodeproj-versions/xcode3.2.2 (on OS X 10.6.8)

  3. Double-click tunnelblick/Tunnelblick.xcodeproj to begin.

  4. Be sure to do a "Clean all targets" before building.
