local AgendaFilter = require('orgmode.agenda.filter')
local Files = require('orgmode.parser.files')
local Range = require('orgmode.parser.range')
local utils = require('orgmode.utils')
local agenda_highlights = require('orgmode.colors.highlights')
local date = require('orgmode.objects.date')
local hl_map = agenda_highlights.get_agenda_hl_map()

local function sort_todos(todos)
  table.sort(todos, function(a, b)
    if a:get_priority_sort_value() ~= b:get_priority_sort_value() then
      return a:get_priority_sort_value() > b:get_priority_sort_value()
    end
    return a.category < b.category
  end)
  return todos
end

---@class AgendaTodosView
---@field items table[]
---@field content table[]
---@field highlights table[]
---@field header string
---@field search string
---@field filters AgendaFilter
---@field win_width number
local AgendaTodosView = {}

function AgendaTodosView:new(opts)
  opts = opts or {}
  local data = {
    content = {},
    highlights = {},
    items = {},
    search = opts.search or '',
    filters = opts.filters or AgendaFilter:new(),
    header = opts.org_agenda_overriding_header,
    win_width = opts.win_width or utils.winwidth(),
  }

  setmetatable(data, self)
  self.__index = self
  return data
end

function AgendaTodosView:build()
  self.items = {}
  for _, orgfile in ipairs(Files.all()) do
    for _, headline in ipairs(orgfile:get_unfinished_todo_entries()) do
      if self:_is_unscheduled_or_past(headline) then
        if self.filters:matches(headline) then
          table.insert(self.items, headline)
        end
      end
    end
  end

  self.content = { { line_content = 'Global list of TODO items of type: ALL' } }
  self.highlights = {}
  self.active_view = 'todos'
  self.generate_view(self.items, self.content, self.filters, self.win_width)
  return self
end

function AgendaTodosView:_is_unscheduled_or_past(headline)
  local scheduled_date = headline:get_scheduled_date()
  if scheduled_date == nil then
    return true
  end
  local adjusted_date = scheduled_date:get_adjusted_date()
  local today = date:today()
  if adjusted_date:is_same_or_before(today, 'day') then
    return true
  end
  return false
end

function AgendaTodosView.generate_view(items, content, filters, win_width)
  items = sort_todos(items)
  local offset = #content
  local longest_category = utils.reduce(items, function(acc, todo)
    return math.max(acc, vim.api.nvim_strwidth(todo:get_category()))
  end, 0)

  for i, headline in ipairs(items) do
    if filters:matches(headline) then
      table.insert(content, AgendaTodosView.generate_todo_item(headline, longest_category, i + offset, win_width))
    end
  end

  return { items = items, content = content }
end

function AgendaTodosView.generate_todo_item(headline, longest_category, line_nr, win_width)
  local category = '  ' .. utils.pad_right(string.format('%s:', headline:get_category()), longest_category + 1)
  local todo_keyword = headline.todo_keyword.value
  local todo_keyword_padding = todo_keyword ~= '' and ' ' or ''
  local line = string.format('  %s%s%s %s', category, todo_keyword_padding, todo_keyword, headline.title)
  if #headline.tags > 0 then
    local tags_string = headline:tags_to_string()
    local padding_length = math.max(1, win_width - vim.api.nvim_strwidth(line) - vim.api.nvim_strwidth(tags_string))
    local indent = string.rep(' ', padding_length)
    line = string.format('%s%s%s', line, indent, tags_string)
  end
  local todo_keyword_pos = category:len() + 4
  local highlights = {}
  if headline.todo_keyword.value ~= '' then
    table.insert(highlights, {
      hlgroup = hl_map[headline.todo_keyword.value] or hl_map[headline.todo_keyword.type],
      range = Range:new({
        start_line = line_nr,
        end_line = line_nr,
        start_col = todo_keyword_pos,
        end_col = todo_keyword_pos + todo_keyword:len(),
      }),
    })
  end
  if headline:is_clocked_in() then
    table.insert(highlights, {
      range = Range:new({
        start_line = line_nr,
        end_line = line_nr,
        start_col = 1,
        end_col = 0,
      }),
      hl_group = 'Visual',
      whole_line = true,
    })
  end
  return {
    line_content = line,
    longest_category = longest_category,
    line = line_nr,
    jumpable = true,
    file = headline.file,
    file_position = headline.range.start_line,
    headline = headline,
    highlights = highlights,
  }
end

return AgendaTodosView
