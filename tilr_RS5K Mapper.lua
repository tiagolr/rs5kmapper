function log(t)
  reaper.ShowConsoleMsg(t .. '\n')
end
function logtable(table)
  log(tostring(table))
  for index, value in pairs(table) do -- print table
    log('    ' .. tostring(index) .. ' : ' .. tostring(value))
  end
end
function clone_table(table)
  local copy = {}
  for key, val in pairs(table) do
    copy[key] = val
  end
  return copy
end

local sep = package.config:sub(1, 1)
local script_folder = debug.getinfo(1).source:match("@?(.*[\\|/])")
rtk = dofile(script_folder .. 'tilr_RS5K Mapper' .. sep .. 'rtk.lua')

_notes = {'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'}
notes = {}
for i = 0, 127 do
  notes[i+1] = _notes[i % 12 + 1] .. (math.floor(i/12) - 1)
end

globals = {
  win_x = nil,
  win_y = nil,
  win_w = 768,
  win_h = 553,
  key_h = 30,
  key_w = 6,
  region_h = 254,
  vel_h = 2,
  drag_margin = 10,
}
g = globals

-- init globals from project config
local exists, win_x = reaper.GetProjExtState(0, 'rs5kmapper', 'win_x')
if exists ~= 0 then globals.win_x = tonumber(win_x) end
local exists, win_y = reaper.GetProjExtState(0, 'rs5kmapper', 'win_y')
if exists ~= 0 then globals.win_y = tonumber(win_y) end

sel_key = nil
regions = {}
mouse = {
  down = false,
  toggled = false,
  drag = {
    active = false,
    start_x = 0,
    start_y = 0,
    region = nil,
    margin = nil,
  }
}

function make_region(keymin, keymax, velmin, velmax)
  return {
    id = rtk.uuid4(),
    keymin = keymin,
    keymax = keymax,
    velmin = velmin,
    velmax = velmax,
    pitch = 0,
    x = keymin * g.key_w,
    y = g.win_h - (velmax * g.vel_h + g.key_h),
    w = (keymax - keymin) * g.key_w + g.key_w,
    h = (velmax - velmin) * g.vel_h + g.vel_h,
    hover = false,
    selected = false,
    track = 0,
    fxid = '',
    file = '',
  }
end

table.insert(regions, make_region(30, 50, 0, 127))
table.insert(regions, make_region(70, 90, 0, 127))

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

function draw_pitch_key()
  -- local nkey = math.floor(rtk.mouse.x / globals.key_w)
  -- sel_key = nkey
  -- gfx.set(1, 0, 0, 1)
  -- gfx.rect(nkey * g.key_w, g.win_h - g.key_h, g.key_w, g.key_h)
  for _, reg in ipairs(regions) do
    if reg.selected then
      gfx.set(1, .5, 0, 1)
      key = reg.keymin - reg.pitch
      if key < 0 or key > 127 then
        return
      end
      gfx.rect(key * g.key_w, g.win_h - g.key_h, g.key_w, g.key_h)
    end
  end
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
  local helper_w = 6
  for _, reg in ipairs(regions) do
    gfx.set(0, 1, 1, reg.selected and 0.5 or 0.25)
    gfx.rect(reg.x, reg.y, reg.w, reg.h, 1)
    gfx.set(0, 1, 1, (reg.hover or reg.selected) and 0.75 or 0.5)
    gfx.rect(reg.x, reg.y, reg.w, reg.h, 0)
    if reg.hover then -- draw drag helpers
      gfx.rect(reg.x, reg.y + reg.h / 2 - helper_w / 2, helper_w, helper_w, 1) -- left
      gfx.rect(reg.x + reg.w - helper_w, reg.y + reg.h / 2 - helper_w / 2, helper_w, helper_w, 1) -- right
      gfx.rect(reg.x + reg.w / 2 - helper_w / 2, reg.y, helper_w, helper_w, 1) -- top
      gfx.rect(reg.x + reg.w / 2 - helper_w / 2, reg.y + reg.h - helper_w, helper_w, helper_w, 1) -- bottom
    end
  end
end

-- recalc regions after window resize
function recalc_regions ()
  for _, reg in ipairs(regions) do
    rr = make_region(reg.keymin, reg.keymax, reg.velmin, reg.velmax)
    reg.x = rr.x
    reg.y = rr.y
    reg.w = rr.w
    reg.h = rr.h
  end
end

