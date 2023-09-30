function log(t)
  reaper.ShowConsoleMsg(t .. '\n')
end
function logtable(table)
  log(tostring(table))
  for index, value in pairs(table) do -- print table
    log('    ' .. tostring(index) .. ' : ' .. tostring(value))
  end
end

globals = {
  win_x = nil,
  win_y = nil,
  win_w = 768,
  win_h = 553,
  key_h = 30,
  key_w = 6,
  region_h = 254
}
g = globals

-- init globals from project config
local exists, win_x = reaper.GetProjExtState(0, 'rs5kmapper', 'win_x')
if exists ~= 0 then globals.win_x = tonumber(win_x) end
local exists, win_y = reaper.GetProjExtState(0, 'rs5kmapper', 'win_y')
if exists ~= 0 then globals.win_y = tonumber(win_y) end

sel_key = nil
regions = {
  {30, 50, 0, 127}
}

function draw_keyboard()
  function draw_key (x, y, w, h, black_key)
    if black_key then
      gfx.set(0, 0, 0)
      gfx.rect(x, y, w, h, 1)
    else
      gfx.set(1, 1, 1)
      gfx.rect(x, y, w, h, 1)
      -- gfx.set(0,0,0, 1)
      -- gfx.rect(x, y, w, h, 0)
    end
  end
  for i=0, 127 do
    local pitch = i % 12
    local is_black_key = pitch == 1 or pitch == 3 or pitch == 6 or pitch == 8 or pitch == 10
    draw_key(i * globals.key_w, globals.win_h - globals.key_h, globals.key_w, globals.key_h, is_black_key)
  end
end

function draw_selected_key()
  local nkey = math.floor(rtk.mouse.x / globals.key_w)
  sel_key = nkey
  gfx.set(1, 0, 0, 1)
  gfx.rect(nkey * g.key_w, g.win_h - g.key_h, g.key_w, g.key_h)
end

function draw_guides()
  for i=0, 127, 12 do
    gfx.set(1, 1, 1, .25)
    gfx.line(i * g.key_w, g.win_h - g.region_h - g.key_h, i*g.key_w, g.win_h - g.key_h)
    gfx.x = i * g.key_w + 5
    gfx.y = g.win_h - g.key_h - g.region_h
    gfx.drawstr('C'..(math.floor(i/12) - 1))
  end
end

function draw_regions()
  local vel_h = g.region_h / 127
  for i, reg in ipairs(regions) do
    gfx.set(0, 1, 1, 0.25)
    local left = reg[1] * g.key_w
    local top = globals.win_h - (reg[4] * vel_h + g.key_h)
    local width = (reg[2] - reg[1]) * g.key_w + g.key_w
    local height = (reg[4] - reg[3]) * vel_h + vel_h
    gfx.rect(left, top, width, height, 1)
  end
end

function draw()
  draw_keyboard()
  draw_selected_key()
  draw_guides()
  draw_regions()
  text:attr('text', 'Key ' .. sel_key)
end

function init()
  local sep = package.config:sub(1, 1)
  local script_folder = debug.getinfo(1).source:match("@?(.*[\\|/])")
  rtk = dofile(script_folder .. 'tilr_RS5K Mapper' .. sep .. 'rtk.lua')
  window = rtk.Window{ w=globals.win_w, h=globals.win_h, title='RS5K Mapper'}
  window.onmove = function (self)
    reaper.SetProjExtState(0, 'rs5kmapper', 'win_x', self.x)
    reaper.SetProjExtState(0, 'rs5kmapper', 'win_y', self.y)
  end
  window.onupdate = function ()
    window:queue_draw()
  end
  window.ondraw = draw

  local box = window:add(rtk.VBox{})
  text = box:add(rtk.Text{'Apply '})

  window:open{align='center'}
  if globals.win_x and globals.win_y then
    window:attr('x', globals.win_x)
    window:attr('y', globals.win_y)
  end

end

init()