module("luci.controller.open-hotspot", package.seeall)

local http = require("luci.http")
local template = require("luci.template")
local ubus = require("ubus")
local sys = require("luci.sys")
local dispatcher = require("luci.dispatcher")

local BACKUP_EXPORT = "/tmp/open-hotspot-luci-export.tar.gz"
local BACKUP_IMPORT = "/tmp/open-hotspot-luci-import.tar.gz"

local function ubus_call(method, args)
	local connection = ubus.connect(nil, 1000)
	if not connection then
		return nil, "ubus unavailable"
	end
	local result = connection:call("open_hotspot", method, args or {})
	connection:close()
	if type(result) ~= "table" then
		return nil, "management operation failed"
	end
	if result.ok == false then
		return nil, result.error or "management operation failed"
	end
	return result
end

local function csrf_ok()
	local expected = dispatcher.context.authtoken
	if http.formvalue("token") ~= expected then
		http.status(403, "Forbidden")
		http.prepare_content("text/plain")
		http.write("Forbidden")
		return false
	end
	return true
end

local function value(name)
	return http.formvalue(name) or ""
end

local function integer(name, default)
	return tonumber(value(name)) or default
end

local function run_backup(action, path)
	os.remove(path)
	local command = "/usr/lib/open-hotspot/backup.sh " .. action .. " " .. path .. " >/dev/null 2>&1"
	return sys.call(command) == 0
end

local function stream_backup(path)
	local file = io.open(path, "rb")
	if not file then
		return false
	end
	http.header("Content-Disposition", 'attachment; filename="open-hotspot-backup.tar.gz"')
	http.prepare_content("application/gzip")
	while true do
		local chunk = file:read(8192)
		if not chunk then break end
		http.write(chunk)
	end
	file:close()
	os.remove(path)
	return true
end

function profiles()
	local message
	local action = value("action")
	if http.getenv("REQUEST_METHOD") == "POST" then
		if not csrf_ok() then return end
		local args = {
			name = value("name"), period_type = value("period_type"),
			time_limit_s = integer("time_limit_s", 0),
			upload_limit_b = integer("upload_limit_b", 0),
			download_limit_b = integer("download_limit_b", 0),
			upload_rate_kbps = integer("upload_rate_kbps", 0),
			download_rate_kbps = integer("download_rate_kbps", 0),
			max_devices = integer("max_devices", 1)
		}
		local result, err
		if action == "create" then
			result, err = ubus_call("profile_create", args)
		elseif action == "update" then
			args.id = integer("id", 0)
			result, err = ubus_call("profile_update", args)
		elseif action == "delete" then
			result, err = ubus_call("profile_delete", { id = integer("id", 0) })
		else
			err = "unknown action"
		end
		message = err and ("Error: " .. err) or "Saved"
	end
	local result, err = ubus_call("profile_list", {})
	template.render("open-hotspot/profiles", {
		profiles = result and result.profiles or {},
		page_error = err or "",
		page_message = message or "",
		page_url = dispatcher.build_url("admin", "services", "open-hotspot", "profiles"),
		token = dispatcher.context.authtoken
	})
end

function accounts()
	local message
	local action = value("action")
	if http.getenv("REQUEST_METHOD") == "POST" then
		if not csrf_ok() then return end
		local result, err
		if action == "create" then
			result, err = ubus_call("account_create", {
				username = value("username"), profile_id = integer("profile_id", 0),
				expires_at = value("expires_at"), pin = value("pin")
			})
		elseif action == "update" then
			result, err = ubus_call("account_update", {
				id = integer("id", 0), username = value("username"),
				profile_id = integer("profile_id", 0), status = value("status"),
				expires_at = value("expires_at")
			})
		elseif action == "renew" then
			result, err = ubus_call("account_renew", { id = integer("id", 0) })
		elseif action == "set-pin" then
			result, err = ubus_call("account_set_pin", {
				id = integer("id", 0), pin = value("pin")
			})
		elseif action == "delete" then
			result, err = ubus_call("account_delete", { id = integer("id", 0) })
		else
			err = "unknown action"
		end
		message = err and ("Error: " .. err) or "Saved"
	end
	local accounts_result, accounts_error = ubus_call("account_list", {})
	local profiles_result, profiles_error = ubus_call("profile_list", {})
	template.render("open-hotspot/accounts", {
		accounts = accounts_result and accounts_result.accounts or {},
		profiles = profiles_result and profiles_result.profiles or {},
		page_error = accounts_error or profiles_error or "",
		page_message = message or "",
		page_url = dispatcher.build_url("admin", "services", "open-hotspot", "accounts"),
		token = dispatcher.context.authtoken
	})
