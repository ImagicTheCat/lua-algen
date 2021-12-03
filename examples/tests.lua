package.path = "src/?.lua;"..package.path

local ffi = require("ffi")
local algen = require("algen")

local function errcheck(perr, f, ...)
  local ok, err = pcall(f, ...)
  assert(not ok and not not err:find(perr))
end

do -- Check generator correctness with LuaJIT's math.random.
  for s=0,2 do
    math.randomseed(s)
    local g = algen.generator(s)
    for i=1,100 do
      assert(math.random() == g())
      assert(math.random(100) == g:random(100)) -- g:random() == g()
      assert(math.random(50, 100) == g(50, 100))
    end
  end
end
do -- Check uint64_t random.
  local g = algen.generator()
  assert(ffi.istype("uint64_t", g:randomU64()))
  assert(g:randomU64() ~= g:randomU64())
end
do -- Check state load/save.
  local g = algen.generator()
  local state = g:save()
  local t = {}; for i=1,10 do t[i] = g() end
  g:load(state); assert(state == g:save())
  -- check sequence
  for i=1,10 do assert(t[i] == g()) end
end
do -- Check platform state load/save and generation.
  -- state of seed 42 after 10 iterations
  local state = "\xB3\xCC\xB1\x89\x1D\xD7\xFC\x2F\x6D\xAF\x13\x08\x1B\xDD\xF0\x5D\xC5\x9D\x34\x49\xF0\xFA\xDF\x12\x4D\xBA\x7B\x7C\xF9\x03\x09\xA2"
  local expected_result = "60218273736083316299561950935886675883429748977957665304013622"
  -- compute
  local g = algen.generator()
  g:load(state)
  local s = ""; for i=1,32 do s = s..g(0,99) end
  assert(s == expected_result)
end
do -- Check errors.
  local g = algen.generator()
  errcheck("seed must be a number", algen.generator, 0ULL)
  errcheck("invalid state data", g.load, g, "state")
end
