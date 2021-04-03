local obs = obslua;
local var = {}


--
-- Helpers
--

local info = function(msg) 
    obs.script_log(obs.LOG_INFO, "INFO: "..msg)
end

local warn = function(msg) 
    obs.script_log(obs.LOG_WARNING, "WARNING: "..msg)
end

local split = function(s, sep)
    local fields = {}
    
    local sep = sep or " "
    local pattern = string.format("([^%s]+)", sep)
    string.gsub(s, pattern, function(c) fields[#fields + 1] = c end)
    
    return fields
end

--
-- Code
--

local start_recording_timerproc = function()
    obs.remove_current_callback()
    obs.obs_frontend_recording_start()
    info("RECORDING STARTED")
end

local stop_recording_timerproc = function() 
    obs.remove_current_callback()
    obs.obs_frontend_recording_stop()
    info ("RECORDING STOPPED")
end


local check_for_active_sources = function() 
    if not (var.sources_count > 0) or var.enabled == false then
        return
    end

    local source_active = false
    for i,s in ipairs(var.sources) do
        if var.sources[s] == true then
            source_active = true
            break
        end
    end

    if var.source_active ~= source_active then
        obs.timer_remove(start_recording_timerproc)
        obs.timer_remove(stop_recording_timerproc)

        if source_active then -- begin recording
            if (var.start_timer > 0) then
                info("Recording timer started. ("..var.start_timer.."s)")
            else
                start_recording_timerproc()
            end
            obs.timer_add(start_recording_timerproc, var.start_timer * 1000)
        elseif var.source_active ~= nil then -- stop recording
            if (var.stop_timeout > 0) then
                info("There are no sources active. Recording will stop in "..var.stop_timeout.."s")
            else
                stop_recording_timerproc()
            end
            obs.timer_add(stop_recording_timerproc, var.stop_timeout * 1000)
        end

        var.source_active = source_active
    end
end

--
-- handlers
--

local on_source_activated = function(cd)
    local src = obs.calldata_source(cd, "source")
    if src == nil then
        warn("Source activated but calldata is nil")
        return
    end

    local name = obs.obs_source_get_name(src)
    if var.sources[name] ~= nil then
        info("Source activated: "..name)
        var.sources[name] = true
    end

    check_for_active_sources()
end

local on_source_deactivated = function(cd) 
    local src = obs.calldata_source(cd, "source")
    if src == nil then
        warn("Source deactivated but calldata is nil")
        return
    end

    local name = obs.obs_source_get_name(src)
    if var.sources[name] ~= nil then 
        info("Source deactivated: "..name)
        var.sources[name] = false
    end

    check_for_active_sources()
end

--
-- Script setup
--

function script_description()
    return "Automatically begin recording when a source is activated, and stop recording when the source is deactivated after a specified timeout"
end

function script_properties() 
    local props = obs.obs_properties_create()
    obs.obs_properties_add_bool(props, "enabled", "Enabled")
    obs.obs_properties_add_text(props, "source_list", "Sources", obs.OBS_TEXT_MULTILINE)
    obs.obs_properties_add_int(props, "start_timer", "Start timer (sec)", 0, 100000, 1)
    obs.obs_properties_add_int(props, "stop_timeout", "Stop timeout (sec)", 0, 100000, 1)

    return props
end

function script_defaults(settings)
    obs.obs_data_set_default_int(settings, "stop_timeout", 10)
    obs.obs_data_set_default_bool(settings, "enabled", true)
end

function script_update(settings) 
    var.enabled = obs.obs_data_get_bool(settings, "enabled")
    var.stop_timeout = obs.obs_data_get_int(settings, "stop_timeout")
    var.start_timer = obs.obs_data_get_int(settings, "start_timer")
    var.sources = split(obs.obs_data_get_string(settings, "source_list"), "\n")

    info("Settings changed")
    info("Stop timeout: "..var.stop_timeout..". Start timer: "..var.start_timer)

    local sources_count = 0
    info("Sources:")
    for i, s in ipairs(var.sources) do
        var.sources[s] = false
        info(s)
        sources_count = sources_count + 1
    end

    if not (sources_count > 0) then info("<No sources specified>") end
    var.sources_count = sources_count

    local enable_str
    if var.enabled then enable_str = "ENABLED" else enable_str = "DISABLED" end
    info("Currently "..enable_str)

    check_for_active_sources()
end

function script_load(settings)
    local sh = obs.obs_get_signal_handler()
    obs.signal_handler_connect(sh, "source_activate", on_source_activated)
    obs.signal_handler_connect(sh, "source_deactivate", on_source_deactivated)
end