end

function devices()
	local message
	local action = value("action")
	if http.getenv("REQUEST_METHOD") == "POST" then
		if not csrf_ok() then return end
		local result, err
		local id = integer("id", 0)
		if action == "block" then
			result, err = ubus_call("device_block", { id = id })
			elseif action == "unblock" then
				result, err = ubus_call("device_unblock", { id = id })
			elseif action == "remove" then
				result, err = ubus_call("device_remove", { id = id })
			elseif action == "force-deauth" then
				result, err = ubus_call("device_force_deauth", { id = id })
			elseif action == "reassign" then
				result, err = ubus_call("device_reassign", {
					id = id, target_account_id = integer("target_account_id", 0)
				})
		else
			err = "unknown action"
		end
		message = err and ("Error: " .. err) or "Saved"
	end
	local result, err = ubus_call("device_list", {})
	local accounts_result, accounts_error = ubus_call("account_list", {})
	template.render("open-hotspot/devices", {
		devices = result and result.devices or {},
		accounts = accounts_result and accounts_result.accounts or {},
		page_error = err or accounts_error or "",
		page_message = message or "",
		page_url = dispatcher.build_url("admin", "services", "open-hotspot", "devices"),
		token = dispatcher.context.authtoken
	})
end

function vouchers()
	local message
	local action = value("action")
	if http.getenv("REQUEST_METHOD") == "POST" then
		if not csrf_ok() then return end
		local result, err
		if action == "generate" then
			result, err = ubus_call("voucher_generate", {
				count = integer("count", 1), profile_id = integer("profile_id", 0),
				validity_seconds = integer("validity_seconds", 3600)
			})
			if not err and result and result.codes then
				message = "Generated: " .. table.concat(result.codes, ", ")
			else
				message = err and ("Error: " .. err) or "Generated"
			end
		elseif action == "revoke" then
			result, err = ubus_call("voucher_revoke", { id = integer("id", 0) })
			message = err and ("Error: " .. err) or "Saved"
		else
			message = "Error: unknown action"
		end
	end
	local vouchers_result, vouchers_error = ubus_call("voucher_list", {})
	local profiles_result, profiles_error = ubus_call("profile_list", {})
	template.render("open-hotspot/vouchers", {
		vouchers = vouchers_result and vouchers_result.vouchers or {},
		profiles = profiles_result and profiles_result.profiles or {},
		page_error = vouchers_error or profiles_error or "",
		page_message = message or "",
		page_url = dispatcher.build_url("admin", "services", "open-hotspot", "vouchers"),
		token = dispatcher.context.authtoken
	})
end

function status()
	local result, err = ubus_call("overview", {})
	local account_status, account_status_error = ubus_call("account_status_list", {})
	template.render("open-hotspot/status", {
		overview = result or {},
		account_status = account_status and account_status.account_status or {},
		page_error = err or account_status_error or "",
		page_url = dispatcher.build_url("admin", "services", "open-hotspot", "status")
	})
end

function history()
	local result, err = ubus_call("history_list", {})
	template.render("open-hotspot/history", {
		history = result and result.history or {},
		page_error = err or "",
		page_url = dispatcher.build_url("admin", "services", "open-hotspot", "history")
	})
end