function select_region(reg)
  local index = -1
  for i,r in ipairs(regions) do
    r.selected = r == reg
    if r.selected then index = i end
  end
  if index > -1 then -- move region to top of the list
    table.remove(regions, index)
    table.insert(regions, reg)
  end
end

function start_drag(region, margin)
  mouse.drag.active = true
  mouse.drag.region = clone_table(region) -- region copy
  mouse.drag.start_x = rtk.mouse.x
  mouse.drag.start_y = rtk.mouse.y
  mouse.drag.margin = margin
end

function stop_drag()
  mouse.drag.active = false
  mouse.drag.region = nil
  mouse.drag.margin = nil
end

function update_drag()
  if not mouse.drag.active then return end
  local reg = mouse.drag.region
  local delta_x = rtk.mouse.x - mouse.drag.start_x
  local delta_y = rtk.mouse.y - mouse.drag.start_y
  local keymin = mouse.drag.region.keymin
  local keymax = mouse.drag.region.keymax
  local velmin = mouse.drag.region.velmin
  local velmax = mouse.drag.region.velmax
  if mouse.drag.margin == 'left' then
    keymin = mouse.drag.region.keymin + math.floor(delta_x / g.key_w)
  elseif mouse.drag.margin == 'right' then
    keymax = mouse.drag.region.keymax + math.floor(delta_x / g.key_w)
  elseif mouse.drag.margin == 'top' then
    velmax = velmax - math.floor(delta_y / g.vel_h)
  elseif mouse.drag.margin == 'bottom' then
    velmin = velmin - math.floor(delta_y / g.vel_h)
  else
    keymin = keymin + math.floor(delta_x / g.key_w)
    keymax = keymax + math.floor(delta_x / g.key_w)
    velmin = velmin - math.floor(delta_y / g.vel_h)
    velmax = velmax - math.floor(delta_y / g.vel_h)
  end
  if keymin > keymax then
    local tmp = keymin
    keymin = keymax
    keymax = tmp
  end
  if velmin > velmax then
    local tmp = velmin
    velmin = velmax
    velmax = tmp
  end
  if keymin < 0 then -- fix out of bounds drag
    if not mouse.drag.margin then keymax = keymax - keymin end
    keymin = 0
  end
  if keymax > 127 then -- fix out of bounds drag
    if not mouse.drag.margin then keymin = keymin + 127 - keymax end
    keymax = 127
  end
  if velmin < 0 then --
    if not mouse.drag.margin then velmax = velmax - velmin end
    velmin = 0
  end
  if velmax > 127 then --
    if not mouse.drag.margin then velmin = velmin + 127 - velmax end
    velmax = 127
  end
  local newreg = make_region(keymin, keymax, velmin, velmax)
  for _, rr in ipairs(regions) do
    if rr.id == reg.id then
        rr.keymin = newreg.keymin
        rr.keymax = newreg.keymax
        rr.x = newreg.x
        rr.w = newreg.w
        rr.velmin = newreg.velmin
        rr.velmax = newreg.velmax
        rr.y = newreg.y
        rr.h = newreg.h
    end
  end
end

