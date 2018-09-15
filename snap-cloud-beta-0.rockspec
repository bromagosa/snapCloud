package = "snap-cloud"
version = "beta-0"
source = {
   url = "git://github.com/bromagosa/snapCloud.git"
}
description = {
   summary = "A Project Server and API for Snap!.",
   detailed = [[
      This is currently in active development.
      Maybe this will say something witty one day.
   ]],
   homepage = "http://snap.berkeley.edu",
   license = "AGPL"
}
dependencies = {
   "lua >= 5.1, < 5.2",
   "lapis",
   "md5",
   "luasec",
   "luacrypto",
   "xml",
   "lua-resty-mail",
   "luasocket"
}
build = {
    type = "builtin",

    modules = {}
}
