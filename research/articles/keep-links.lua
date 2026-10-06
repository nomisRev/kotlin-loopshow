-- Prepares one part of a bundled book (the tutorial or one KEEP) so that all parts
-- can be concatenated into a single EPUB with working cross-references.
--
-- Environment:
--   BOOK    space-separated file stems in the book, primary KEEPs first
--           (e.g. "KEEP-0454-better-... 0001-value-classes")
--   PREFIX  id of the part being processed ("tutorial" or a book id)
--   IS_KEEP "1" when the part is an original KEEP: its first H1 is replaced
--           by the chapter heading the build script adds
--   GITHUB_BASE  optional, see below
--   STANDALONE   optional, see below

local PREFIX = os.getenv("PREFIX")
local IS_KEEP = os.getenv("IS_KEEP") == "1"
-- optional: GitHub folder URL that unresolved relative links are resolved against
local GITHUB_BASE = os.getenv("GITHUB_BASE")
-- "1" for a KEEP converted on its own: keep its title heading
local STANDALONE = os.getenv("STANDALONE") == "1"

local function id_for(stem)
  local num, rest = stem:match("^KEEP%-(%d+)%-(.*)$")
  if num then return "keep-" .. num .. "-" .. rest:lower() end
  return "note-" .. stem:lower()
end

local by_stem, by_num, by_suffix = {}, {}, {}
for stem in (os.getenv("BOOK") or ""):gmatch("%S+") do
  local id = id_for(stem)
  by_stem[stem:lower()] = id
  local num, rest = stem:match("^KEEP%-(%d+)%-(.*)$")
  if num then
    by_num[num] = by_num[num] or id
    by_suffix[rest:lower()] = id
  end
end

-- identifier of the KEEP title heading the build script replaces
local title_id = nil

local function local_id(id)
  return PREFIX .. "--" .. id
end

-- Maps a link target to an in-book anchor, or returns nil to keep it as is.
local function resolve(target)
  if target:sub(1, 1) == "#" then
    local frag = target:sub(2)
    if IS_KEEP then frag = frag:lower() end
    if frag == title_id then return "#" .. PREFIX end
    return "#" .. local_id(frag)
  end
  local is_keep_repo = target:find("github.com/Kotlin/KEEP", 1, true)
  if target:match("^%a+:") and not is_keep_repo then return nil end
  local stem, frag = target:match("([%w%._%-]+)%.md(#?.*)$")
  if not stem then return nil end
  local key = stem:lower()
  local id = by_stem[key] or by_suffix[key]
  if not id then
    local num = stem:match("^KEEP%-(%d+)")
    if num then id = by_num[string.format("%04d", tonumber(num))] end
  end
  if not id then return nil end
  if frag ~= "" then return "#" .. id .. "--" .. frag:sub(2) end
  return "#" .. id
end

local function fix_raw(text)
  text = text:gsub('(%s)id="([^"]+)"', function(sp, v)
    return sp .. 'id="' .. local_id(v) .. '"'
  end)
  text = text:gsub('(%s)name="([^"]+)"', function(sp, v)
    return sp .. 'id="' .. local_id(v) .. '"'
  end)
  text = text:gsub('href="([^"]+)"', function(v)
    return 'href="' .. (resolve(v) or v) .. '"'
  end)
  -- e-ink: no collapsible sections, always show the content
  text = text:gsub("</?details[^>]*>", "")
  text = text:gsub("<summary>(.-)</summary>", "<p><strong>%1</strong></p>")
  -- EPUB pages are XHTML: void elements must be self-closed
  for _, tag in ipairs({ "br", "hr", "img" }) do
    text = text:gsub("<(" .. tag .. "[^>]-)%s*/?>", "<%1/>")
  end
  -- side-by-side HTML tables with code cells: stack the cells instead
  for _, tag in ipairs({ "table", "thead", "tbody", "tr", "td", "th" }) do
    text = text:gsub("</?" .. tag .. "[^>]*>", "")
  end
  return text
end

local HTML_TAGS = {}
for t in ([[a b i u s em strong code pre kbd sub sup small span div p br hr
  img ul ol li dl dt dd details summary table thead tbody tr td th
  blockquote h1 h2 h3 h4 h5 h6]]):gmatch("%S+") do
  HTML_TAGS[t] = true
end

local function with_id(el)
  if el.identifier and el.identifier ~= "" then
    el.identifier = local_id(el.identifier)
  end
  return el
end

-- Turns plain "KEEP-367" / "KEEP-0367" mentions into links when that KEEP is in the book.
local function link_mentions(s)
  local before, num, after = s.text:match("^(.-)KEEP%-(%d+)(.*)$")
  if not num then return nil end
  local id = by_num[string.format("%04d", tonumber(num))]
  if not id then return nil end
  local out = pandoc.List()
  if before ~= "" then out:insert(pandoc.Str(before)) end
  -- non-breaking hyphen: keeps the link text from matching again
  out:insert(pandoc.Link(pandoc.Str("KEEP\u{2011}" .. num), "#" .. id, "",
    pandoc.Attr("", { "keep-ref" })))
  if after ~= "" then out:insert(pandoc.Str(after)) end
  return out
end

local structure = {
  Pandoc = function(doc)
    if not IS_KEEP or STANDALONE then return doc end
    local blocks, dropped, h1s = pandoc.List(), false, 0
    for _, b in ipairs(doc.blocks) do
      if b.t == "Header" and b.level == 1 then h1s = h1s + 1 end
    end
    for _, b in ipairs(doc.blocks) do
      if not dropped and b.t == "Header" and b.level == 1 then
        dropped = true
        title_id = b.identifier
      else
        if b.t == "Header" and h1s > 1 then b.level = b.level + 1 end
        blocks:insert(b)
      end
    end
    doc.blocks = blocks
    return doc
  end,
}

local links = {
  traverse = "topdown",
  Header = function(el)
    with_id(el)
    return el, false
  end,
  Div = with_id,
  Span = with_id,
  CodeBlock = with_id,
  Code = with_id,
  Link = function(el)
    if el.classes:includes("keep-ref") then return el, false end
    with_id(el)
    local resolved = resolve(el.target)
    if not resolved and GITHUB_BASE and not el.target:match("^%a+:") then
      -- relative repo link to something outside the book: point to GitHub
      resolved = GITHUB_BASE .. el.target
    end
    el.target = resolved or el.target
    return el, false
  end,
  Str = link_mentions,
  RawInline = function(el)
    if not el.format:match("html") then return el end
    -- prose like "<clinit>" is not HTML: show it as text
    local tag = el.text:match("^</?(%a[%w]*)>$")
    if tag and not HTML_TAGS[tag:lower()] then return pandoc.Str(el.text) end
    el.text = fix_raw(el.text)
    return el
  end,
  RawBlock = function(el)
    if el.format:match("html") then el.text = fix_raw(el.text) end
    return el
  end,
}

return { structure, links }
