local oo = require("loop.simple")
local AppletMeta = require("jive.AppletMeta")
local appletManager = appletManager
local log = require("jive.utils.log").logger("StandaloneTime")

module(...)
oo.class(_M, AppletMeta)

function jiveVersion(meta)
    return 1, 1
end

function registerApplet(meta)
    log:warn("StandaloneTime: Meta loaded; registerApplet")
    meta:registerService("standaloneTimeStart")
    -- AppletManager services are lazy. Calling our registered service here is
    -- the normal framework path that instantiates this headless applet.
    appletManager:callService("standaloneTimeStart")
end