function backup()
	local message
	local action
	local uploaded
	local upload_received = false
	if http.getenv("REQUEST_METHOD") == "POST" then
		http.setfilehandler(function(field, _, content)
			if field == "archive" and content and #content > 0 then
				if not uploaded then
					uploaded = io.open(BACKUP_IMPORT, "wb")
				end
				if uploaded then
					uploaded:write(content)
					upload_received = true
				end
			end
		end)
		action = http.formvalue("action") or ""
		local token = http.formvalue("token") or ""
		if token ~= dispatcher.context.authtoken then
			if uploaded then uploaded:close() end
			os.remove(BACKUP_IMPORT)
			return csrf_ok()
		end
		if uploaded then uploaded:close() end
		if action == "export" then
			if run_backup("export", BACKUP_EXPORT) and stream_backup(BACKUP_EXPORT) then
				return
			end
			message = "Backup export failed"
		elseif action == "validate" or action == "import" then
			local archive = io.open(BACKUP_IMPORT, "rb")
			if archive then archive:close() end
			if not upload_received or not archive then
				message = "Select a backup archive first"
			else
				if action == "validate" then
					message = run_backup("validate", BACKUP_IMPORT) and "Backup is valid" or "Backup validation failed"
				else
					message = run_backup("import", BACKUP_IMPORT) and "Backup imported; reload LuCI" or "Backup import failed"
				end
			end
			os.remove(BACKUP_IMPORT)
		else
			message = "Unknown backup action"
		end
	end
	template.render("open-hotspot/backup", {
		page_error = message or "",
		page_url = dispatcher.build_url("admin", "services", "open-hotspot", "backup"),
		token = dispatcher.context.authtoken
	})
end

function templates()
	local message
	if http.getenv("REQUEST_METHOD") == "POST" then
		if not csrf_ok() then return end
		local _, err = ubus_call("template_apply", { name = value("name") })
		message = err and ("Error: " .. err) or "Saved"
	end
	local result, err = ubus_call("template_list", {})
	template.render("open-hotspot/templates", {
		templates = result and result.templates or {},
		page_error = err or "",
		page_message = message or "",
		page_url = dispatcher.build_url("admin", "services", "open-hotspot", "templates"),
		token = dispatcher.context.authtoken
	})
end

function index()
	if not nixio.fs.access("/etc/config/open-hotspot") then
		return
	end

	local root = entry({"admin", "services", "open-hotspot"}, firstchild(),
		translate("Open-HotSpot"), 60)
	root.dependent = false
	root.acl_depends = { "luci-app-open-hotspot" }

	local setup = entry({"admin", "services", "open-hotspot", "setup"},
		cbi("open-hotspot/setup"), translate("Setup"), 1)
	setup.leaf = true
	setup.acl_depends = { "luci-app-open-hotspot" }

	local profiles = entry({"admin", "services", "open-hotspot", "profiles"},
		call("profiles"), translate("Profiles"), 10)
	profiles.leaf = true
	profiles.acl_depends = { "luci-app-open-hotspot" }

	local accounts = entry({"admin", "services", "open-hotspot", "accounts"},
		call("accounts"), translate("Accounts"), 20)
	accounts.leaf = true
	accounts.acl_depends = { "luci-app-open-hotspot" }

	local devices = entry({"admin", "services", "open-hotspot", "devices"},
		call("devices"), translate("Devices"), 30)
	devices.leaf = true
	devices.acl_depends = { "luci-app-open-hotspot" }

	local vouchers = entry({"admin", "services", "open-hotspot", "vouchers"},
		call("vouchers"), translate("Vouchers"), 40)
	vouchers.leaf = true
	vouchers.acl_depends = { "luci-app-open-hotspot" }

	local status = entry({"admin", "services", "open-hotspot", "status"},
		call("status"), translate("Dashboard"), 5)
	status.leaf = true
	status.acl_depends = { "luci-app-open-hotspot" }

	local history = entry({"admin", "services", "open-hotspot", "history"},
		call("history"), translate("History"), 50)
	history.leaf = true
	history.acl_depends = { "luci-app-open-hotspot" }

	local backup = entry({"admin", "services", "open-hotspot", "backup"},
		call("backup"), translate("Backup"), 55)
	backup.leaf = true
	backup.acl_depends = { "luci-app-open-hotspot" }

	local templates = entry({"admin", "services", "open-hotspot", "templates"},
		call("templates"), translate("Portal templates"), 45)
	templates.leaf = true
	templates.acl_depends = { "luci-app-open-hotspot" }
end
