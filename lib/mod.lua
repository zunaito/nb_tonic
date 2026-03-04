-- nb_tonic v1.0 @sonoCircuit - based on supertonic @infinitedigits (thx zack!)

local tx = require 'textentry'
local mu = require 'musicutil'
local md = require 'core/mods'
local fs = include 'nb_tonic/lib/fs_tonic'


local kit_path = "/home/we/dust/data/nb_tonic/tonic_kits"
local vox_path = "/home/we/dust/data/nb_tonic/tonic_voxs"
local default_kit = "/home/we/dust/data/nb_tonic/tonic_kits/default.tkit"
local failsafe_kit = "/home/we/dust/code/nb_tonic/data/tonic_kits/default.tkit"

local NUM_VOICES = 8

local selected_voice = 1
local base_note = 0
local choke = {1, 2, 3, 4, 5, 5, 6, 6}

local current_kit = ""
local current_vox = {}
for i = 1, NUM_VOICES do
  current_vox[i] = ""
end

local voice_params = {
  "level", "pan", "dist", "send_a", "send_b", "eq_freq", "eq_gain", "mix",
  "osc_wav", "osc_freq", "mod_mode", "mod_amt", "mod_rate", "osc_attack", "osc_decay",
  "noise_mode", "noise_freq", "noise_q", "noise_env", "noise_attack", "noise_decay", "noise_stereo",
  "osc_vel", "mod_vel", "noise_vel", "choke_group"
}


---------------- osc msgs ----------------

local function init_nb_tonic()
  osc.send({'localhost', 57120}, '/nb_tonic/init')
end

local function trig_tonic(vox, vel)
  local chk = choke[vox + 1]
  osc.send({'localhost', 57120}, '/nb_tonic/trig', {vox, vel, chk})
end

local function set_param(i, key, val)
  local vox = i - 1
  osc.send({'localhost', 57120}, '/nb_tonic/set_param', {vox, key, val})
end

local function set_main_amp(val)
  osc.send({'localhost', 57120}, '/nb_tonic/set_main_amp', {val})
end

local function set_cutoff(val)
  osc.send({'localhost', 57120}, '/nb_tonic/set_cutoff', {val})
end

local function set_resonance(val)
  osc.send({'localhost', 57120}, '/nb_tonic/set_resonance', {val})
end


---------------- utils ----------------

local function round_form(param, quant, form)
  return(util.round(param, quant)..form)
end

local function pan_display(param)
  if param < -0.01 then
    return ("L < "..math.abs(util.round(param * 100, 1)))
  elseif param > 0.01 then
    return (math.abs(util.round(param * 100, 1)).." > R")
  else
    return "> <"
  end
end

local function mix_display(param)
  local tone = util.round(util.linlin(-1, 1, 100, 0, param), 1)
  local noise = util.round(util.linlin(-1, 1, 0, 100, param), 1)
  return tone.."/"..noise
end

local function build_menu()
  for i = 1, NUM_VOICES do
    for _,v in ipairs(voice_params) do
      local name = "nb_tonic_"..v.."_"..i
      if i == selected_voice then
        params:show(name)
        if not md.is_loaded("fx") then
          params:hide("nb_tonic_send_a_"..i)
          params:hide("nb_tonic_send_b_"..i)
        end
      else
        params:hide(name)
      end
    end
  end
  _menu.rebuild_params()
end

---------------- save load ----------------

local function save_kit(txt)
  if txt then
    local kit = {}
    for n = 1, NUM_VOICES do
      kit[n] = {}
      for _, v in ipairs(voice_params) do
        kit[n][v] = params:get("nb_tonic_"..v.."_"..n)
      end
    end
    tab.save(kit, kit_path.."/"..txt..".tkit")
    current_kit = txt
    print("saved tonic kit: "..txt)
  end
end

local function load_kit(path)
  if path ~= "cancel" and path ~= "" then
    if path:match("^.+(%..+)$") == ".tkit" then
      local kit = tab.load(path)
      if next(kit) then
        for n = 1, NUM_VOICES do
          for _, v in ipairs(voice_params) do
            if kit[n][v] ~= nil then
              params:set("nb_tonic_"..v.."_"..n, kit[n][v])
            end
          end
        end
        current_kit = path:match("[^/]*$"):gsub(".tkit", "")
        print("loaded tonic kit: "..current_kit)
      else
        if util.file_exists(failsafe_kit) then
          load_synth_patch(failsafe_kit)
        end
        print("error: could not find tonic kit", path)
      end
    else
      print("error: not a tonic kit file")
    end
  end
