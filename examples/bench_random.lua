-- Benchmark random.
-- usage: <baseline|generator> [n]
package.path = "src/?.lua;"..package.path

local algen = require("algen")

local mode, n = ...
n = tonumber(n) or 1e6

local v
if mode == "baseline" then
  for i=1,n do v = math.random() end
elseif mode == "generator" then
  local g = algen.generator()
  for i=1,n do v = g:random() end
else error("invalid mode "..tostring(mode)) end
print(v)
