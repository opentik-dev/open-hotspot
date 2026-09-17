local uci = require("luci.model.uci").cursor()

local m = Map("open-hotspot", translate("Open-HotSpot setup"))
m.description = translate(
	"Local-only account, quota, and speed management for openNDS. " ..
	"The current stage prepares the base without changing an existing FAS.") ..
	'<link rel="stylesheet" href="/luci-static/resources/open-hotspot.css">'

local s = m:section(NamedSection, "global", "manager",
	translate("Installation state"))
s.anonymous = true
s.addremove = false

local function readonly(name, title, description)
	local option = s:option(DummyValue, name, title, description)
	option.rmempty = false
	function option.cfgvalue(_, section)
		return uci:get("open-hotspot", section, name) or "—"
	end
	return option
end

local state = readonly("setup_state", translate("State"),
	translate("The setup state is recorded by the restartable base setup."))
state.rawhtml = false

readonly("setup_last_error", translate("Last setup error"),
	translate("A blocker is recorded here without changing network services."))
readonly("fas_mode", translate("Planned FAS mode"),
	translate("Local level 1 is the selected local-only path."))
readonly("fas_port", translate("Local FAS port"),
	translate("Port 80 remains reserved for the openNDS captive portal."))
readonly("fas_path", translate("FAS path"))
readonly("local_fas_enabled", translate("Local FAS enabled"),
	translate("Activation remains explicit and is disabled during base setup."))

local p = m:section(SimpleSection)
p.template = "cbi/nullsection"
local plan = p:option(DummyValue, "package_plan", translate("Verified package plan"),
	translate("The core package plan does not replace dnsmasq."))
function plan.cfgvalue()
	return table.concat({
		"opennds",
		"sqlite3-cli",
		"php8-cgi",
		"php8-mod-pdo-sqlite",
		"luci-base",
		"luci-compat"
	}, "\n")
end

local note = p:option(DummyValue, "next_step", translate("Next step"))
function note.cfgvalue()
	local state = uci:get("open-hotspot", "global", "setup_state")
	local local_fas = uci:get("open-hotspot", "global", "local_fas_enabled")
	if state == "BASE_READY" and local_fas == "1" then
		return translate("Base and local FAS are active. Complete the disposable-client openNDS validation before handoff.")
	elseif state == "BASE_READY" then
		return translate("Base is ready. Live openNDS/FAS validation is still required before activation.")
	end
	return translate("Resolve the recorded preflight or database blocker first.")
end

return m