end

local function save_voice(txt)
  if txt then
    local t = {}
    for _, v in ipairs(voice_params) do
      t[v] = params:get("nb_tonic_"..v.."_"..selected_voice)
    end
    tab.save(t, vox_path.."/"..txt..".tvox")
    print("saved tonic vox: "..txt)
  end
end

local function load_voice(path)
  if path ~= "cancel" and path ~= "" then
    if path:match("^.+(%..+)$") == ".tvox" then
      local t = tab.load(path)
      if t ~= nil then
        for i, v in ipairs(voice_params) do
          if t[v] ~= nil then
            params:set("nb_tonic_"..v.."_"..selected_voice, t[v])
          end
        end
        current_vox[selected_voice] = path:match("[^/]*$"):gsub(".tvox", "")
        print("loaded tonic vox: "..current_vox[selected_voice])
      else
        print("error: could not find tonic vox", path)
      end
    else
      print("error: not a tonic vox file")
    end
  end
end

---------------- params ----------------

local function add_params()
  params:add_group("nb_tonic_group", "tonic", ((NUM_VOICES * 26) + 18))
  params:hide("nb_tonic_group")
  
  params:add_separator("nb_tonic_kits", "tonic kit")

  params:add_trigger("nb_tonic_load_kit", ">> load")
  params:set_action("nb_tonic_load_kit", function() fs.enter(kit_path, load_kit) end)

  params:add_trigger("nb_tonic_save_kit", "<< save")
  params:set_action("nb_tonic_save_kit", function() tx.enter(save_kit, current_kit)  end)
   
  params:add_separator("nb_tonic_settings", "settings")

  params:add_control("nb_tonic_global_level", "main level", controlspec.new(0, 1, "lin", 0, 1), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_tonic_global_level", function(val) set_main_amp(val) end)

  params:add_number("nb_tonic_base", "base note", 0, 11, 0, function(param) return mu.note_num_to_name(param:get(), false) end)
  params:set_action("nb_tonic_base", function(val) base_note = val end)

  params:add_separator("nb_tonic_filter", "global lpf")

  params:add_control("nb_tonic_global_cutoff", "cutoff", controlspec.new(20, 20000, "exp", 0, 20000), function(param) return round_form(param:get(), 1, "hz") end)
  params:set_action("nb_tonic_global_cutoff", function(val) set_cutoff(val) end)
  
  params:add_control("nb_tonic_global_resonance", "resonance", controlspec.new(0, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_tonic_global_resonance", function(val) set_resonance(val) end)

  params:add_separator("nb_tonic_voice", "voice")

  params:add_number("nb_tonic_selected_voice", "selected voice", 1, NUM_VOICES, 1)
  params:set_action("nb_tonic_selected_voice", function(n) selected_voice = n build_menu() end)

  for i = 1, NUM_VOICES do
    params:add_number("nb_tonic_choke_group_"..i, "choke group", 1, 6, choke[i])
    params:set_action("nb_tonic_choke_group_"..i, function(val) choke[i] = val - 1 end)
  end

  params:add_trigger("nb_tonic_trig", "trig voice >>")
  params:set_action("nb_tonic_trig", function() trig_tonic(selected_voice - 1, 1) end)

  params:add_trigger("nb_tonic_load_voice", "> load voice")
  params:set_action("nb_tonic_load_voice", function() fs.enter(vox_path, load_voice) end)

  params:add_trigger("nb_tonic_save_voice", "< save voice")
  params:set_action("nb_tonic_save_voice", function() tx.enter(save_voice, current_vox[selected_voice]) end)
  
  params:add_separator("nb_tonic_level_params", "levels")
  for i = 1, NUM_VOICES do
    params:add_control("nb_tonic_level_"..i, "level", controlspec.new(0, 2, "lin", 0, 1), function(param) return round_form(param:get() * 100, 1, "%") end)
    params:set_action("nb_tonic_level_"..i, function(val) set_param(i, 'level', val)  end)

    params:add_control("nb_tonic_pan_"..i, "pan", controlspec.new(-1, 1, "lin", 0, 0, "", 1/200), function(param) return pan_display(param:get()) end)
    params:set_action("nb_tonic_pan_"..i, function(val) set_param(i, 'pan', val)  end)

    params:add_control("nb_tonic_dist_"..i, "distortion", controlspec.new(0, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
    params:set_action("nb_tonic_dist_"..i, function(val) set_param(i, 'dist', val) end)

    params:add_control("nb_tonic_send_a_"..i, "send a", controlspec.new(0, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
    params:set_action("nb_tonic_send_a_"..i, function(val) set_param(i, 'send_a', val) end)

    params:add_control("nb_tonic_send_b_"..i, "send b", controlspec.new(0, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
    params:set_action("nb_tonic_send_b_"..i, function(val) set_param(i, 'send_b', val) end)
    
    params:add_control("nb_tonic_eq_freq_"..i, "eq freq", controlspec.new(20, 20000, "exp", 0, 1000), function(param) return round_form(param:get(), 1, "hz") end)
    params:set_action("nb_tonic_eq_freq_"..i, function(val) set_param(i, 'eq_freq', val) end)

    params:add_control("nb_tonic_eq_gain_"..i, "eq gain", controlspec.new(-20, 20, "lin", 0, 0, "", 1/400), function(param) return round_form(param:get(), 0.1, "dB") end)
    params:set_action("nb_tonic_eq_gain_"..i, function(val) set_param(i, 'eq_gain', val) end)

    params:add_control("nb_tonic_mix_"..i, "mix [tone/noise]", controlspec.new(-1, 1, "lin", 0, -0.8), function(param) return mix_display(param:get()) end)
    params:set_action("nb_tonic_mix_"..i, function(val) set_param(i, 'mix', val) end)
  end

  params:add_separator("nb_tonic_tone_params", "tone")
  for i = 1, NUM_VOICES do
    params:add_option("nb_tonic_osc_wav_"..i, "waveform", {"sine", "tri", "saw"}, 1)
    params:set_action("nb_tonic_osc_wav_"..i, function(val) set_param(i, 'osc_wav', val)  end)

    params:add_control("nb_tonic_osc_freq_"..i, "freq", controlspec.new(20, 20000, "exp", 0, 1000), function(param) return round_form(param:get(), 1, "hz") end)
    params:set_action("nb_tonic_osc_freq_"..i, function(val) set_param(i, 'osc_freq', val) end)

    params:add_option("nb_tonic_mod_mode_"..i, "mod mode", {"decay", "sine", "random"}, 1)
    params:set_action("nb_tonic_mod_mode_"..i, function(val) set_param(i, 'mod_mode', val)  end)

    params:add_number("nb_tonic_mod_amt_"..i, "mod amt", -96, 96, 0, function(param) return  (param:get() < 0 and "" or "+")..param:get().."st" end)
    params:set_action("nb_tonic_mod_amt_"..i, function(val) set_param(i, 'mod_amt', val)  end)

    params:add_control("nb_tonic_mod_rate_"..i, "mod rate", controlspec.new(0.1, 20000, "exp", 0, 17), function(param) return round_form(param:get(), 0.1, "hz") end)
    params:set_action("nb_tonic_mod_rate_"..i, function(val) set_param(i, 'mod_rate', val) end)

    params:add_control("nb_tonic_osc_attack_"..i, "attack", controlspec.new(0, 10, "lin", 0, 0, "", 1/1000), function(param) return round_form(param:get() * 1000, 1, "ms") end)
    params:set_action("nb_tonic_osc_attack_"..i, function(val) set_param(i, 'osc_attack', val) end)

    params:add_control("nb_tonic_osc_decay_"..i, "decay", controlspec.new(0, 10, "lin", 0, 0.32, "", 1/1000), function(param) return round_form(param:get() * 1000, 1, "ms") end)
    params:set_action("nb_tonic_osc_decay_"..i, function(val) set_param(i, 'osc_decay', val) end)
  end
  
  params:add_separator("nb_tonic_noise_params", "noise")
  for i = 1, NUM_VOICES do
    params:add_control("nb_tonic_noise_freq_"..i, "freq", controlspec.new(20, 20000, "exp", 0, 1000), function(param) return round_form(param:get(), 1, "hz") end)
    params:set_action("nb_tonic_noise_freq_"..i, function(val) set_param(i, 'noise_freq', val) end)

    params:add_control("nb_tonic_noise_q_"..i, "filter q", controlspec.new(0.1, 10000, "exp", 0, 0.7), function(param) return round_form(param:get(), 0.1, "") end)
    params:set_action("nb_tonic_noise_q_"..i, function(val) set_param(i, 'noise_q', val) end)

    params:add_option("nb_tonic_noise_mode_"..i, "filter mode", {"lp", "bp", "hp"}, 1)
    params:set_action("nb_tonic_noise_mode_"..i, function(val) set_param(i, 'noise_mode', val)  end)

    params:add_option("nb_tonic_noise_env_"..i, "env mode", {"exp", "lin", "mod"}, 1)
    params:set_action("nb_tonic_noise_env_"..i, function(val) set_param(i, 'noise_env', val)  end)
    
    params:add_control("nb_tonic_noise_attack_"..i, "attack", controlspec.new(0, 10, "lin", 0, 0, "", 1/1000), function(param) return round_form(param:get() * 1000, 1, "ms") end)
    params:set_action("nb_tonic_noise_attack_"..i, function(val) set_param(i, 'noise_attack', val) end)

    params:add_control("nb_tonic_noise_decay_"..i, "decay", controlspec.new(0, 10, "lin", 0, 0.32, "", 1/1000), function(param) return round_form(param:get() * 1000, 1, "ms") end)
    params:set_action("nb_tonic_noise_decay_"..i, function(val) set_param(i, 'noise_decay', val) end)
    
    params:add_option("nb_tonic_noise_stereo_"..i, "stereo", {"off", "on"}, 2)
    params:set_action("nb_tonic_noise_stereo_"..i, function(val) set_param(i, 'noise_stereo', val)  end)
  end
  
  params:add_separator("nb_tonic_velocity_params", "velocity")
  for i = 1, NUM_VOICES do
    params:add_control("nb_tonic_osc_vel_"..i, "osc velocity", controlspec.new(0, 1, "lin", 0, 1), function(param) return round_form(param:get() * 100, 1, "%") end)
    params:set_action("nb_tonic_osc_vel_"..i, function(val) set_param(i, 'osc_vel', val)  end)

    params:add_control("nb_tonic_mod_vel_"..i, "mod velocity", controlspec.new(0, 1, "lin", 0, 1), function(param) return round_form(param:get() * 100, 1, "%") end)
    params:set_action("nb_tonic_mod_vel_"..i, function(val) set_param(i, 'mod_vel', val)  end)

    params:add_control("nb_tonic_noise_vel_"..i, "noise velocity", controlspec.new(0, 1, "lin", 0, 1), function(param) return round_form(param:get() * 100, 1, "%") end)
    params:set_action("nb_tonic_noise_vel_"..i, function(val) set_param(i, 'noise_vel', val)  end)
  end
  -- load default kit after params
  clock.run(function()
    clock.sleep(0.1)
    load_kit(default_kit)
  end)
end

---------------- nb player ----------------

function add_nb_tonic_player()
  local player = {}

  function player:describe()
    return {
      name = "tonic",
      supports_bend = false,
      supports_slew = false
    }
  end
  
  function player:active()
    if self.name ~= nil then
      params:show("nb_tonic_group")
      build_menu()
    end
  end

  function player:inactive()
    if self.name ~= nil then
      params:hide("nb_tonic_group")
      _menu.rebuild_params()
    end
  end

  function player:stop_all()
  end

  function player:modulate(val)
  end

  function player:set_slew(s)
  end

  function player:pitch_bend(note, val)
  end

  function player:modulate_note(note, key, value)
  end

  function player:note_on(note, vel)
    local vox = ((note % 12) - base_note) % NUM_VOICES
    trig_tonic(vox, vel)
  end

  function player:note_off(note)
  end

  function player:add_params()
    add_params()
  end

  if note_players == nil then
    note_players = {}
  end

  note_players["tonic"] = player
end


---------------- mod zone ----------------

local function post_system()
  if util.file_exists(kit_path) == false then
    util.make_dir(kit_path)
    util.make_dir(vox_path)
    os.execute('cp '.. '/home/we/dust/code/nb_tonic/data/tonic_kits/*.tkit '.. kit_path)
    os.execute('cp '.. '/home/we/dust/code/nb_tonic/data/tonic_voxs/*.tvox '.. vox_path)
  end
end

local function pre_init()
  init_nb_tonic()
  add_nb_tonic_player()
end

md.hook.register("system_post_startup", "nb tonic post startup", post_system)
md.hook.register("script_pre_init", "nb tonic pre init", pre_init)