function update_mouse()
  if rtk.mouse.down == 1 then
    if not mouse.down then
      mouse.toggled = true
    end
    mouse.down = true
  else
    mouse.down = false
  end
  local hover_margin = nil
  local hover = false
  local selected = false
  if mouse.drag.active then
    goto continue
  end
  for i = #regions, 1, -1 do
    local reg = regions[i]
		reg.hover = false
    if not hover and rtk.point_in_box(rtk.mouse.x, rtk.mouse.y, reg.x, reg.y, reg.w, reg.h) then -- mouse in region
      reg.hover = true
      hover = true
      if not selected and mouse.toggled then
        selected = reg
      end
      if rtk.point_in_box(rtk.mouse.x, rtk.mouse.y, reg.x, reg.y + reg.h / 2 - g.drag_margin / 2, g.drag_margin, g.drag_margin) then -- mouse in left drag
        hover_margin = 'left'
      elseif rtk.point_in_box(rtk.mouse.x, rtk.mouse.y, reg.x + reg.w - g.drag_margin, reg.y + reg.h / 2 - g.drag_margin / 2, g.drag_margin, g.drag_margin) then -- mouse in right drag
        hover_margin = 'right'
      elseif rtk.point_in_box(rtk.mouse.x, rtk.mouse.y, reg.x + reg.w / 2 - g.drag_margin / 2, reg.y, g.drag_margin, g.drag_margin) then -- mouse in top drag
        hover_margin = 'top'
      elseif rtk.point_in_box(rtk.mouse.x, rtk.mouse.y, reg.x + reg.w / 2 - g.drag_margin / 2, reg.y + reg.h - g.drag_margin, g.drag_margin, g.drag_margin) then -- mouse in bottom drag
        hover_margin = 'bottom'
      end
    end
	end
  ::continue::
  if selected then
    select_region(selected)
    start_drag(selected, hover_margin)
  end
  if not hover and not mouse.drag.margin then
    window:request_mouse_cursor(rtk.mouse.cursors.POINTER)
  end
  if mouse.drag.margin or hover_margin then -- if its dragging margins or hovering drag margins draw cursor
    if mouse.drag.margin == 'left' or hover_margin == 'left' or mouse.drag.margin == 'right' or hover_margin == 'right' then
      window:request_mouse_cursor(rtk.mouse.cursors.SIZE_EW)
    elseif mouse.drag.margin == 'top' or hover_margin == 'top' or mouse.drag.margin == 'bottom' or hover_margin == 'bottom' then
      window:request_mouse_cursor(rtk.mouse.cursors.SIZE_NS)
    end
  end
  if mouse.drag.active and not mouse.down then
    stop_drag()
  end
  if not selected and mouse.toggled and rtk.point_in_box(rtk.mouse.x, rtk.mouse.y, 0, g.win_h - g.region_h - g.key_h, g.win_w, g.win_h) then -- mouse in regions area
    select_region(nil)
  end
end

function draw()
  -- after x milliseconds if not dragging
  --  fetch_regions()
  update_mouse()
  update_drag()
  draw_keyboard()
  draw_pitch_key()
  draw_guides()
  draw_regions()
  draw_ui()
  mouse.toggled = false
end

function draw_ui()
  local sel_region
  for _, reg in ipairs(regions) do
    if reg.selected then sel_region = reg end
  end
  if not sel_region then
    ui_hbox:attr('visible', false)
    ui_helpbox:attr('visible', true)
  else
    ui_hbox:attr('visible', true)
    ui_helpbox:attr('visible', false)
    ui_note_start:attr('text', sel_region.keymin .. ' ' .. notes[sel_region.keymin + 1])
    ui_note_end:attr('text', sel_region.keymax .. ' ' .. notes[sel_region.keymax + 1])
    ui_vel_min:attr('text', sel_region.velmin)
    ui_vel_max:attr('text', sel_region.velmax)
    ui_pitch:attr('text', sel_region.pitch .. ' ' .. (notes[sel_region.keymin - sel_region.pitch + 1] or ''))
  end
end

function init()
  window = rtk.Window{ w=globals.win_w, h=globals.win_h, title='RS5K Mapper'}
  window.onmove = function (self)
    reaper.SetProjExtState(0, 'rs5kmapper', 'win_x', self.x)
    reaper.SetProjExtState(0, 'rs5kmapper', 'win_y', self.y)
  end
  window.onupdate = function ()
    window:queue_draw()
  end
  window.ondraw = draw

  window.onresize = function ()
    globals.win_w = window.w
    globals.win_h = window.h
    globals.key_w = window.w / 128
    recalc_regions()
  end

  ui_vbox = window:add(rtk.VBox{ padding=10, spacing=10 })
  ui_hbox = ui_vbox:add(rtk.HBox{ spacing=10 })
  ui_hbox:add(rtk.Text{'Vel min'})
  ui_vel_min = ui_hbox:add(rtk.Text{'', w=40 })
  ui_hbox:add(rtk.Text{'Vel max'})
  ui_vel_max = ui_hbox:add(rtk.Text{'', w=40 })
  ui_hbox:add(rtk.Text{'Note start'})
  ui_note_start = ui_hbox:add(rtk.Text{'', w=60 })
  ui_hbox:add(rtk.Text{'Note end'})
  ui_note_end = ui_hbox:add(rtk.Text{'', w=60 })
  ui_hbox:add(rtk.Text{'Pitch'})
  ui_pitch = ui_hbox:add(rtk.Text{'', w=60})

  ui_helpbox = ui_vbox:add(rtk.Text{'No region selected', visible=false})

  window:open{align='center'}
  if globals.win_x and globals.win_y then
    window:attr('x', globals.win_x)
    window:attr('y', globals.win_y)
  end

end

init()