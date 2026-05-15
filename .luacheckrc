std = "luajit"
cache = true
codes = true

self = false

globals = {
  "vim",
}

exclude_files = {
  "doc/",
}

-- Tweak strictness for plugin idioms.
ignore = {
  "212",  -- unused argument
  "631",  -- line too long
}
