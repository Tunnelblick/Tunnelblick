easy-rsa/2.x doesn't work well with LibreSSL because the latter doesn't
understand $ENV:: in the config file. Here is a simple fix to make it work on
macOS High Sierra. It consists of a a new template config file
libressl.cfg.template and an updated whichopensslcnf script. The idea is to
embed the necessary environment variables directly into the config file which
is genererated form the template.
