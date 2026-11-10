local now = 100
copy_table = function(t) local o = {} for k, v in pairs(t) do o[k] = v end return o end
love = {timer = {getTime = function() return now end}, system = {getOS = function() return 'Linux' end}}
G = setmetatable({FUNCS = {}, C = {WHITE = {1,1,1,1}}, CONTROLLER = {}}, {__index = function() return {} end})
local ok, err = pcall(dofile, 'assets/functions/button_callbacks.lua')
if not ok then print('load error', err) end
local fails = 0
local function check(name, cond) if not cond then fails = fails + 1 print('FAIL ' .. name) end end

local function make(rt)
  local text = {ref_table = {v = ''}, ref_value = 'v', letters = {}, current_position = 0}
  for i = 1, rt.max_length do text.letters[i] = '' end
  rt.text = text
  rt.colour = {0,0,0,1}
  G.CONTROLLER.text_input_hook = {config = {ref_table = rt}, parent = {parent = {config = {}}}}
  local pos = 0
  TRANSPOSE_TEXT_INPUT = function(n)
    pos = math.max(0, pos + n)
    text.current_position = pos
    text.ref_table.v = table.concat(text.letters)
  end
  return text
end

local function typed(rt, keys)
  local t = make(rt)
  for _, k in ipairs(keys) do
    if type(k) == 'table' then G.FUNCS.text_input_char(k[1]) else G.FUNCS.text_input_key({key = k, physical = true}) end
  end
  return t.ref_table.v
end

check('ascii', typed({max_length = 16, extended_corpus = true}, {'h', 'i'}) == 'hi')
check('apostrophe', typed({max_length = 16, extended_corpus = true}, {'l', "'", 'a'}) == "l'a")
check('accent textinput', typed({max_length = 16, extended_corpus = true}, {'c', {'é'}, 't'}) == 'cét')
check('dead key no dup', typed({max_length = 16, extended_corpus = true}, {'f', {'ê'}, 'e', 't'}) == 'fêt')
check('enye', typed({max_length = 16, extended_corpus = true}, {{'ñ'}, {'¿'}}) == 'ñ¿')
check('strict room code', typed({max_length = 4, extended_corpus = true, strict_corpus = true}, {'a', "'", {'é'}}) == 'a')
check('plain field', typed({max_length = 8, all_caps = true}, {'a', {'é'}, "'"}) == 'A')
check('max len counts letters', typed({max_length = 3, extended_corpus = true}, {{'é'}, {'é'}, {'é'}, {'é'}}) == 'ééé')
check('no A circumflex', typed({max_length = 3, extended_corpus = true}, {{'Â'}}) == '')
local cs = G.TEXT_INPUT_CHARSET
check('charset sizes', #cs.lower == 23 and #cs.upper == 22)
print(fails == 0 and 'all text input checks pass' or (fails .. ' failed'))
